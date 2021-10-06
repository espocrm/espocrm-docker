#!/bin/bash

set -eu

DOCUMENT_ROOT="/var/www/html"

# entrypoint-utils.sh
# END: entrypoint-utils.sh

applyConfigEnvironments

/usr/local/bin/php /var/www/html/websocket.php

exec "$@"