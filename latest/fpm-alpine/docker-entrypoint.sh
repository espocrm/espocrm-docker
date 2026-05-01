#!/bin/bash

set -euo pipefail

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

    php -r 'echo version_compare($argv[1], $argv[2], $argv[3]);' "$version1" "$version2" "$operator"
}

join() {
    local sep="$1"; shift
    local out; printf -v out "${sep//%/%%}%s" "$@"
    echo "${out#$sep}"
}

getConfigParamFromFile() {
    local name="$1"

    php -r "
        \$name = \$argv[1];

        if (file_exists('/var/www/html/data/state.php')) {
            \$config=include('/var/www/html/data/state.php');

            if (array_key_exists(\$name, \$config)) {
                echo \$config[\$name];
                exit;
            }
        }

        if (file_exists('/var/www/html/data/config-internal.php')) {
            \$config=include('/var/www/html/data/config-internal.php');

            if (array_key_exists(\$name, \$config)) {
                echo \$config[\$name];
                exit;
            }
        }

        if (file_exists('/var/www/html/data/config.php')) {
            \$config=include('/var/www/html/data/config.php');

            if (array_key_exists(\$name, \$config)) {
                echo \$config[\$name];
                exit;
            }
        }
    " "$name"
}

getConfigParam() {
    local name="$1"

    php -r "
        \$name = \$argv[1];

        require_once('/var/www/html/bootstrap.php');

        \$app = new \Espo\Core\Application();
        \$config = \$app->getContainer()->get('config');

        echo \$config->get(\$name);
    " "$name"
}

# Bool: saveConfigParam "jobRunInParallel" "true"
# String: saveConfigParam "language" "'en_US'"
saveConfigParam() {
    local name="$1"
    local value="$2"

    php -r "
        \$name = \$argv[1];
        \$rawValue = \$argv[2];

        \$normalizeValue = static function (string \$value) {
            if (\$value === 'null') {
                return null;
            }

            if (\$value === 'true') {
                return true;
            }

            if (\$value === 'false') {
                return false;
            }

            if (preg_match('/^-?(?:0|[1-9][0-9]*)$/', \$value)) {
                return (int) \$value;
            }

            if (preg_match('/^-?(?:[0-9]*\\.[0-9]+|[0-9]+\\.[0-9]*)$/', \$value)) {
                return (float) \$value;
            }

            return \$value;
        };

        \$value = \$normalizeValue(\$rawValue);

        require_once('/var/www/html/bootstrap.php');

        \$app = new \Espo\Core\Application();
        \$config = \$app->getContainer()->get('config');

        if (\$config->get(\$name) === \$value) {
            return;
        }

        \$injectableFactory = \$app->getContainer()->get('injectableFactory');
        \$configWriter = \$injectableFactory->create('\\Espo\\Core\\Utils\\Config\\ConfigWriter');

        \$configWriter->set(\$name, \$value);
        \$configWriter->save();
    " "$name" "$value"
}

saveConfigArrayParam() {
    local key1="$1"
    local key2="$2"
    local value="$3"

    php -r "
        \$key1 = \$argv[1];
        \$key2 = \$argv[2];
        \$rawValue = \$argv[3];

        \$normalizeValue = static function (string \$value) {
            if (\$value === 'null') {
                return null;
            }

            if (\$value === 'true') {
                return true;
            }

            if (\$value === 'false') {
                return false;
            }

            if (preg_match('/^-?(?:0|[1-9][0-9]*)$/', \$value)) {
                return (int) \$value;
            }

            if (preg_match('/^-?(?:[0-9]*\\.[0-9]+|[0-9]+\\.[0-9]*)$/', \$value)) {
                return (float) \$value;
            }

            return \$value;
        };

        \$value = \$normalizeValue(\$rawValue);

        require_once('/var/www/html/bootstrap.php');

        \$app = new \Espo\Core\Application();
        \$config = \$app->getContainer()->get('config');

        \$arrayValue = \$config->get(\$key1) ?? [];

        if (!is_array(\$arrayValue)) {
            return;
        }

        if (array_key_exists(\$key2, \$arrayValue) && \$arrayValue[\$key2] === \$value) {
            return;
        }

        \$injectableFactory = \$app->getContainer()->get('injectableFactory');
        \$configWriter = \$injectableFactory->create('\\Espo\\Core\\Utils\\Config\\ConfigWriter');

        \$arrayValue[\$key2] = \$value;

        \$configWriter->set(\$key1, \$arrayValue);
        \$configWriter->save();
    " "$key1" "$key2" "$value"
}

