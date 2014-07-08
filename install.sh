#!/bin/bash

#full path
MY_PATH=`dirname "$0"`

#Parse variables
source $MY_PATH/install.conf

#Fetch latest repodata
apt-get update
apt-get upgrade -y

#Disable interactive mode during the installation
export DEBIAN_FRONTEND=noninteractive

#Install software we need
apt-get install -y nginx php5-fpm git mysql-server php5-mysql phpmyadmin php5-curl unzip ntp tomcat7 apache2-utils

#Removing default nginx config
rm /etc/nginx/sites-enabled/default

#Creating directory for SSL certs
mkdir /etc/nginx/.ssl
cp $MY_PATH/ssl/* /etc/nginx/.ssl/
#Creating directories for static content and .htpasswd
mkdir -p $STATICDIR
mkdir -p $HTPASSDIR

#Configuring Tomcat memory allocation
sed -i "s/Xmx128m/Xmx${MEMORY}m/" /etc/default/tomcat7

#Nginx virtual host configuration
cat > /etc/nginx/sites-available/tomcat.conf << TOMCATCONF
server {
        listen 80;

        server_name $DOMAIN www.$DOMAIN default;

        location / {

        proxy_set_header X-Real-IP  \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Host \$host:\$server_port;
        proxy_pass http://127.0.0.1:8080;
        proxy_redirect default;
        }

        location ~ \.(png|gif|jpg|jpeg|js|css|swf|ttf|woff|eot|svg)$ {
                access_log off;
                root $STATICDIR;
                try_files \$uri \$uri/ =404;
                expires 7d;
        }

        location /phpmyadmin {
                access_log off;
                root /usr/share/;
                index index.php index.html index.htm;
                auth_basic            "Restricted";
                auth_basic_user_file  $HTPASSDIR/.htpasswd;
                location ~ ^/phpmyadmin/(.+\.php)\$ {
                        try_files \$uri =404;
                        root /usr/share/;
                        fastcgi_pass 127.0.0.1:9000;
                        fastcgi_index index.php;
                        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                        include /etc/nginx/fastcgi_params;
                        fastcgi_read_timeout 300;
                }
                location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))\$ {
                        root /usr/share/;
                }
        }
        location /phpMyAdmin {
                rewrite ^/* /phpmyadmin last;
        }

         location ~ /\.ht {
                deny all;
        }
}

server {
	listen 443;

	server_name $DOMAIN www.$DOMAIN default;

	ssl     on;
	ssl_ciphers         ALL:!ADH:!EXPORT56:RC4+RSA:+HIGH:+MEDIUM:+LOW:+SSLv3:+EXP:+eNULL;
	ssl_certificate     .ssl/tomcat.crt;
	ssl_certificate_key .ssl/tomcat.key;
	ssl_session_cache   shared:SSL:10m;
	ssl_session_timeout 60m;

	location / {

        proxy_set_header X-Real-IP  \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Host \$host:\$server_port;
        proxy_pass http://127.0.0.1:8080;
        proxy_redirect default;
        }

        location ~ \.(png|gif|jpg|jpeg|js|css|swf|ttf|woff|eot|svg)$ {
                access_log off;
                root $STATICDIR;
                try_files \$uri \$uri/ =404;
                expires 7d;
        }
}
TOMCATCONF

#Nginx configuration
mv /etc/nginx/nginx.conf /etc/nginx/nginx.default
cat > /etc/nginx/nginx.conf << NGINXCONF
user www-data;
worker_processes 2;
pid /var/run/nginx.pid;

events {
        worker_connections 10000;
        multi_accept on;
        use epoll;
}

http {

        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;
        types_hash_max_size 2048;
        # server_tokens off;
        # server_names_hash_bucket_size 64;
        # server_name_in_redirect off;

        include /etc/nginx/mime.types;
        default_type application/octet-stream;

        log_format loadtime '\$remote_addr - \$remote_user [\$time_local]  '
                    '\$request_time "\$request" \$status  \$body_bytes_sent '
                    '"\$http_referer" "\$http_user_agent" ';
        access_log off;
        error_log /var/log/nginx/error.log;

        gzip on;
        gzip_disable "MSIE [1-6]\.(?!.*SV1)";
        gzip_vary on;
        gzip_proxied any;
        gzip_comp_level 6;
        gzip_buffers 16 8k;
        gzip_http_version 1.1;
        gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;

        include /etc/nginx/sites-enabled/*;
}
NGINXCONF

#php-fpm pool configuration
rm /etc/php5/fpm/pool.d/www.conf
cat > /etc/php5/fpm/pool.d/www.conf << WWWCONF
[www]
user = www-data
group = www-data
listen = 127.0.0.1:9000
pm = ondemand
pm.max_children = 50
pm.start_servers = 2
pm.min_spare_servers = 2
pm.max_spare_servers = 6
pm.max_requests = 500
chdir = /
WWWCONF

#Linking available site to the enabled
ln -s /etc/nginx/sites-available/tomcat.conf /etc/nginx/sites-enabled/

#Root password configuration
echo "root:$ROOTPASS" | chpasswd

#Mysql DB creation and root password configuration
mysql -e "CREATE DATABASE ${DBNAME};"
cat $MY_PATH/mysqldamp.sql | mysql $DBNAME
mysqladmin -u root password $MYSQLPASS

htpasswd -c -b $HTPASSDIR/.htpasswd $HTPASSUSER $HTPASSUPASS

#Installing and configuring java
mkdir /root/tomcat7/java
tar -xvf $MY_PATH/jdk-7* -C $MY_PATH/java
mkdir /usr/lib/jvm
mv $MY_PATH/java/jdk1.7* /usr/lib/jvm/jdk1.7.0
update-alternatives --install "/usr/bin/java" "java" "/usr/lib/jvm/jdk1.7.0/bin/java" 1
update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib/jvm/jdk1.7.0/bin/javac" 1
update-alternatives --install "/usr/bin/javaws" "javaws" "/usr/lib/jvm/jdk1.7.0/bin/javaws" 1
chmod a+x /usr/bin/java
chmod a+x /usr/bin/javac
chmod a+x /usr/bin/javaws
echo 'JAVA_HOME=/usr/lib/jvm/jdk1.7.0' >> /etc/default/tomcat7

#Restarting NginX
service nginx restart

#Restarting php-fpm
service php5-fpm restart

#Restarting tomcat
service tomcat7 restart
