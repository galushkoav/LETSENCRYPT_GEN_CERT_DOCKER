#!/bin/bash
set -e

DOMAIN="$1"
NGINX_CONFIG_DIR="/docker-compose/app/configs/nginx/deploy.d/"
LETSENCRYPT_CERT_DIR="/docker-compose/certbot/etc/letsencrypt"
LETSENCRYPT_VAR_DIR="/docker-compose/certbot/var/lib/letsencrypt"
LETSENCRYPT_LOG_DIR="/docker-compose/certbot/var/log/letsencrypt"
LETSENCRYPT_WEBROOT_DIR="/docker-compose/app/var/www/letsencrypt"
LETSENCRYPT_ADMIN_EMAIL="a.v.galushko@itc-life.ru"
function docker_nginx_reload () {
    echo "Reload nginx конфиг";
    docker exec $(docker ps | grep nginx-alpine | grep app | awk '{print $1}') nginx -s reload;
    sleep 2;
}

function docker_certbot_pull () {
    echo "Скачаем образ certbot/certbot последней версии"
    docker pull certbot/certbot
    echo "Готово"
}

function generate_ssl () {
    echo "Приступаем к получению сертификата для домена ${DOMAIN}"
    docker run -it --rm --name certbot -v "${LETSENCRYPT_CERT_DIR}:/etc/letsencrypt"  -v "${LETSENCRYPT_VAR_DIR}:/var/lib/letsencrypt" -v "${LETSENCRYPT_LOG_DIR}:/var/log/letsencrypt" -v "${LETSENCRYPT_WEBROOT_DIR}:/var/www/letsencrypt"  certbot/certbot certonly  --webroot -w /var/www/letsencrypt --email ${LETSENCRYPT_ADMIN_EMAIL} --text --no-eff-email --agree-tos   -d "${DOMAIN}" -d "www.${DOMAIN}"
    echo "Готово"
}

function generate_nginx_config_without_ssl() {
echo "Проверяем не был ли уже сгенерирован сертификат. Для этого проверим наличие директории ${NGINX_CONFIG_DIR}/${DOMAIN}.conf"
if  [ ! -f "${NGINX_CONFIG_DIR}/${DOMAIN}.conf" ]
then

    echo "Генериуем первоначальный конфиг для валидации домена"
cat <<OEF> ${NGINX_CONFIG_DIR}/${DOMAIN}.conf

server {
    listen 80;
    server_name
    ${DOMAIN}
    www.${DOMAIN}
    ;
    location ^~ /.well-known/acme-challenge/ {
           root /var/www/letsencrypt/;
    }
    location / {
            proxy_pass   http://backend-smart-uk.ru/;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-Server \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_connect_timeout 120;
            proxy_send_timeout 120;
            proxy_read_timeout 180;
           
    }
}

OEF
echo "Конфиг сгенерирован"
else
echo "Файл конфигурации ${NGINX_CONFIG_DIR}/${DOMAIN}.con уже существует. Выходим. Если что-то пошло не так удалите файл ${NGINX_CONFIG_DIR}/${DOMAIN}.conf"
exit
fi
}


function generate_nginx_config_with_ssl () {
echo "Теперь создадим конфиг с редиректом на https и подключим наш сертификат"

cat <<OEF> ${NGINX_CONFIG_DIR}/${DOMAIN}.conf

server {
    listen 80;
    server_name
    ${DOMAIN}
    www.${DOMAIN}
    ;
    location ^~ /.well-known/acme-challenge/ {
           root /var/www/letsencrypt/;
    }
    location / {
           return              301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name
    ${DOMAIN}
    www.${DOMAIN}
    ;
    ssl_protocols TLSv1.1 TLSv1.2;
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_prefer_server_ciphers on;
    ssl_dhparam /etc/nginx/dhparam.pem;
    ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHAAES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA';
    ssl_stapling on;
    ssl_verify_client         off;
    location ^~ /.well-known/acme-challenge/ {
           root /var/www/letsencrypt/;
          }
    location / {
            proxy_pass   http://backend-smart-uk.ru/;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-Server \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_connect_timeout 120;
            proxy_send_timeout 120;
            proxy_read_timeout 180;
           
    }
}
OEF
echo "Конфиг сгенерирован"
}

docker_certbot_pull
generate_nginx_config_without_ssl && docker_nginx_reload && generate_ssl && generate_nginx_config_with_ssl && docker_nginx_reload



