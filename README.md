## Official Docker Image for EspoCRM

This repository is the official Docker image for EspoCRM.

### Usage

Use a prebuilt version for a production instance, https://hub.docker.com/r/espocrm/espocrm.

```
version: '3.8'

services:

  mysql:
    image: mysql:8
    container_name: mysql
    command: --default-authentication-plugin=mysql_native_password
    environment:
      MYSQL_ROOT_PASSWORD: root_password
      MYSQL_DATABASE: espocrm
      MYSQL_USER: espocrm
      MYSQL_PASSWORD: database_password
    volumes:
      - mysql:/var/lib/mysql
    restart: always

  espocrm:
    image: espocrm/espocrm
    container_name: espocrm
    environment:
      ESPOCRM_DATABASE_HOST: mysql
      ESPOCRM_DATABASE_USER: espocrm
      ESPOCRM_DATABASE_PASSWORD: database_password
      ESPOCRM_ADMIN_USERNAME: admin
      ESPOCRM_ADMIN_PASSWORD: password
      ESPOCRM_SITE_URL: "http://localhost:8080"
    volumes:
      - espocrm:/var/www/html
    restart: always
    ports:
      - 8080:80

  espocrm-daemon:
    image: espocrm/espocrm
    container_name: espocrm-daemon
    volumes:
      - espocrm:/var/www/html
    restart: always
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
    entrypoint: docker-websocket.sh
    ports:
      - 8081:8080

volumes:
  mysql:
  espocrm:
```
### Traefik Usage

This configuration should allow for the following:
* Serve EspoCRM on `WebSecure` port when `your_domain.tld` is used
* Redirect HTTP to HTTPs for `your_domain.tld`
* Serve WebSockets for EspoCRM on the `ws_your_domain.tld`
* Create `backend` network to connect EspoCRM instances to `MySQL` using `backend` bridge network

How to use:
* Change `your_domain.tld` and `ws_your_domain.tld` to your domains
* Change the default users and passwords in the config to your liking
* To avoid name collisions, change `container_name` options or delete them altoghether
* Change `proxy` network to your traefik docker network. Or see Traefik tutorial [here](https://docs.technotim.live/posts/traefik-portainer-ssl/).

```
version: "3.9"

services:
  mysql:
    image: mysql:latest
    container_name: mysql
    command: --default-authentication-plugin=mysql_native_password
    environment:
      MYSQL_ROOT_PASSWORD: root_password
      MYSQL_DATABASE: espocrm
      MYSQL_USER: espouser
      MYSQL_PASSWORD: database_password
    volumes:
      - mysql:/var/lib/mysql
    restart: always
    networks:
      - backend
      
  espocrm:
    image: espocrm/espocrm:latest
    container_name: espocrm
    environment:
      ESPOCRM_DATABASE_HOST: mysql
      ESPOCRM_DATABASE_USER: espouser
      ESPOCRM_DATABASE_PASSWORD: database_password
      ESPOCRM_ADMIN_USERNAME: admin
      ESPOCRM_ADMIN_PASSWORD: password
      ESPOCRM_SITE_URL: "https://your_domain.tld"
    volumes:
      - ./espocrm:/var/www/html
    restart: always
    labels:
      - traefik.enable=true
      - traefik.docker.network=proxy
      - traefik.http.routers.espocrm-app.rule=Host(`your_domain.tld`)
      - traefik.http.routers.espocrm-app.entrypoints=websecure
      - traefik.http.routers.espocrm-app.tls=true
      - traefik.http.routers.espocrm-app-http.rule=Host(`your_domain.tld`)
      - traefik.http.routers.espocrm-app-http.entrypoints=web
      - traefik.http.routers.espocrm-app-http.middlewares=espocrm-app-https-redirect
      - traefik.http.middlewares.espocrm-app-https-redirect.redirectscheme.scheme=https
      - traefik.http.services.espocrm.loadbalancer.server.port=80
      - traefik.http.routers.espocrm-app.service=espocrm
    networks:
      - proxy
      - backend

  espocrm-daemon:
    image: espocrm/espocrm:latest
    container_name: espocrm-daemon
    volumes:
      - espocrm:/var/www/html
    restart: always
    entrypoint: docker-daemon.sh
    networks:
      - backend
      - proxy

  espocrm-ws:
    image: espocrm/espocrm:latest
    container_name: espocrm-ws
    environment:
     ESPOCRM_CONFIG_USE_WEB_SOCKET: true
     ESPOCRM_CONFIG_WEB_SOCKET_URL: wss://ws_your_domain.tld
     ESPOCRM_CONFIG_WEB_SOCKET_ZERO_M_Q_SUBSCRIBER_DSN: tcp://*:7777
     ESPOCRM_CONFIG_WEB_SOCKET_ZERO_M_Q_SUBMISSION_DSN: tcp://espocrm-ws:7777
    volumes:
      - espocrm:/var/www/html
    restart: always
    entrypoint: docker-websocket.sh
    labels:
      - traefik.enable=true
      - traefik.docker.network=proxy
      - traefik.http.routers.espocrm-ws.rule=Host(`ws_your_domain.tld`)
      - traefik.http.routers.espocrm-ws.entrypoints=websecure
      - traefik.http.routers.espocrm-ws.tls=true
      - traefik.http.routers.espocrm-ws.service=espocrm-ws
      - traefik.http.services.espocrm-ws.loadbalancer.server.port=8080
    networks:
      - proxy
      - backend

networks:
  proxy:
    external: true
  backend:
    driver: bridge

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

EspoCRM is published under the GNU GPLv3 [license](https://raw.githubusercontent.com/espocrm/espocrm-docker/master/LICENSE).