checkInstanceReady() {
    local isInstalled
    isInstalled=$(getConfigParamFromFile "isInstalled")

    if [ -z "$isInstalled" ] || [ "$isInstalled" != 1 ]; then
        echo >&2 "Instance is not ready: installation in progress"
        exit 0
    fi

    local maintenanceMode
    maintenanceMode=$(getConfigParamFromFile "maintenanceMode")

    if [ -n "$maintenanceMode" ] && [ "$maintenanceMode" = 1 ]; then
        echo >&2 "Instance is not ready: waiting for maintenance mode to be disabled"
        exit 0
    fi

    if ! verifyDatabaseReady ; then
        exit 0
    fi
}

isDatabaseReady() {
    php -r "
        require_once('/var/www/html/bootstrap.php');

        \$app = new \Espo\Core\Application();

        \$injectableFactory = \$app->getContainer()->get('injectableFactory');
        \$helper = \$injectableFactory->create('\\Espo\\Core\\Utils\\Database\\Helper');

        try {
            \$helper->createPDO();
        } catch (\Throwable \$e) {
            exit(1);
        }

        exit(0);
    "
}

verifyDatabaseReady() {
    for i in {1..40}
    do
        if isDatabaseReady; then
            return 0
        fi

        echo >&2 "Waiting for database connection (attempt $i/40)..."
        sleep 3
    done

    echo >&2 "error: Database connection failed"
    return 1
}

applyConfigEnvironments() {
    local envName
    local envValue

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

normalizeConfigParamName() {
    local value="$1"
    local prefix=${2:-"$configPrefix"}

    php -r "
        \$value = \$argv[1];
        \$prefix = \$argv[2];

        \$value = str_ireplace(\$prefix, '', \$value);
        \$value = strtolower(\$value);

        \$value = preg_replace_callback(
            '/_([a-zA-Z])/',
            function (\$matches) {
                return strtoupper(\$matches[1]);
            },
            \$value
        );

        echo \$value;
    " "$value" "$prefix"
}

normalizeConfigParamValue() {
    local value="$1"

    php -r "
        \$value = \$argv[1];
        \$trimmed = trim(\$value);

        if (preg_match('/^\'(.*)\'$/s', \$trimmed, \$matches)) {
            echo str_replace('\\\\\'', '\'', \$matches[1]);
            return;
        }

        echo \$value;
    " "$value"
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

    local key
    key=$(normalizeConfigParamName "$envName")

    local value
    value=$(normalizeConfigParamValue "$envValue")

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

        local key2
        key2=$(normalizeConfigParamName "$envName" "${configPrefixArrayList[$i]}")

        break
    done

    local value
    value=$(normalizeConfigParamValue "$envValue")

    saveConfigArrayParam "$key1" "$key2" "$value"
}

setEnvValue() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        printf >&2 "error: Both $var and $fileVar are set"
        exit 1
    fi
    local val="$def"
    if [ "${!var:-}" ]; then
        val="${!var}"
    elif [ "${!fileVar:-}" ]; then
        val="$(< "${!fileVar}")"
    fi
    export "$var"="$val"
    unset "$fileVar"
}

urlEncode() {
    local value="${1-}"
    php -r 'echo rawurlencode($argv[1]);' "$value"
}
# END: entrypoint-utils.sh

start() {
    if [ -f "/var/www/html/data/config.php" ]; then
        local isInstalled
        isInstalled=$(getConfigParamFromFile "isInstalled")

        if [ -n "$isInstalled" ] && [ "$isInstalled" = 1 ]; then
            local installedVersion
            installedVersion=$(getConfigParamFromFile "version")

            local isVersionGreater
            isVersionGreater=$(compareVersion "$ESPOCRM_VERSION" "$installedVersion" ">")

            if [ -n "$isVersionGreater" ]; then
                actionUpgrade
                return
            fi

            # no need any action
            return
        fi

        actionReinstall
        return
    fi

    actionInstall
}

actionInstall() {
    echo >&2 "info: Run \"install\" action."

    if [ ! -d "$SOURCE_FILES" ]; then
        echo >&2 "error: Source files [$SOURCE_FILES] are not found."
        exit 1
    fi

    cp -a "$SOURCE_FILES/." /var/www/html/

    installEspocrm
}

