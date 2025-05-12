FROM php:8.3-fpm-alpine

LABEL org.opencontainers.image.source=https://github.com/espocrm/espocrm
LABEL org.opencontainers.image.description="EspoCRM is an Open Source CRM. Try for Free."

# Install php libs
RUN set -ex; \
    apk add --no-cache --virtual .build-deps \
        postgresql-dev \
        libzip-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        libwebp-dev \
        freetype-dev \
        openldap-dev \
        imap-dev \
        krb5-dev \
        openssl-dev \
        libzmq \
        zeromq-dev \
        bash \
        $PHPIZE_DEPS \
    ; \
    \
    # Install php-zmq
        cd /usr; \
        curl -fSL https://github.com/zeromq/php-zmq/archive/616b6c64ffd3866ed038615494306dd464ab53fc.tar.gz -o php-zmq.tar.gz; \
        tar -zxf php-zmq.tar.gz; \
        cd php-zmq*; \
        phpize && ./configure; \
        make; \
        make install; \
        cd .. && rm -rf php-zmq*; \
    # END: Install php-zmq
    \
    docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg=/usr/include \
        --with-webp \
    ; \
    docker-php-ext-configure imap \
        --with-kerberos \
        --with-imap-ssl \
    ; \
    \
    docker-php-ext-install -j "$(nproc)" \
        gd \
        pdo_pgsql \
        pdo_mysql \
        zip \
        imap \
        ldap \
        exif \
        pcntl \
        posix \
        bcmath \
    ; \
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

ENV ESPOCRM_VERSION 9.1.1
ENV ESPOCRM_SHA256 7adce6d7b74583b2d460d2a1ab52308232b6172f6058b9c1cc159ec6ce6abeb2

WORKDIR /var/www/html

RUN set -ex; \
    curl -fSL "https://www.espocrm.com/downloads/EspoCRM-9.1.1.zip" -o EspoCRM.zip; \
    echo "${ESPOCRM_SHA256} *EspoCRM.zip" | sha256sum -c -; \
    unzip -q EspoCRM.zip -d /usr/src; \
    mv "/usr/src/EspoCRM-9.1.1" /usr/src/espocrm; \
    rm EspoCRM.zip

COPY ./docker-*.sh  /usr/local/bin/

ENTRYPOINT [ "docker-entrypoint.sh" ]

CMD ["php-fpm"]
