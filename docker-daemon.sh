#!/bin/bash

set -euo pipefail

# entrypoint-utils.sh
# END: entrypoint-utils.sh

exitIfNotReady
applyConfigEnv

exec /usr/local/bin/php /var/www/html/daemon.php
