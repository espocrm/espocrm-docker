#!/bin/bash

set -eu

DOCUMENT_ROOT="/var/www/html"

# entrypoint-utils.sh
configPrefix="ESPOCRM_CONFIG_"

declare -A configPrefixArrayList=(
    [logger]="ESPOCRM_CONFIG_LOGGER_"
    [database]="ESPOCRM_CONFIG_DATABASE_"
)

compareVersion() {
    local version1="$1"
    local version2="$2"
    local operator="$3"

    echo $(php -r "echo version_compare('$version1', '$version2', '$operator');")
}

join() {
    local sep="$1"; shift
    local out; printf -v out "${sep//%/%%}%s" "$@"
    echo "${out#$sep}"
}

getConfigParamFromFile() {
    local name="$1"

    php -r "
        if (file_exists('$DOCUMENT_ROOT/data/config-internal.php')) {
            \$config=include('$DOCUMENT_ROOT/data/config-internal.php');

            if (array_key_exists('$name', \$config)) {
                die(\$config['$name']);
            }
        }

        if (file_exists('$DOCUMENT_ROOT/data/config.php')) {
            \$config=include('$DOCUMENT_ROOT/data/config.php');

            if (array_key_exists('$name', \$config)) {
                die(\$config['$name']);
            }
        }
    "
}

getConfigParam() {
    local name="$1"

    php -r "
        require_once('$DOCUMENT_ROOT/bootstrap.php');

        \$app = new \Espo\Core\Application();
        \$config = \$app->getContainer()->get('config');

        echo \$config->get('$name');
    "
}

# Bool: saveConfigParam "jobRunInParallel" "true"
# String: saveConfigParam "language" "'en_US'"
saveConfigParam() {
    local name="$1"
    local value="$2"

    php -r "
        require_once('$DOCUMENT_ROOT/bootstrap.php');

        \$app = new \Espo\Core\Application();
        \$config = \$app->getContainer()->get('config');

        if (\$config->get('$name') === $value) {
            return;
        }

        \$injectableFactory = \$app->getContainer()->get('injectableFactory');
        \$configWriter = \$injectableFactory->create('\\Espo\\Core\\Utils\\Config\\ConfigWriter');

        \$configWriter->set('$name', $value);
        \$configWriter->save();
    "
}

saveConfigArrayParam() {
    local key1="$1"
    local key2="$2"
    local value="$3"

    php -r "
        require_once('$DOCUMENT_ROOT/bootstrap.php');

        \$app = new \Espo\Core\Application();
        \$config = \$app->getContainer()->get('config');

        \$arrayValue = \$config->get('$key1') ?? [];

        if (!is_array(\$arrayValue)) {
            return;
        }

        if (array_key_exists('$key2', \$arrayValue) && \$arrayValue['$key2'] === $value) {
            return;
        }

        \$injectableFactory = \$app->getContainer()->get('injectableFactory');
        \$configWriter = \$injectableFactory->create('\\Espo\\Core\\Utils\\Config\\ConfigWriter');

        \$arrayValue['$key2'] = $value;

        \$configWriter->set('$key1', \$arrayValue);
        \$configWriter->save();
    "
}

checkInstanceReady() {
    local isInstalled=$(getConfigParamFromFile "isInstalled")

    if [ -z "$isInstalled" ] || [ "$isInstalled" != 1 ]; then
        echo >&2 "Instance is not ready: waiting for the installation"
        exit 0
    fi

    local maintenanceMode=$(getConfigParamFromFile "maintenanceMode")

    if [ -n "$maintenanceMode" ] && [ "$maintenanceMode" = 1 ]; then
        echo >&2 "Instance is not ready: waiting for the upgrade"
        exit 0
    fi

    if ! verifyDatabaseReady ; then
        exit 0
    fi
}

isDatabaseReady() {
    php -r "
        require_once('$DOCUMENT_ROOT/bootstrap.php');

        \$app = new \Espo\Core\Application();
        \$config = \$app->getContainer()->get('config');

        \$helper = new \Espo\Core\Utils\Database\Helper(\$config);

        try {
            \$helper->createPdoConnection();
        }
        catch (Exception \$e) {
            die(false);
        }

        die(true);
    "
}

verifyDatabaseReady() {
    for i in {1..40}
    do
        isReady=$(isDatabaseReady 2>&1)

        if [ -n "$isReady" ]; then
            return 0 #true
        fi

        echo >&2 "Waiting Database for receiving connections..."
        sleep 3
    done

    echo >&2 "error: Database is not available"
    return 1 #false
}

applyConfigEnvironments() {
    local envName
    local envValue
    local configParamName
    local configParamValue

    compgen -v | while read -r envName; do

        if [[ $envName != "$configPrefix"* ]]; then
            continue
        fi

        envValue="${!envName}"

        if isConfigArrayParam "$envName" ; then
            saveConfigArrayValue "$envName" "$envValue"
            continue
        fi

        saveConfigValue "$envName" "$envValue"

    done
}

isValueQuoted() {
    local value="$1"

    php -r "
        echo isQuote('$value');

        function isQuote (\$value) {
            \$value = trim(\$value);

            if (\$value === '0') {
                return false;
            }

            if (empty(\$value)) {
                return true;
            }

            if (filter_var(\$value, FILTER_VALIDATE_IP)) {
                return true;
            }

            if (!preg_match('/[^0-9.]+/', \$value)) {
                return false;
            }

            if (in_array(\$value, ['null', '1'], true)) {
                return false;
            }

            if (in_array(\$value, ['true', 'false'])) {
                return false;
            }

            return true;
        }
    "
}

normalizeConfigParamName() {
    local value="$1"
    local prefix=${2:-"$configPrefix"}

    php -r "
        \$value = str_ireplace('$prefix', '', '$value');
        \$value = strtolower(\$value);

        \$value = preg_replace_callback(
            '/_([a-zA-Z])/',
            function (\$matches) {
                return strtoupper(\$matches[1]);
            },
            \$value
        );

        echo \$value;
    "
}

normalizeConfigParamValue() {
    local value=${1//\'/\\\'}

    local isValueQuoted=$(isValueQuoted "$value")

    if [ -n "$isValueQuoted" ] && [ "$isValueQuoted" = 1 ]; then
        echo "'$value'"
        return
    fi

    echo "$value"
}

isConfigArrayParam() {
    local envName="$1"

    for i in "${!configPrefixArrayList[@]}"
    do
        if [[ "$envName" != ${configPrefixArrayList[$i]}* ]]; then
            continue
        fi

        return 0 #true
    done

    return 1 #false
}

saveConfigValue() {
    local envName="$1"
    local envValue="$2"

    local key=$(normalizeConfigParamName "$envName")
    local value=$(normalizeConfigParamValue "$envValue")

    saveConfigParam "$key" "$value"
}

saveConfigArrayValue() {
    local envName="$1"
    local envValue="$2"

    for i in "${!configPrefixArrayList[@]}"
    do
        if [[ "$envName" != ${configPrefixArrayList[$i]}* ]]; then
            continue
        fi

        local key1="$i"
        local key2=$(normalizeConfigParamName "$envName" "${configPrefixArrayList[$i]}")

        break
    done

    local value=$(normalizeConfigParamValue "$envValue")

    saveConfigArrayParam "$key1" "$key2" "$value"
}
# END: entrypoint-utils.sh

checkInstanceReady

applyConfigEnvironments

/usr/local/bin/php /var/www/html/websocket.php

exec "$@"