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
    local result
    result=$(php /var/www/html/bin/command db:check 2>/dev/null)

    [ "$result" = "OK" ]
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
