#!/bin/bash

#variable declaration
export WEB1_IP="125.231.56.11"
export WEB2_IP="125.231.56.44"
export DB1_IP="125.231.56.22"
export DB2_IP="125.231.56.33"
export DNS1_IP="125.231.56.55"

name=${1:?"Did not enter a value in the first argument."}
domain=${2:?"Did not enter a value in the second argument."}

#web server ip settings
function web_ip_settings(){
	echo -n "Choose a web server IP(1/2) : "
	read cho
	case $cho in
		1 )
			WEB_IP=$WEB1_IP
			;;
		2 )
			WEB_IP=$WEB2_IP
			;;
	esac
}

#new domain settings
function new_domain_settings(){
	local cho

	echo -n "Do you want to use the new domain?(y/n) : "
	read cho
	case $cho in
		y )
			echo -n "enter the new domain : "
			read domain
			;;
		n )
			break
			;;
	esac
}

#add user and password settings
function useradd_settings(){
	local cho

	if grep "$name" /etc/passwd >& /dev/null; then
		echo -n "The name that already exists. Are you sure you want to re-enter?(y/n) : "
		read cho

		case $cho in
			y )
				echo -n "enter name : "
				read name
				;;
			n )
				echo "end"
				exit 0
				;;
		esac
	else
		useradd -m -s /bin/false -d /home/$name -g teamlog $name
		passwd $name

		chmod 755 /home/$name
		chown root:teamlog /home/$name

		mkdir -p /home/$name/public_html
		mkdir -p /home/$name/httpd/log/
		mkdir -p /home/$name/nginx/log/

		touch /home/$name/httpd/log/$domain-error_log
		touch /home/$name/httpd/log/$domain-access_log
		touch /home/$name/nginx/log/$domain-error_log
		touch /home/$name/nginx/log/$domain-access_log

		find /home/$name/ -type f -exec chmod 644 {} \;
		find /home/$name/ -type d -exec chmod 755 {} \;
		chown -R $name:teamlog /home/$name/
	fi
}

#quota settings
function quota_settings(){
	local cho
	local group

	while [[ cho != 6 ]]; do
		echo "quota settings"

		cat <<- ENDIT
			1) quotacheck
			2) quotaon
			3) quotaoff
			4) quotauser
			5) quotagroup
			6) end
		ENDIT

		read cho
		case $cho in
			1 )
				quotacheck -avug
				;;
			2 )
				quotaon -avugm
				;;
			3 )
				quotaoff
				;;
			4 )
				edquota -u $name
				;;
			5 )
				echo -n "enter the group name : "
				read group
				edquota -g $group
				;;
			6 )
				break
				;;
		esac
	done
}

#virtualhost settings
function virtualhost_settings(){
	local cho

	rm -f /tmp/httpd.conf
	rm -f /tmp/nginx.conf

	touch /tmp/httpd.conf
	touch /tmp/nginx.conf

	#vi /etc/httpd/conf.d/$domain.conf
	echo "<VirtualHost *:8080>" >> /tmp/httpd.conf
	echo "    ServerAdmin $name@$domain" >> /tmp/httpd.conf
	echo "    DocumentRoot /home/$name/public_html" >> /tmp/httpd.conf
	echo "    ServerName $domain" >> /tmp/httpd.conf
	echo "    ErrorLog /home/$name/httpd/log/$domain-error_log" >> /tmp/httpd.conf
	echo "    CustomLog /home/$name/httpd/log/$domain-access_log common" >> /tmp/httpd.conf
	echo "</VirtualHost>" >> /tmp/httpd.conf
	cat /tmp/httpd.conf > /etc/httpd/conf.d/$domain.conf
	service httpd reload

	#vi /etc/nginx/conf.d/$domain.conf
	echo "server {" >> /tmp/nginx.conf
	echo "    listen 80;" >> /tmp/nginx.conf
	echo "    server_name $domain;" >> /tmp/nginx.conf
	echo "    access_log /home/$name/nginx/log/$domain-access_log;" >> /tmp/nginx.conf
	echo "    error_log /home/$name/nginx/log/$domain-error_log crit;" >> /tmp/nginx.conf
	echo "    location ~* .(gif|jpg|jpeg|png|ico|wmv|3gp|avi|mpg|mpeg|mp4|flv|mp3|mid|js|css|html|htm|wml)$ {" >> /tmp/nginx.conf
	echo "        root /home/$name/public_html;" >> /tmp/nginx.conf
	echo "    }" >> /tmp/nginx.conf
	echo "    location / {" >> /tmp/nginx.conf
	echo "        proxy_send_timeout   90;" >> /tmp/nginx.conf
	echo "        proxy_read_timeout   90;" >> /tmp/nginx.conf
	echo "        proxy_buffer_size    128k;" >> /tmp/nginx.conf
	echo "        proxy_buffers     4 256k;" >> /tmp/nginx.conf
	echo "        proxy_busy_buffers_size 256k;" >> /tmp/nginx.conf
	echo "        proxy_temp_file_write_size 256k;" >> /tmp/nginx.conf
	echo "        proxy_connect_timeout 30s;" >> /tmp/nginx.conf
	echo "        proxy_redirect  http://$domain:8080   http://$domain;" >> /tmp/nginx.conf
	echo "        proxy_pass   http://127.0.0.1:8080;" >> /tmp/nginx.conf
	echo "        proxy_set_header   Host   \$host;" >> /tmp/nginx.conf
	echo "        proxy_set_header   X-Real-IP  \$remote_addr;" >> /tmp/nginx.conf
	echo "        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;" >> /tmp/nginx.conf
	echo "    }" >> /tmp/nginx.conf
	echo "}" >> /tmp/nginx.conf
	cat /tmp/nginx.conf > /etc/nginx/conf.d/$domain.conf
	service nginx reload
}

