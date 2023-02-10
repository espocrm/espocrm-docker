FROM php:8.1-fpm-alpine

# Install php libs
RUN set -ex; \
    apk add --no-cache --virtual .build-deps \
        libzip-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        libwebp-dev \
        openldap-dev \
        imap-dev \
        libzmq \
        zeromq-dev \
        bash \
        $PHPIZE_DEPS \
    ; \
    \
# Install php-zmq
    cd /usr; \
    curl -fSL https://github.com/zeromq/php-zmq/archive/ee5fbc693f07b2d6f0d9fd748f131be82310f386.tar.gz -o php-zmq.tar.gz; \
    tar -zxf php-zmq.tar.gz; \
    cd php-zmq*; \
    phpize && ./configure; \
    make; \
    make install; \
    cd .. && rm -rf php-zmq*; \
# END: Install php-zmq
    \
    docker-php-ext-configure gd --with-jpeg --with-webp; \
    docker-php-ext-install gd; \
    docker-php-ext-install exif; \
    docker-php-ext-install ldap; \
    docker-php-ext-install imap; \
    docker-php-ext-install pcntl; \
    docker-php-ext-install zip; \
    docker-php-ext-install pdo_mysql; \
    docker-php-ext-install pcntl; \
    docker-php-ext-install posix; \
    docker-php-ext-enable zmq; \
    docker-php-ext-install bcmath

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

ENV ESPOCRM_VERSION 7.3.3
ENV ESPOCRM_SHA256 9d7061d301fb168ab5bb5d2b6c75a90f83a80b3d304de3644463d92e7210746b

WORKDIR /var/www/html

RUN set -ex; \
    curl -fSL "https://www.espocrm.com/downloads/EspoCRM-7.3.3.zip" -o EspoCRM.zip; \
	echo "${ESPOCRM_SHA256} *EspoCRM.zip" | sha256sum -c -; \
    unzip -q EspoCRM.zip -d /usr/src; \
    mv "/usr/src/EspoCRM-7.3.3" /usr/src/espocrm; \
	rm EspoCRM.zip; \
    chown -R www-data:www-data /usr/src/espocrm

COPY ./docker-*.sh  /usr/local/bin/

ENTRYPOINT [ "docker-entrypoint.sh" ]

CMD ["php-fpm"]
