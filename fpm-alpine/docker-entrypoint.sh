#!/bin/bash

set -euo pipefail

# entrypoint-utils.sh
configPrefix="ESPOCRM_CONFIG_"

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

        if (\$config->get('$name') !== $value) {
            \$injectableFactory = \$app->getContainer()->get('injectableFactory');
            \$configWriter = \$injectableFactory->create('\\Espo\\Core\\Utils\\Config\\ConfigWriter');

            \$configWriter->set('$name', $value);
            \$configWriter->save();
        }
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

        echo >&2 "Waiting MySQL for receiving connections..."
        sleep 3
    done

    echo >&2 "error: MySQL is not available"
    return 1 #false
}

applyConfigEnvironments() {
    local envName
    local envValue
    local configParamName
    local configParamValue

    compgen -v | while read -r envName; do

        if [[ $envName == "$configPrefix"* ]]; then

            envValue="${!envName}"

            configParamName=$(normalizeConfigParamName "$envName")
            configParamValue=$(normalizeConfigParamValue "$envValue")

            saveConfigParam "$configParamName" "$configParamValue"

        fi

    done
}

isQuoteValue() {
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

    php -r "
        \$value = str_ireplace('$configPrefix', '', '$value');
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

    local isQuoteValue=$(isQuoteValue "$value")

    if [ -n "$isQuoteValue" ] && [ "$isQuoteValue" = 1 ]; then
        echo "'$value'"
        return
    fi

    echo "$value"
}
# END: entrypoint-utils.sh

installationType() {
    if [ -f "$DOCUMENT_ROOT/data/config.php" ]; then
        local isInstalled=$(getConfigParamFromFile "isInstalled")

        if [ -n "$isInstalled" ] && [ "$isInstalled" = 1 ]; then
            local installedVersion=$(getConfigParamFromFile "version")
            local isVersionGreater=$(compareVersion "$ESPOCRM_VERSION" "$installedVersion" ">")

            if [ -n "$isVersionGreater" ]; then
                echo "upgrade"
                return
            fi

            echo "skip"
            return
        fi

        echo "reinstall"
        return
    fi

    echo "install"
}

actionInstall() {
    if [ ! -d "$SOURCE_FILES" ]; then
        echo >&2 "error: Source files [$SOURCE_FILES] are not found."
        exit 1
    fi

    cp -a "$SOURCE_FILES/." "$DOCUMENT_ROOT/"

    installEspocrm
}

actionReinstall() {
    if [ -f "$DOCUMENT_ROOT/install/config.php" ]; then
        sed -i "s/'isInstalled' => true/'isInstalled' => false/g" "$DOCUMENT_ROOT/install/config.php"
    fi

    installEspocrm
}

actionUpgrade() {
    UPGRADE_NUMBER=$((UPGRADE_NUMBER+1))

    if [ $UPGRADE_NUMBER -gt $MAX_UPGRADE_COUNT ];then
        echo >&2 "The MAX_UPGRADE_COUNT exceded. The upgrading process has been stopped."
        return
    fi

    local installedVersion=$(getConfigParamFromFile "version")
    local isVersionEqual=$(compareVersion "$installedVersion" "$ESPOCRM_VERSION" ">=")

    if [ -n "$isVersionEqual" ]; then
        echo >&2 "Upgrade process is finished. EspoCRM version is $installedVersion."
        return
    fi

    echo >&2 "Start upgrading process from version $installedVersion."

    if ! runUpgradeStep ; then
        return
    fi

    actionUpgrade
}

runUpgradeStep() {
    local result=$(php command.php upgrade -y --toVersion="$ESPOCRM_VERSION")

    if [[ "$result" == *"Error:"* ]]; then
        echo >&2 "error: Upgrade error, more details:"
        echo >&2 "$result"

        return 1 #false
    fi

    return 0 #true
}

