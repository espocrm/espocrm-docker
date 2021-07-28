#!/bin/bash
set -e

DOCUMENT_ROOT="/var/www/html"

# see docker-entrypoint.sh
saveConfigParam() {
    local name="$1"
    local value="$2"

    php -r "
        require_once('$DOCUMENT_ROOT/bootstrap.php');

        \$app = new \Espo\Core\Application();
        \$config = \$app->getContainer()->get('config');

        if (\$config->get('$name') !== $value) {
            \$config->set('$name', $value);
            \$config->save();
        }
    "
}

# see docker-entrypoint.sh
applyEnvironments() {
    declare -A configParams=(
        ['webSocketZeroMQSubmissionDsn']='ESPOCRM_ENV_WEBSOCKET_SUBMISSION_DSN'
        ['webSocketZeroMQSubscriberDsn']='ESPOCRM_ENV_WEBSOCKET_SUBSCRIBER_DSN'
    )

    for paramName in "${!configParams[@]}"
    do
        local envName="${configParams[$paramName]}"

        if [ -n "${!envName-}" ]; then
            saveConfigParam "$paramName" "'${!envName}'"
        fi
    done
}

applyEnvironments

/usr/local/bin/php /var/www/html/websocket.php

exec "$@"