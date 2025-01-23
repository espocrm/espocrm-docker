#!/bin/bash

set -euo pipefail

# entrypoint-utils.sh
# END: entrypoint-utils.sh

isCustomPath() {
    local path="$1"

    for customDir in "${CUSTOM_RESOURCE_LIST[@]}"; do
        if [[ "$path" == "$customDir"* ]]; then
            return 0 # true
        fi
    done

    return 1 # false
}

runFileIntegrity() {
    if [ ! -d "$SOURCE_FILES" ]; then
        echo >&2 "error: Source files [$SOURCE_FILES] are not found."
        exit 1
    fi

    local documentRoot="/var/www/html"

    cp -a "$SOURCE_FILES/." "$documentRoot/"

    local backupDir="$documentRoot/data/.backup/integrity/$(date +'%Y%m%d-%H%M%S')"

    diff --exclude="data" -rq "$documentRoot" "$SOURCE_FILES" | grep "Only in $documentRoot" | while read -r line; do
        local path=${line/"Only in $documentRoot: "/}

        path=${path/"Only in $documentRoot/"/}
        path=${path/": "/\/}

        local fullPath="$documentRoot/$path"

        if isCustomPath "$fullPath"; then
            continue
        fi

        echo >&2 "info: [Integrity] Extra item found: $fullPath"

        local backupPath="$backupDir/$path"

        if [ -f "$fullPath" ]; then
            echo >&2 "info: [Integrity] Backup file to: $backupPath"

            mkdir -p $(dirname "$backupPath")
            cp "$fullPath" "$backupPath"

            echo >&2 "info: [Integrity] Delete file: $fullPath"
            rm -f "$fullPath"

            continue
        fi

        if [ -d "$fullPath" ]; then
            echo >&2 "info: [Integrity] Backup directory to: $backupPath"

            mkdir -p "$backupPath"
            cp -a "$fullPath"/. "$backupPath"/

            echo >&2 "info: [Integrity] Delete directory: $fullPath"
            rm -rf "$fullPath"

            continue
        fi
    done

    find "$documentRoot" -type d -empty -print -exec rmdir {} \;
}

installationType() {
    if [ -f "/var/www/html/data/config.php" ]; then
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
    installEspocrm
}

actionReinstall() {
    if [ -f "/var/www/html/install/config.php" ]; then
        sed -i "s/'isInstalled' => true/'isInstalled' => false/g" "/var/www/html/install/config.php"
    fi

    installEspocrm
}

actionUpgrade() {
    UPGRADE_NUMBER=$((UPGRADE_NUMBER+1))

    if [ $UPGRADE_NUMBER -gt $MAX_UPGRADE_COUNT ];then
        echo >&2 "The MAX_UPGRADE_COUNT exceed. The upgrading process has been stopped."
        return
    fi

    local installedVersion=$(getConfigParamFromFile "version")
    local isVersionEqual=$(compareVersion "$installedVersion" "$ESPOCRM_VERSION" ">=")

    if [ -n "$isVersionEqual" ]; then
        echo >&2 "Upgrade process is finished. EspoCRM version is $installedVersion."

        setPermissions
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

    declare -a preferences=()

    for optionName in "${!OPTIONAL_PARAMS[@]}"
    do
        local varName="${OPTIONAL_PARAMS[$optionName]}"

        setEnvValue "${varName}" "${!varName-}"

        if [ -n "${!varName-}" ]; then
            preferences+=("${optionName}=${!varName}")
        fi
    done

    runInstallationStep "step1" "user-lang=${ESPOCRM_LANGUAGE}"

    local databaseHost="${ESPOCRM_DATABASE_HOST}"

    if [ -n "$ESPOCRM_DATABASE_PORT" ]; then
        databaseHost="${ESPOCRM_DATABASE_HOST}:${ESPOCRM_DATABASE_PORT}"
    fi

    for i in {1..20}
    do
        settingsTestResult=$(runInstallationStep "settingsTest" "dbPlatform=${ESPOCRM_DATABASE_PLATFORM}&hostName=${databaseHost}&dbName=${ESPOCRM_DATABASE_NAME}&dbUserName=${ESPOCRM_DATABASE_USER}&dbUserPass=${ESPOCRM_DATABASE_PASSWORD}" true 2>&1)

        if [[ ! "$settingsTestResult" == *"Error:"* ]]; then
            break
        fi

        sleep 5
    done

    if [[ "$settingsTestResult" == *"Error:"* ]] && [[ "$settingsTestResult" == *"[errorCode] => 2002"* ]]; then
        echo >&2 "warning: Unable connect to Database server. Continuing anyway"
        return
    fi

    runInstallationStep "setupConfirmation" "db-platform=${ESPOCRM_DATABASE_PLATFORM}&host-name=${databaseHost}&db-name=${ESPOCRM_DATABASE_NAME}&db-user-name=${ESPOCRM_DATABASE_USER}&db-user-password=${ESPOCRM_DATABASE_PASSWORD}"
    runInstallationStep "checkPermission"
    runInstallationStep "saveSettings" "site-url=${ESPOCRM_SITE_URL}&default-permissions-user=www-data&default-permissions-group=www-data"
    runInstallationStep "buildDatabase"
    runInstallationStep "createUser" "user-name=${ESPOCRM_ADMIN_USERNAME}&user-pass=${ESPOCRM_ADMIN_PASSWORD}"
    runInstallationStep "savePreferences" "$(join '&' "${preferences[@]}")"
    runInstallationStep "finish"

    saveConfigParam "jobRunInParallel" "true"

    setPermissions

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

setPermissions() {
    find /var/www/html -type d -exec chmod 755 {} +
    find /var/www/html -type f -exec chmod 644 {} +

    chown -R root:root /var/www/html

    chown www-data:www-data /var/www/html
    chown -R www-data:www-data "${CUSTOM_RESOURCE_LIST[@]}"
}

setEnvironments() {
    for defaultParam in "${!DEFAULTS[@]}"
    do
        setEnvValue "${defaultParam}" "${DEFAULTS[$defaultParam]}"
    done
}

# ------------------------- START -------------------------------------
# Global variables
SOURCE_FILES="/usr/src/espocrm"
MAX_UPGRADE_COUNT=20

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

runFileIntegrity

installationType=$(installationType)

case $installationType in
    install)
        echo >&2 "Run \"install\" action."
        actionInstall
        ;;

    reinstall)
        echo >&2 "Run \"reinstall\" action."
        actionReinstall
        ;;

    upgrade)
        echo >&2 "Run \"upgrade\" action."

        if verifyDatabaseReady ; then
            UPGRADE_NUMBER=0
            actionUpgrade
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
