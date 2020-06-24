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
    git clone https://github.com/zeromq/php-zmq.git; \
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

ENV ESPOCRM_VERSION 5.9.3
ENV ESPOCRM_SHA256 b571d502de31a40d5e267c8658742f24ebc5c09245707306529b0d3f2e7c03bc

ENV ESPOCRM_UPGRADE_VERSION 5.8.5
ENV ESPOCRM_UPGRADE_URL https://www.espocrm.com/downloads/upgrades/EspoCRM-upgrade-5.8.5-to-5.9.3.zip
ENV ESPOCRM_UPGRADE_SHA256 188b1de2c5877737e2ecf78ed29c5e333fd6ee8108f44a400aca74b66d4b79c1

VOLUME ${DOCUMENT_ROOT}

RUN set -ex; \
    curl -fSL "https://www.espocrm.com/downloads/EspoCRM-5.9.3.zip" -o EspoCRM.zip; \
	echo "${ESPOCRM_SHA256} *EspoCRM.zip" | sha256sum -c -; \
    unzip -q EspoCRM.zip -d /usr/src; \
    mv "/usr/src/EspoCRM-5.9.3" /usr/src/espocrm; \
	rm EspoCRM.zip; \
    mkdir /usr/src/espocrm-upgrades; \
    chown -R ${DEFAULT_OWNER}:${DEFAULT_GROUP} /usr/src/espocrm /usr/src/espocrm-upgrades

COPY ./docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT [ "docker-entrypoint.sh" ]

RUN (crontab -l -u ${DEFAULT_OWNER}; echo "* * * * * cd ${DOCUMENT_ROOT}; /usr/local/bin/php -f cron.php > /dev/null 2>&1") | crontab - -u ${DEFAULT_OWNER}

CMD ["sh", "-c", "crond && php-fpm"]
