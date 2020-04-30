#!/bin/bash

set -euo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

latestRelease=$(curl -s "https://s.espocrm.com/release/latest")

version=$(echo $latestRelease | jq -r '.version')
downnloadUrl=$(echo $latestRelease | jq -r '.downloadUrl')
sha256=$(echo $latestRelease | jq -r '.packageSha256')

upgradeRelease=$(curl -s "https://s.espocrm.com/upgrade/prev/?toVersion=$version")

upgradeVersion=$(echo $upgradeRelease | jq -r '.fromVersion')
upgradeDownnloadUrl=$(echo $upgradeRelease | jq -r '.package')
upgradeSha256=$(echo $upgradeRelease | jq -r '.packageSha256')

declare variantList=(
    'apache'
    'fpm'
    'fpm-alpine'
)

declare -A distributions=(
    [apache]='debian'
    [fpm]='debian'
    [fpm-alpine]='alpine'
)

declare -A cmds=(
    [apache]='apache2-foreground'
    [fpm]='php-fpm'
    [fpm-alpine]='php-fpm'
)

declare -A additions=(
    [apache]='\
RUN a2enmod rewrite;\
'
    [fpm]=''
    [fpm-alpine]=''
)

travisEnv=
for variant in "${variantList[@]}"
do
    dist="${distributions[$variant]}"
    cmd="${cmds[$variant]}"
    addition="${additions[$variant]}"

    mkdir -p "$variant"

    sed -r \
			-e 's#%%VARIANT%%#'"$variant"'#' \
			-e 's#%%ESPOCRM_VERSION%%#'"$version"'#' \
			-e 's#%%ESPOCRM_DOWNLOAD_URL%%#'"$downnloadUrl"'#' \
	        -e 's#%%ESPOCRM_SHA256%%#'"$sha256"'#' \
	        -e 's#%%ESPOCRM_UPGRADE_VERSION%%#'"$upgradeVersion"'#' \
	        -e 's#%%ESPOCRM_UPGRADE_URL%%#'"$upgradeDownnloadUrl"'#' \
	        -e 's#%%ESPOCRM_UPGRADE_SHA256%%#'"$upgradeSha256"'#' \
			-e 's#%%ADDITIONS%%#'"$addition"'#' \
			-e 's#%%CMD%%#'"$cmd"'#' \
		"./Dockerfile-$dist.template" > "$variant/Dockerfile"

    cp docker-entrypoint.sh "$variant/docker-entrypoint.sh"

	travisEnv+='\n  - VARIANT='"$variant"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
