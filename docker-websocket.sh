#!/bin/bash

set -eu

# entrypoint-utils.sh
# END: entrypoint-utils.sh

checkInstanceReady

applyConfigEnvironments

/usr/local/bin/php /var/www/html/websocket.php

exec "$@"
