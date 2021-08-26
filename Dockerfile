FROM alpine:3

RUN apk --no-cache add php7 php7-fpm php7-mysqli php7-json php7-openssl php7-curl \
    php7-zlib php7-xml php7-phar php7-intl php7-dom php7-xmlreader php7-ctype php7-session \
    php7-mbstring php7-gd nginx supervisor curl

WORKDIR /app

RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
 && php composer-setup.php \
 && php -r "unlink('composer-setup.php');"

COPY composer.json composer.lock ./
RUN php composer.phar install --prefer-dist --no-dev --no-autoloader && rm -rf /root/.composer

COPY . .
RUN php composer.phar dump-autoload --no-dev --optimize

CMD ["config/start.sh"]
