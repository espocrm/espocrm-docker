configPrefix="ESPOCRM_CONFIG_"

declare -A configPrefixArrayList=(
    [logger]="ESPOCRM_CONFIG_LOGGER_"
    [database]="ESPOCRM_CONFIG_DATABASE_"
)

join() {
    local sep="$1"; shift
    local out; printf -v out "${sep//%/%%}%s" "$@"
    echo "${out#$sep}"
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
    bin/command app-check || exit 0
}

verifyDatabaseReady() {
    for i in {1..40}; do
        [ "$(bin/command db:check 2>/dev/null)" = "OK" ] && return 0

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

        return 0 # true
    done

    return 1 # false
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
