#!/bin/bash
#auth：Install FastDFS Service

#Global variable loading
source /etc/profile
#Set the time zone
timedatectl  set-timezone Asia/Shanghai

#Close selinux
sudo setenforce 0 && getenforce
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux

#time synchronization
yum -y install epel-release
yum makecache
yum -y install net-tools
yum -y update vim*
yum -y install ntp* && systemctl enable ntpd
systemctl start ntpd && systemctl enable ntpd
yum -y install curl wget git unzip lrzsz

#SSH configuration
sed -i 's/#UseDNS yes/UseDNS no/g' /etc/ssh/sshd_config
systemctl restart sshd && systemctl enable sshd

#Configuration aliyun yum
mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo

#Configuration depends on
yum install -y gcc gcc-c++ libevent pcre pcre-devel zlib zlib-devel openssl openssl-devel 

#Install libfastcommon
tar xf ./libfastcommon-1.0.7.tgz -C /usr/local/src/
cd /usr/local/src/libfastcommon-1.0.7/
./make.sh && ./make.sh install

#Copy the libfastcommon library file
\cp -rf /usr/lib64/libfastcommon.so /usr/lib && ls -ll /usr/lib/libfastcommon.so

#Back to root
cd /root/fastdfs

#Install FastDFS
mkdir -pv /home/fdfs_storage
mkdir -pv /home/fastdfs
tar xf ./FastDFS_v5.05.tgz -C /usr/local/src/
cd  /usr/local/src/FastDFS/
./make.sh && ./make.sh install
cd /root/fastdfs
tar xf ./fastdfs_file_v1.0.tgz -C /etc/fdfs/

#Back to root
cd /root/fastdfs
#Installation of nginx services
mkdir -pv /var/temp/nginx/client
tar xf ./nginx-1.8.0.tar.gz -C /usr/local/src/
cd /root/fastdfs/
tar xf ./fastdfs-nginx-module_v1.16.tgz -C  /usr/local/src/
\cp -rf /usr/lib64/libfdfsclient.so /usr/lib/
cd /usr/local/src/nginx-1.8.0/
./configure \
--prefix=/usr/local/nginx \
--pid-path=/var/run/nginx/nginx.pid \
--lock-path=/var/lock/nginx.lock \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--with-http_gzip_static_module \
--http-client-body-temp-path=/var/temp/nginx/client \
--http-proxy-temp-path=/var/temp/nginx/proxy \
--http-fastcgi-temp-path=/var/temp/nginx/fastcgi \
--http-uwsgi-temp-path=/var/temp/nginx/uwsgi \
--http-scgi-temp-path=/var/temp/nginx/scgi \
--add-module=/usr/local/src/fastdfs-nginx-module/src
make && make install


#Configure and start tracker
cd /root/fastdfs
/usr/bin/fdfs_trackerd /etc/fdfs/tracker.conf restart
#Configure and start storage
sed -i 's/tracker_server=IPADDR:22122/tracker_server=default_ip:22122/g' /etc/fdfs/storage.conf
/usr/bin/fdfs_storaged /etc/fdfs/storage.conf restart
#Configure and client
sed -i 's/tracker_server=IPADDR:22122/tracker_server=default_ip:22122/' /etc/fdfs/client.conf
#Configuration and nginx file
sed -i 's/tracker_server=IPADDR:22122/tracker_server=default_ip:22122/' /etc/fdfs/mod_fastdfs.conf

#Create log directory
mkdir -pv  /usr/local/nginx/logs 

##Configure and nginx file
sudo tee /etc/profile.d/nginx.sh <<-'EOF'
export NGINX_HOME=/usr/local/nginx
export PATH=$PATH:$NGINX_HOME/sbin
EOF
source /etc/profile.d/nginx.sh
sudo tee /usr/local/nginx/conf/nginx.conf <<-'EOF'
user  nobody nobody;
worker_processes  4;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;
pid        logs/nginx.pid;

events {
    use epoll;
    worker_connections 51200;
    multi_accept on;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
    access_log  logs/access.log  main;

    sendfile        on;
    tcp_nopush     on;
    keepalive_timeout  65;
    gzip  on;
    server {
        listen       80;
        server_name  localhost;
        access_log  logs/host.access.log  main;

        location / {
            root   html;
            index  index.html index.htm;
        }

        location /group1/M00 {
            root /home/fdfs_storage/data;
            ngx_fastdfs_module;
        }
        error_page  404              /404.html;
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }
}
EOF

#Configure and start nginx file 
sudo tee /lib/systemd/system/nginx.service <<-'EOF'
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/usr/local/nginx/logs/nginx.pid
ExecStartPre=/usr/local/nginx/sbin/nginx -t
ExecStart=/usr/local/nginx/sbin/nginx
ExecReload=/usr/local/nginx/sbin/nginx -s reload
ExecStop=/usr/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
#Start nginx
systemctl daemon-reload && systemctl restart nginx

#Close the firewall
systemctl stop firewalld && systemctl disable firewalld
firewall-cmd --state

#Create access image
/usr/bin/fdfs_test /etc/fdfs/client.conf upload /root/fastdfs/22.jpg

