## Official Docker Image for EspoCRM

This repository is the official Docker image for EspoCRM.

### Usage

Example `stack.yml`:

```
version: '3.1'

services:

  mysql:
    image: mysql:8
    command: --default-authentication-plugin=mysql_native_password
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: example
    volumes:
      - mysql:/var/lib/mysql

  espocrm:
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

volumes:
  mysql:
  espocrm:
```

Run `docker stack deploy -c stack.yml espocrm` (or `docker-compose -f stack.yml up`), wait for it to initialize completely, and visit `http://localhost:8080`.

### Documentation

Documentation for administrators, users and developers is available [here](https://docs.espocrm.com).

### License

EspoCRM is published under the GNU GPLv3 [license](https://raw.githubusercontent.com/espocrm/docker/master/LICENSE).
