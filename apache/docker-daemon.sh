#!/bin/bash

set -eu

/usr/local/bin/php /var/www/html/daemon.php

exec "$@"