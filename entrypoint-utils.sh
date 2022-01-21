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

        \$config=include('$DOCUMENT_ROOT/data/config.php');
        if (array_key_exists('$name', \$config)) {
            die(\$config['$name']);
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
