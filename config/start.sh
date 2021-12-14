#!/bin/sh
test -f /secrets/dotenv && cp /secrets/dotenv /app/.env
sed -i -e s/__PORT__/${PORT:-8080}/g /app/config/nginx.conf
#supervisord -n -c /app/config/supervisord.conf
php-fpm8 -R -c /app/config/php.ini -y /app/config/fpm-pool.conf
nginx -c /app/config/nginx.conf -g 'daemon off;'
