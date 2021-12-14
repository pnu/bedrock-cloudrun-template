FROM alpine:3

RUN apk --no-cache add php8 php8-fpm php8-mysqli php8-json php8-openssl php8-curl \
    php8-zlib php8-xml php8-phar php8-intl php8-dom php8-xmlreader php8-ctype php8-session \
    php8-mbstring php8-gd nginx supervisor curl

WORKDIR /app

RUN php8 -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php8 composer-setup.php \
    && php8 -r "unlink('composer-setup.php');"

COPY composer.json composer.lock ./
RUN php8 composer.phar install --prefer-dist --no-dev --no-autoloader && rm -rf /root/.composer

COPY . .
RUN php8 composer.phar dump-autoload --no-dev --optimize

CMD ["config/start.sh"]