actionReinstall() {
    echo >&2 "info: Run \"reinstall\" action."

    if [ -f "/var/www/html/install/config.php" ]; then
        sed -i "s/'isInstalled' => true/'isInstalled' => false/g" "/var/www/html/install/config.php"
    fi

    rm -rf /var/www/html/data/cache

    installEspocrm
}

actionUpgrade() {
    echo >&2 "info: Run \"upgrade\" action."

    MAX_UPGRADE_COUNT=20
    UPGRADE_NUMBER=0

    if ! verifyDatabaseReady ; then
        echo >&2 "error: Unable to upgrade the instance. Database is not ready."
        return 1
    fi

    if ! runUpgradeProcess; then
        echo >&2 "error: Upgrade process failed. Starting the actual version."
        return 0 # the container will be started, but with the actual version
    fi

    setPermissions
    return 0
}

runUpgradeProcess() {
    UPGRADE_NUMBER=$((UPGRADE_NUMBER+1))

    if [ $UPGRADE_NUMBER -gt $MAX_UPGRADE_COUNT ];then
        echo >&2 "error: The MAX_UPGRADE_COUNT exceed. The upgrading process has been stopped."
        return 1
    fi

    local installedVersion
    installedVersion=$(getConfigParamFromFile "version")

    local isVersionEqual
    isVersionEqual=$(compareVersion "$installedVersion" "$ESPOCRM_VERSION" ">=")

    if [ -n "$isVersionEqual" ]; then
        echo >&2 "info: Upgrading is finished. EspoCRM version is $installedVersion."
        return 0
    fi

    echo >&2 "info: Start upgrading from version $installedVersion."

    if ! runUpgradeStep ; then
        return 1
    fi

    runUpgradeProcess
}

runUpgradeStep() {
    local result
    result=$(php command.php upgrade -y --toVersion="$ESPOCRM_VERSION")

    if [[ "$result" == *"Error:"* ]]; then
        echo >&2 "error: Upgrade error, more details:"
        echo >&2 "$result"

        return 1 #false
    fi

    return 0 #true
}

installEspocrm() {
    echo >&2 "info: Start EspoCRM installation"

    declare -a preferences=()

    for optionName in "${!OPTIONAL_PARAMS[@]}"
    do
        local varName="${OPTIONAL_PARAMS[$optionName]}"

        setEnvValue "${varName}" "${!varName-}"

        if [ -n "${!varName-}" ]; then
            preferences+=("${optionName}=$(urlEncode "${!varName}")")
        fi
    done

    runInstallationStep "step1" "user-lang=$(urlEncode "$ESPOCRM_LANGUAGE")"

    local databaseHost="${ESPOCRM_DATABASE_HOST}"

    if [ -n "$ESPOCRM_DATABASE_PORT" ]; then
        databaseHost="${ESPOCRM_DATABASE_HOST}:${ESPOCRM_DATABASE_PORT}"
    fi

    for i in {1..20}
    do
        settingsTestResult=$(runInstallationStep "settingsTest" "dbPlatform=$(urlEncode "$ESPOCRM_DATABASE_PLATFORM")&hostName=$(urlEncode "$databaseHost")&dbName=$(urlEncode "$ESPOCRM_DATABASE_NAME")&dbUserName=$(urlEncode "$ESPOCRM_DATABASE_USER")&dbUserPass=$(urlEncode "$ESPOCRM_DATABASE_PASSWORD")" true 2>&1)

        if [[ ! "$settingsTestResult" == *"Error:"* ]]; then
            break
        fi

        sleep 5
    done

    if [[ "$settingsTestResult" == *"Error:"* ]] && [[ "$settingsTestResult" == *"[errorCode] => 2002"* ]]; then
        echo >&2 "warning: Unable connect to Database server. Continuing anyway"
        return
    fi

    runInstallationStep "setupConfirmation" "db-platform=$(urlEncode "$ESPOCRM_DATABASE_PLATFORM")&host-name=$(urlEncode "$databaseHost")&db-name=$(urlEncode "$ESPOCRM_DATABASE_NAME")&db-user-name=$(urlEncode "$ESPOCRM_DATABASE_USER")&db-user-password=$(urlEncode "$ESPOCRM_DATABASE_PASSWORD")"
    runInstallationStep "checkPermission"
    runInstallationStep "saveSettings" "site-url=$(urlEncode "$ESPOCRM_SITE_URL")&default-permissions-user=www-data&default-permissions-group=www-data"
    runInstallationStep "buildDatabase"
    runInstallationStep "createUser" "user-name=$(urlEncode "$ESPOCRM_ADMIN_USERNAME")&user-pass=$(urlEncode "$ESPOCRM_ADMIN_PASSWORD")"
    runInstallationStep "savePreferences" "$(join '&' "${preferences[@]}")"
    runInstallationStep "finish"

    saveConfigParam "jobRunInParallel" "true"

    setPermissions

    echo >&2 "info: End EspoCRM installation"
}

