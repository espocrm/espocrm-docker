#!/bin/bash

set -euo pipefail

installationType() {
    if [ -f "$DOCUMENT_ROOT/data/config.php" ]; then
        local isInstalled=$(php -r "\$config=include('$DOCUMENT_ROOT/data/config.php'); echo \$config['isInstalled'];")

        if [ -n "$isInstalled" ]; then
            local installedVersion=$(php -r "\$config=include('$DOCUMENT_ROOT/data/config.php'); echo \$config['version'];")
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
    local installedVersion=$(php -r "\$config=include('$DOCUMENT_ROOT/data/config.php'); echo \$config['version'];")
    local isVersionEqual=$(compareVersion "$installedVersion" "$ESPOCRM_VERSION" ">=")

    if [ -n "$isVersionEqual" ]; then
        echo >&2 "Upgrade process is finished. EspoCRM version is $installedVersion."
        return
    fi

    if [ $installedVersion == $ESPOCRM_UPGRADE_VERSION ]; then
        local upgradePackage="/usr/src/espocrm-upgrades/upgrade-$ESPOCRM_UPGRADE_VERSION-$ESPOCRM_VERSION.zip"
        curl -fSL "$ESPOCRM_UPGRADE_URL" -o "$upgradePackage"
        if ! echo "$ESPOCRM_UPGRADE_SHA256 $upgradePackage" | sha256sum -c -; then
            echo >&2 "error: Checksum for upgrade package is failed."
            exit 1
        fi

        echo >&2 "Start upgrading process from version $installedVersion."
        runUpgradeStep "$upgradePackage"
        actionUpgrade
        return
    fi

    echo >&2 "Start upgrading process from version $installedVersion."
    runUpgradeStep
    actionUpgrade
}

runUpgradeStep() {
    if [ -n "${1-}" ]; then
        local package="$1"
        local result=$(php command.php upgrade -y --file="$package")
    else
        local result=$(php command.php upgrade -y)
    fi

    if [[ "$result" == *"Error:"* ]]; then
        echo >&2 "error: Upgrade error, more details:"
        echo >&2 "$result"
        exit 1
    fi
}

installEspocrm() {
    echo >&2 "Start EspoCRM installation"

    find . -type d -exec chmod 755 {} + && find . -type f -exec chmod 644 {} +;
    find data custom/Espo/Custom client/custom -type d -exec chmod 775 {} + && find data custom/Espo/Custom client/custom -type f -exec chmod 664 {} +;
    chmod 775 application/Espo/Modules client/modules;

    declare -a preferences=()
    for optionName in "${!OPTIONAL_PARAMS[@]}"
    do
        local varName="${OPTIONAL_PARAMS[$optionName]}"
        if [ -n "${!varName-}" ]; then
            preferences+=("${optionName}=${!varName}")
        fi
    done

    runInstallationStep "step1" "user-lang=${ESPOCRM_LANGUAGE}"
    runInstallationStep "settingsTest" "hostName=${ESPOCRM_DATABASE_HOST}&dbName=${ESPOCRM_DATABASE_NAME}&dbUserName=${ESPOCRM_DATABASE_USER}&dbUserPass=${ESPOCRM_DATABASE_PASSWORD}"
    runInstallationStep "setupConfirmation" "host-name=${ESPOCRM_DATABASE_HOST}&db-name=${ESPOCRM_DATABASE_NAME}&db-user-name=${ESPOCRM_DATABASE_USER}&db-user-password=${ESPOCRM_DATABASE_PASSWORD}"
    runInstallationStep "checkPermission"
    runInstallationStep "saveSettings" "site-url=${ESPOCRM_SITE_URL}&default-permissions-user=${DEFAULT_OWNER}&default-permissions-group=${DEFAULT_GROUP}"
    runInstallationStep "buildDatabase"
    runInstallationStep "createUser" "user-name=${ESPOCRM_ADMIN_USERNAME}&user-pass=${ESPOCRM_ADMIN_PASSWORD}"
    runInstallationStep "savePreferences" "$(join '&' "${preferences[@]}")"
    runInstallationStep "finish"

    echo >&2 "End EspoCRM installation"
}

runInstallationStep() {
    local actionName="$1"

    if [ -n "${2-}" ]; then
        local data="$2"
        local result=$(php install/cli.php -a "$actionName" -d "$data")
    else
        local result=$(php install/cli.php -a "$actionName")
    fi

    if [[ "$result" == *"Error:"* ]]; then
        echo >&2 "error: installation error, more details:"
        echo >&2 "$result"
        exit 1
    fi
}

# ------------------------- START -------------------------------------
# Global variables
SOURCE_FILES="/usr/src/espocrm"
DOCUMENT_ROOT="/var/www/html"
DEFAULT_OWNER="www-data"
DEFAULT_GROUP="www-data"

declare -a REQUIRED_PARAMS=(
    'ESPOCRM_DATABASE_PASSWORD'
)

declare -A DEFAULTS=(
    ['ESPOCRM_DATABASE_HOST']='mysql'
    ['ESPOCRM_DATABASE_NAME']='espocrm'
    ['ESPOCRM_DATABASE_USER']='root'
    ['ESPOCRM_ADMIN_USERNAME']='admin'
    ['ESPOCRM_ADMIN_PASSWORD']='pasword'
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

for requiredParam in "${REQUIRED_PARAMS[@]}"
do
    if [ -z "${!requiredParam-}" ]; then
        echo >&2 "error: Parameter \"$requiredParam\" is required."
        exit 1
    fi
done

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
        actionUpgrade
        chown -R $DEFAULT_OWNER:$DEFAULT_GROUP "$DOCUMENT_ROOT"
        ;;

    skip)
        ;;

    *)
        echo >&2 "error: uknown installation type [$installationType]"
        exit 1
        ;;
esac
# ------------------------- END -------------------------------------

exec "$@"
