## Official Docker Image for EspoCRM

This repository is the official Docker image for EspoCRM.

Article map:

- [Usage](#usage)
- [Legacy Usage (EspoCRM v6.1.7 and earlier)](#legacy-usage-espocrm-v617-and-earlier)
- [Usage (only for development)](#usage-only-for-development)
- [Upgrading](#upgrading)
- [Documentation](#documentation)

### Usage

Use a prebuilt version for a production instance, https://hub.docker.com/r/espocrm/espocrm.

```
version: '3.8'

services:

  espocrm-db:
    image: mariadb:latest
    container_name: espocrm-db
    environment:
      MARIADB_ROOT_PASSWORD: root_password
      MARIADB_DATABASE: espocrm
      MARIADB_USER: espocrm
      MARIADB_PASSWORD: database_password
    volumes:
      - espocrm-db:/var/lib/mysql
    restart: always

  espocrm:
    image: espocrm/espocrm
    container_name: espocrm
    environment:
      ESPOCRM_DATABASE_HOST: espocrm-db
      ESPOCRM_DATABASE_USER: espocrm
      ESPOCRM_DATABASE_PASSWORD: database_password
      ESPOCRM_ADMIN_USERNAME: admin
      ESPOCRM_ADMIN_PASSWORD: password
      ESPOCRM_SITE_URL: "http://localhost:8080"
    volumes:
      - espocrm:/var/www/html
    restart: always
    depends_on:
      - espocrm-db
    ports:
      - 8080:80

  espocrm-daemon:
    image: espocrm/espocrm
    container_name: espocrm-daemon
    volumes:
      - espocrm:/var/www/html
    restart: always
    depends_on:
      - espocrm
    entrypoint: docker-daemon.sh

  espocrm-websocket:
    image: espocrm/espocrm
    container_name: espocrm-websocket
    environment:
      ESPOCRM_CONFIG_USE_WEB_SOCKET: "true"
      ESPOCRM_CONFIG_WEB_SOCKET_URL: "ws://localhost:8081"
      ESPOCRM_CONFIG_WEB_SOCKET_ZERO_M_Q_SUBSCRIBER_DSN: "tcp://*:7777"
      ESPOCRM_CONFIG_WEB_SOCKET_ZERO_M_Q_SUBMISSION_DSN: "tcp://espocrm-websocket:7777"
    volumes:
      - espocrm:/var/www/html
    restart: always
    depends_on:
      - espocrm
    entrypoint: docker-websocket.sh
    ports:
      - 8081:8080

volumes:
  espocrm:
  espocrm-db:
```

Run `docker compose up -d`, wait for it to initialize completely, and visit `http://localhost:8080`.

### Legacy Usage (EspoCRM v6.1.7 and earlier)

```
version: '3.1'

services:

  mysql:
    container_name: mysql
    image: mysql:8
    command: --default-authentication-plugin=mysql_native_password
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: example
    volumes:
      - mysql:/var/lib/mysql

  espocrm:
    container_name: espocrm
    image: espocrm/espocrm
    environment:
      ESPOCRM_DATABASE_PASSWORD: example
      ESPOCRM_ADMIN_USERNAME: admin
      ESPOCRM_ADMIN_PASSWORD: password
      ESPOCRM_SITE_URL: "http://localhost:8080"
    restart: always
    ports:
      - 8080:80
    volumes:
     - espocrm:/var/www/html

  espocrm-cron:
    image: espocrm/espocrm
    volumes:
     - espocrm:/var/www/html
    restart: always
    entrypoint: docker-cron.sh

volumes:
  mysql:
  espocrm:
```

### Usage (only for development)

Example `docker-compose.yml`:

```
version: '3.1'

services:

  mysql:
    container_name: mysql
    image: mysql:8
    command: --default-authentication-plugin=mysql_native_password
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: example
    volumes:
      - mysql:/var/lib/mysql

  espocrm:
    container_name: espocrm
    build:
      context: ./apache
      dockerfile: Dockerfile
    environment:
      ESPOCRM_DATABASE_PASSWORD: example
      ESPOCRM_ADMIN_USERNAME: admin
      ESPOCRM_ADMIN_PASSWORD: password
      ESPOCRM_SITE_URL: "http://localhost:8080"
    restart: always
    ports:
      - 8080:80
    volumes:
     - espocrm:/var/www/html

  espocrm-daemon:
    container_name: espocrm-daemon
    build:
      context: ./apache
      dockerfile: Dockerfile
    volumes:
     - espocrm:/var/www/html
    restart: always
    entrypoint: docker-daemon.sh

volumes:
  mysql:
  espocrm:
```

### Upgrading

In order to upgrade EspoCRM instance created by the `docker-compose.yml`:

1. Open your `docker-compose.yml` directory.
2. Run the command:

```
$ docker compose pull && docker compose up -d
```

### Documentation

Documentation for administrators, users and developers is available [here](https://docs.espocrm.com).

### License

EspoCRM is published under the GNU AGPLv3 [license](https://raw.githubusercontent.com/espocrm/espocrm/master/LICENSE.txt).