installEspocrm() {
    echo >&2 "Start EspoCRM installation"

    find . -type d -exec chmod 755 {} + && find . -type f -exec chmod 644 {} +
    find data custom/Espo/Custom client/custom -type d -exec chmod 775 {} + && find data custom/Espo/Custom client/custom -type f -exec chmod 664 {} +
    chmod 775 application/Espo/Modules client/modules

    declare -a preferences=()
    for optionName in "${!OPTIONAL_PARAMS[@]}"
    do
        local varName="${OPTIONAL_PARAMS[$optionName]}"
        if [ -n "${!varName-}" ]; then
            preferences+=("${optionName}=${!varName}")
        fi
    done

    runInstallationStep "step1" "user-lang=${ESPOCRM_LANGUAGE}"

    for i in {1..20}
    do
        settingsTestResult=$(runInstallationStep "settingsTest" "hostName=${ESPOCRM_DATABASE_HOST}&dbName=${ESPOCRM_DATABASE_NAME}&dbUserName=${ESPOCRM_DATABASE_USER}&dbUserPass=${ESPOCRM_DATABASE_PASSWORD}" true 2>&1)

        if [[ ! "$settingsTestResult" == *"Error:"* ]]; then
            break
        fi

        sleep 5
    done

    if [[ "$settingsTestResult" == *"Error:"* ]] && [[ "$settingsTestResult" == *"[errorCode] => 2002"* ]]; then
        echo >&2 "warning: Cannot connect to MySQL server. Continuing anyway"
        return
    fi

    runInstallationStep "setupConfirmation" "host-name=${ESPOCRM_DATABASE_HOST}&db-name=${ESPOCRM_DATABASE_NAME}&db-user-name=${ESPOCRM_DATABASE_USER}&db-user-password=${ESPOCRM_DATABASE_PASSWORD}"
    runInstallationStep "checkPermission"
    runInstallationStep "saveSettings" "site-url=${ESPOCRM_SITE_URL}&default-permissions-user=${DEFAULT_OWNER}&default-permissions-group=${DEFAULT_GROUP}"
    runInstallationStep "buildDatabase"
    runInstallationStep "createUser" "user-name=${ESPOCRM_ADMIN_USERNAME}&user-pass=${ESPOCRM_ADMIN_PASSWORD}"
    runInstallationStep "savePreferences" "$(join '&' "${preferences[@]}")"
    runInstallationStep "finish"

    saveConfigParam "jobRunInParallel" "true"

    echo >&2 "End EspoCRM installation"
}

runInstallationStep() {
    local actionName="$1"
    local returnResult=${3-false}

    if [ -n "${2-}" ]; then
        local data="$2"
        local result=$(php install/cli.php -a "$actionName" -d "$data")
    else
        local result=$(php install/cli.php -a "$actionName")
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

# ------------------------- START -------------------------------------
# Global variables
DOCUMENT_ROOT="/var/www/html"
SOURCE_FILES="/usr/src/espocrm"
MAX_UPGRADE_COUNT=20
DEFAULT_OWNER="www-data"
DEFAULT_GROUP="www-data"

if [ "$(id -u)" = '0' ]; then
    if [[ "$1" == "apache2"* ]]; then
        wrongSymbol='#'
        DEFAULT_OWNER="${APACHE_RUN_USER:-www-data}"
        DEFAULT_OWNER="${DEFAULT_OWNER#$wrongSymbol}"

        DEFAULT_GROUP="${APACHE_RUN_GROUP:-www-data}"
        DEFAULT_GROUP="${DEFAULT_GROUP#$wrongSymbol}"
    fi
else
	DEFAULT_OWNER="$(id -u)"
	DEFAULT_GROUP="$(id -g)"
fi

declare -A DEFAULTS=(
    ['ESPOCRM_DATABASE_HOST']='mysql'
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

for defaultParam in "${!DEFAULTS[@]}"
do
    if [ -z "${!defaultParam-}" ]; then
        declare "${defaultParam}"="${DEFAULTS[$defaultParam]}"
    fi
done

installationType=$(installationType)

case $installationType in
    install)
        echo >&2 "Run \"install\" action."
        actionInstall
        chown -R $DEFAULT_OWNER:$DEFAULT_GROUP "$DOCUMENT_ROOT"
        ;;

    reinstall)
        echo >&2 "Run \"reinstall\" action."
        actionReinstall
        chown -R $DEFAULT_OWNER:$DEFAULT_GROUP "$DOCUMENT_ROOT"
        ;;

    upgrade)
        echo >&2 "Run \"upgrade\" action."

        if verifyDatabaseReady ; then
            UPGRADE_NUMBER=0
            actionUpgrade
            chown -R $DEFAULT_OWNER:$DEFAULT_GROUP "$DOCUMENT_ROOT"
        else
            echo "error: Unable to upgrade the instance. Starting the current version."
        fi
        ;;

    skip)
        ;;

    *)
        echo >&2 "error: Unknown installation type [$installationType]"
        exit 1
        ;;
esac

applyConfigEnvironments
# ------------------------- END -------------------------------------

exec "$@"
