## Official Docker Image for EspoCRM

This repository is the official Docker image for EspoCRM.

### Usage

Use a prebuilt version for a production instance, https://hub.docker.com/r/espocrm/espocrm.

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

  espocrm-daemon:
    image: espocrm/espocrm
    volumes:
     - espocrm:/var/www/html
    restart: always
    entrypoint: docker-daemon.sh

volumes:
  mysql:
  espocrm:
```

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

Run `docker-compose up -d`, wait for it to initialize completely, and visit `http://localhost:8080`.

### Documentation

Documentation for administrators, users and developers is available [here](https://docs.espocrm.com).

### License

EspoCRM is published under the GNU GPLv3 [license](https://raw.githubusercontent.com/espocrm/docker/master/LICENSE).
