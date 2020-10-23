FROM php:7.3-fpm-alpine

# Install php libs
RUN set -ex; \
    apk add --no-cache --virtual .build-deps \
        libzip-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        libwebp-dev \
        openldap-dev \
        imap-dev \
        git \
        libzmq \
        zeromq-dev \
        bash \
        $PHPIZE_DEPS \
    ; \
    \
# Install php-zmq
    cd /usr; \
    git clone https://github.com/zeromq/php-zmq.git; \
    cd /usr/php-zmq && git checkout e0db82c3286da81fa8945894dd10125a528299e4; \
    phpize && ./configure; \
    make; \
    make install; \
# END: Install php-zmq
    \
    docker-php-ext-configure gd --with-jpeg-dir=/usr/include/ --with-webp-dir=/usr/include/; \
    docker-php-ext-install gd; \
    docker-php-ext-install exif; \
    docker-php-ext-install ldap; \
    docker-php-ext-install imap; \
    docker-php-ext-install pcntl; \
    docker-php-ext-install zip; \
    docker-php-ext-install pdo_mysql; \
    docker-php-ext-enable zmq

RUN set -ex; \
    rm /var/spool/cron/crontabs/root; \
    echo '* * * * * cd /var/www/html; /usr/local/bin/php -f cron.php > /dev/null 2>&1' > /var/spool/cron/crontabs/www-data

# php.ini
RUN { \
	echo 'expose_php = Off'; \
	echo 'display_errors = Off'; \
	echo 'display_startup_errors = Off'; \
	echo 'log_errors = On'; \
	echo 'memory_limit=256M'; \
	echo 'max_execution_time=180'; \
	echo 'max_input_time=180'; \
	echo 'post_max_size=30M'; \
	echo 'upload_max_filesize=30M'; \
	echo 'date.timezone=UTC'; \
} > ${PHP_INI_DIR}/conf.d/espocrm.ini

ENV ESPOCRM_VERSION 6.0.0
ENV ESPOCRM_SHA256 bfc069e1291569185dfce20f3ff951465806420c48ad2e84e1320ab211801245

ENV ESPOCRM_UPGRADE_VERSION 5.9.4
ENV ESPOCRM_UPGRADE_URL https://www.espocrm.com/downloads/upgrades/EspoCRM-upgrade-5.9.4-to-6.0.0.zip
ENV ESPOCRM_UPGRADE_SHA256 5c3fc704abf3ac385bef2e6a12c968af036c81b0be2812eea4ebf3cca274ead9

WORKDIR /var/www/html

RUN set -ex; \
    curl -fSL "https://www.espocrm.com/downloads/EspoCRM-6.0.0.zip" -o EspoCRM.zip; \
	echo "${ESPOCRM_SHA256} *EspoCRM.zip" | sha256sum -c -; \
    unzip -q EspoCRM.zip -d /usr/src; \
    mv "/usr/src/EspoCRM-6.0.0" /usr/src/espocrm; \
	rm EspoCRM.zip; \
    mkdir /usr/src/espocrm-upgrades; \
    chown -R www-data:www-data /usr/src/espocrm /usr/src/espocrm-upgrades

COPY ./docker-entrypoint.sh /usr/local/bin/
COPY ./docker-cron.sh /usr/local/bin/
ENTRYPOINT [ "docker-entrypoint.sh" ]

CMD ["php-fpm"]
