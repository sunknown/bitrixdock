FROM phpdockerio/php:8.2-fpm

LABEL org.opencontainers.image.source="https://github.com/bitrixdock/bitrixdock"

# Install necessary packages
RUN apt-get update \
    && apt-get -y --no-install-recommends install \
    php8.2-gd \
    php8.2-imagick \
    php8.2-intl \
    php8.2-interbase \
    php8.2-mbstring \
    php8.2-mcrypt \
    php8.2-memcache \
    php8.2-memcached \
    php8.2-mysql \
    php8.2-opcache \
    php8.2-soap \
    php8.2-zip \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/*

COPY ./php.ini /etc/php/8.2/fpm/conf.d/90-php.ini
COPY ./php.ini /etc/php/8.2/cli/conf.d/90-php.ini

# Copy custom PHP-FPM configuration files
COPY ./www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY ./php-fpm.conf /etc/php/8.2/fpm/php-fpm.conf

RUN usermod -u 1000 www-data

RUN echo "www-data" > /etc/cron.deny && chmod 644 /etc/cron.deny

WORKDIR "/var/www/bitrix"

EXPOSE 9000

CMD ["php-fpm8.2", "--nodaemonize", "--fpm-config", "/etc/php/8.2/fpm/php-fpm.conf"]
