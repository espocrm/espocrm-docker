#!/bin/bash

set -euo pipefail

# entrypoint-utils.sh
# END: entrypoint-utils.sh

start() {
    if [ "$(bin/command config:get isInstalled)" = "true" ]; then
        actionUpgrade
        return
    fi

    actionInstall
}

actionUpgrade() {
    echo >&2 "info: Run \"upgrade\" action."

    if ! verifyDatabaseReady ; then
        echo >&2 "error: Unable to upgrade the instance. Database is not ready."
        return 1
    fi

    bin/command migrate
    setPermissions
}

actionInstall() {
    echo >&2 "info: Run \"install\" action."

    rm -rf ./data/cache

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

    echo >&2 "info: Installation completed successfully."
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
    chown -R www-data:www-data "${CUSTOM_RESOURCE_LIST[@]}"
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
CUSTOM_RESOURCE_LIST=(
    "/var/www/html/data"
    "/var/www/html/custom"
    "/var/www/html/client/custom"
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