runInstallationStep() {
    local actionName="$1"
    local returnResult=${3-false}

    local result

    if [ -n "${2-}" ]; then
        local data="$2"
        result=$(php install/cli.php -a "$actionName" -d "$data")
    else
        result=$(php install/cli.php -a "$actionName")
    fi

    if [ "$returnResult" = true ]; then
        echo >&2 "$result"
        return
    fi

    if [[ "$result" == *"Error:"* ]]; then
        echo >&2 "error: Installation error, more details:"
        echo >&2 "$result"
        exit 1
    fi
}

setPermissions() {
    local owner
    owner=$(id -u)

    local group
    group=$(id -g)

    find /var/www/html -type d -exec chmod 755 {} +
    find /var/www/html -type f -exec chmod 644 {} +

    chown -R $owner:$group /var/www/html

    chown www-data:www-data /var/www/html
    chown -R www-data:www-data "${CUSTOM_RESOURCE_LIST[@]}"

    chmod +x bin/command
}

setEnvironments() {
    for defaultParam in "${!DEFAULTS[@]}"
    do
        setEnvValue "${defaultParam}" "${DEFAULTS[$defaultParam]}"
    done
}

warnInsecureCredentials() {
    declare -a warningItems=()

    if [ "$ESPOCRM_ADMIN_PASSWORD" = "${DEFAULTS['ESPOCRM_ADMIN_PASSWORD']}" ]; then
        warningItems+=("ESPOCRM_ADMIN_PASSWORD uses the built-in default value.")
    fi

    if [ "$ESPOCRM_DATABASE_PASSWORD" = "${DEFAULTS['ESPOCRM_DATABASE_PASSWORD']}" ]; then
        warningItems+=("ESPOCRM_DATABASE_PASSWORD uses the built-in default value.")
    fi

    if [ ${#warningItems[@]} -eq 0 ]; then
        return
    fi

    echo >&2 '****************************************************'
    echo >&2 'warning: Insecure default EspoCRM credentials detected.'

    for warningItem in "${warningItems[@]}"
    do
        echo >&2 "warning: $warningItem"
    done

    echo >&2 'warning: Set strong environment variable values before using this instance in production.'
    echo >&2 '****************************************************'
}

# ------------------------- START -------------------------------------
# Global variables
SOURCE_FILES="/usr/src/espocrm"

CUSTOM_RESOURCE_LIST=(
    "/var/www/html/data"
    "/var/www/html/custom"
    "/var/www/html/client/custom"
    "/var/www/html/install/config.php"
)

declare -A DEFAULTS=(
    ['ESPOCRM_DATABASE_PLATFORM']='Mysql'
    ['ESPOCRM_DATABASE_HOST']='mysql'
    ['ESPOCRM_DATABASE_PORT']=''
    ['ESPOCRM_DATABASE_NAME']='espocrm'
    ['ESPOCRM_DATABASE_USER']='root'
    ['ESPOCRM_DATABASE_PASSWORD']='password'
    ['ESPOCRM_ADMIN_USERNAME']='admin'
    ['ESPOCRM_ADMIN_PASSWORD']='password'
    ['ESPOCRM_LANGUAGE']='en_US'
    ['ESPOCRM_SITE_URL']='http://localhost'
)

declare -A OPTIONAL_PARAMS=(
    ['language']='ESPOCRM_LANGUAGE'
    ['dateFormat']='ESPOCRM_DATE_FORMAT'
    ['timeFormat']='ESPOCRM_TIME_FORMAT'
    ['timeZone']='ESPOCRM_TIME_ZONE'
    ['weekStart']='ESPOCRM_WEEK_START'
    ['defaultCurrency']='ESPOCRM_DEFAULT_CURRENCY'
    ['thousandSeparator']='ESPOCRM_THOUSAND_SEPARATOR'
    ['decimalMark']='ESPOCRM_DECIMAL_MARK'
)

setEnvironments
warnInsecureCredentials

start

applyConfigEnvironments
# ------------------------- END -------------------------------------

exec "$@"
