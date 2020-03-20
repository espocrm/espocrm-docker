FROM php:7.3-fpm-alpine

# Install php libs
RUN set -ex; \
    apk update; \
    apk add --no-cache --virtual .build-deps \
        libzip-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        libwebp-dev \
        php7-gd \
        php7-exif \
        openldap-dev \
        imap-dev \
        git \
        bash \
        $PHPIZE_DEPS \
    ; \
    \
# Install php-zmq
    cd /usr; \
    curl -fSL https://github.com/zeromq/libzmq/releases/download/v4.3.2/zeromq-4.3.2.tar.gz -o zeromq-4.3.2.tar.gz; \
    tar -xvzf zeromq-4.3.2.tar.gz; \
    rm zeromq-4.3.2.tar.gz; \
    cd /usr/zeromq-4.3.2; \
    ./configure; \
    make; \
    make install; \
    cd /usr; \
    git clone git://github.com/mkoppanen/php-zmq.git; \
    cd /usr/php-zmq; \
    phpize && ./configure; \
    make; \
    make install; \
    \
# END Instalation php-zmq
    docker-php-ext-configure gd --with-jpeg-dir=/usr/include/ --with-webp-dir=/usr/include/; \
    docker-php-ext-install gd; \
    docker-php-ext-install exif; \
    docker-php-ext-install ldap; \
    docker-php-ext-install imap; \
    docker-php-ext-install pcntl; \
    docker-php-ext-install zip; \
    docker-php-ext-install pdo_mysql; \
    docker-php-ext-enable zmq

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

ENV DOCUMENT_ROOT /var/www/html
ENV DEFAULT_OWNER www-data
ENV DEFAULT_GROUP www-data

ENV ESPOCRM_VERSION 5.8.4
ENV ESPOCRM_SHA256 2337cfc0bee01518bd1d44813b5bf53e82dc677ab0220195b731e817ef373113

ENV ESPOCRM_UPGRADE_VERSION 5.7.11
ENV ESPOCRM_UPGRADE_URL https://www.espocrm.com/downloads/upgrades/EspoCRM-upgrade-5.7.11-to-5.8.4.zip
ENV ESPOCRM_UPGRADE_SHA256 7a4e1720499b897ff3ede69782215d0c4d13d080c5e7dde62ee80807da8e6ae6

VOLUME ${DOCUMENT_ROOT}

RUN set -ex; \
    curl -fSL "https://www.espocrm.com/downloads/EspoCRM-5.8.4.zip" -o EspoCRM.zip; \
	echo "${ESPOCRM_SHA256} *EspoCRM.zip" | sha256sum -c -; \
    unzip -q EspoCRM.zip -d /usr/src; \
    mv "/usr/src/EspoCRM-5.8.4" /usr/src/espocrm; \
	rm EspoCRM.zip; \
    mkdir /usr/src/espocrm-upgrades; \
    chown -R ${DEFAULT_OWNER}:${DEFAULT_GROUP} /usr/src/espocrm /usr/src/espocrm-upgrades

COPY ./docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT [ "docker-entrypoint.sh" ]

RUN (crontab -l -u ${DEFAULT_OWNER}; echo "* * * * * cd ${DOCUMENT_ROOT}; /usr/local/bin/php -f cron.php > /dev/null 2>&1") | crontab - -u ${DEFAULT_OWNER}

CMD ["sh", "-c", "crond && php-fpm"]