#dns new zones settings
function dns_new_zones_settings(){
	#vi /etc/named.rfc1912.zones
	ssh -o StrictHostKeyChecking=yes -l root $DNS1_IP "
	rm -f /tmp/named.zones;
	touch /tmp/named.zones;
	echo "zone \"$domain\" {" >> /tmp/named.zones;
	echo "        type master\;" >> /tmp/named.zones;
	echo "        file \"$domain.zone\"\;" >> /tmp/named.zones;
	echo "        allow-update { none\; }\;" >> /tmp/named.zones;
	echo "}\;" >> /tmp/named.zones;
	cat /tmp/named.zones >> /etc/named.rfc1912.zones;
	service named reload;"
}

#dns new zone settings
function dns_new_zone_settings(){
	#vi /var/named/$domain.zone
	ssh -o StrictHostKeyChecking=yes -l root $DNS1_IP "
	rm -f /tmp/named.zone;
	touch /tmp/named.zone;
	echo "\$TTL   86400"
	echo "@       IN      SOA   @  root  \(" >> /tmp/named.zone;
	echo "                                20000402  \; Serial" >> /tmp/named.zone;
	echo "                                21600   \; Refresh\(6h\)" >> /tmp/named.zone;
	echo "                                900     \; Retry\(15min\)" >> /tmp/named.zone;
	echo "                                604800  \; Expire\(7d\)" >> /tmp/named.zone;
	echo "                                43200\)  \; Minimum\(12h\)" >> /tmp/named.zone;
	echo "                IN      NS      ns.example.com." >> /tmp/named.zone;
	echo "                IN      A       $DNS1_IP" >> /tmp/named.zone;
	echo "                IN      A       $WEB_IP" >> /tmp/named.zone;
	cp /tmp/named.zone /var/named/$domain.zone;
	service named reload;"
}

#dns new zone settings
function dns_add_zone_settings(){
	#vi /var/named/$domain.zone
	ssh -o StrictHostKeyChecking=yes -l root $DNS1_IP "
	rm -f /tmp/named.zone;
	touch /tmp/named.zone;
	echo "$name          IN      A       $WEB_IP" >> /tmp/named.zone;
	cat /tmp/named.zone >> /var/named/$domain.zone;
	service named reload;"
}

#mariadb settings
function mariadb_settings(){
	local db_pass

	echo -n "Enter the database connection password. : "
	read -s db_pass
	echo ""

	mysql -h $DB1_IP -u root -p -e "CREATE DATABASE $name; GRANT ALL PRIVILEGES ON $name.* TO '$name'@'%' IDENTIFIED BY '$db_pass'; FLUSH PRIVILEGES;"
	mysql -h $DB2_IP -u root -p -e "GRANT ALL PRIVILEGES ON $name.* TO '$name'@'%' IDENTIFIED BY '$db_pass'; FLUSH PRIVILEGES;"

	echo "master ip is $DB1_IP, slave ip is $DB2_IP"
	echo "If you want to use the phpmyadmin go to db.example.com."
}

#main
function main(){
	echo "    ____             __ _ _        _        __  "
	echo "   / ___|___  _ __  / _(_) | ___  (_)_ __  / _| ___  "
	echo "  | |   / _ \| '_ \| |_| | |/ _ \ | | '_ \| |_ / _ \  "
	echo "  | |__| (_) | | | |  _| | |  __/_| | | | |  _| (_) |  "
	echo "   \____\___/|_| |_|_| |_|_|\___(_)_|_| |_|_|  \___/  "
	echo ""
	echo "#  coding: utf-8"
	echo "#  name: webhosting.sh"
	echo "#  version: 1.8"
	echo "#  Copyright 2015 jeonghyeon <wyun13043@daum.net>"
	echo ""

	local cho

	while [[ cho != 9 ]]; do
		echo "name: $name"
		echo "domain: $domain"

		cat <<- ENDIT
			1) web_ip_settings
			2) new_domain_settings
			3) useradd_settings
			4) quota_settings
			5) virtualhost_settings
			6) dns_new_zones_settings
			7) dns_new_zone_settings
			8) dns_add_zone_settings
			9) mariadb_settings
			10) end
		ENDIT

		echo -n "choice number : "
		read cho
		case $cho in
			1 )
				web_ip_settings
				;;
			2 )
				new_domain_settings
				;;
			3 )
				useradd_settings
				;;
			4 )
				quota_settings
				;;
			5 )
				virtualhost_settings
				;;
			6 )
				dns_new_zones_settings
				;;
			7 )
				dns_new_zone_settings
				;;
			8 )
				dns_add_zone_settings
				;;
			9 )
				mariadb_settings
				;;
			10 )
				exit
				;;

		esac
	done
}
main