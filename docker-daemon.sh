#!/bin/bash

set -euo pipefail

# entrypoint-utils.sh
# END: entrypoint-utils.sh

checkInstanceReady

applyConfigEnvironments

/usr/local/bin/php /var/www/html/daemon.php
