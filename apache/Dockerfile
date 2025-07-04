FROM php:8.3-apache

LABEL org.opencontainers.image.source=https://github.com/espocrm/espocrm
LABEL org.opencontainers.image.description="EspoCRM is an Open Source CRM. Try for Free."

RUN set -ex; \
    \
    aptMarkList="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    # Install php libs
    apt-get install -y --no-install-recommends \
        libpq-dev \
        libpng-dev \
        libjpeg-dev \
        libwebp-dev \
        libfreetype6-dev \
        libzip-dev \
        libxml2-dev \
        libc-client-dev \
        libkrb5-dev \
        libldap2-dev \
        libzmq5-dev \
        zlib1g-dev \
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
    docker-php-ext-configure ldap \
        --with-libdir="lib/$(dpkg-architecture --query DEB_BUILD_MULTIARCH)" \
    ; \
    docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg=/usr \
        --with-webp \
    ; \
    PHP_OPENSSL=yes docker-php-ext-configure imap \
        --with-kerberos \
        --with-imap-ssl \
    ; \
    \
    docker-php-ext-install -j$(nproc) \
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
    docker-php-ext-enable \
        zmq \
    ; \
    \
# reset a list of apt-mark
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $aptMarkList; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
        | xargs -r realpath | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    # Install required libs
    apt-get install -y --no-install-recommends \
        unzip \
        libldap-common \
    ; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

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

RUN a2enmod rewrite;

ENV ESPOCRM_VERSION 9.1.7
ENV ESPOCRM_SHA256 7d37392dc69116e9901f4e74ceba27f8098df969b243df132874d264fcaf9e4b

WORKDIR /var/www/html

RUN set -ex; \
    curl -fSL "https://www.espocrm.com/downloads/EspoCRM-9.1.7.zip" -o EspoCRM.zip; \
    echo "${ESPOCRM_SHA256} *EspoCRM.zip" | sha256sum -c -; \
    unzip -q EspoCRM.zip -d /usr/src; \
    mv "/usr/src/EspoCRM-9.1.7" /usr/src/espocrm; \
    rm EspoCRM.zip

COPY ./docker-*.sh  /usr/local/bin/

ENTRYPOINT [ "docker-entrypoint.sh" ]

CMD ["apache2-foreground"]
