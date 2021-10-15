#!/bin/bash

set -euo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

if [ -n "${1-}" ]; then
    latestRelease=$(curl -s "https://s.espocrm.com/release/info/?version=$1")
else
    latestRelease=$(curl -s "https://s.espocrm.com/release/latest")
fi

version=$(echo $latestRelease | jq -r '.version')
downnloadUrl=$(echo $latestRelease | jq -r '.package')
sha256=$(echo $latestRelease | jq -r '.packageSha256')

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

    cp docker-*.sh "$variant"/
    sed -i '/# entrypoint-utils.sh/r entrypoint-utils.sh' $variant/docker-*.sh

    sed -r \
			-e 's#%%VARIANT%%#'"$variant"'#' \
			-e 's#%%ESPOCRM_VERSION%%#'"$version"'#' \
			-e 's#%%ESPOCRM_DOWNLOAD_URL%%#'"$downnloadUrl"'#' \
	        -e 's#%%ESPOCRM_SHA256%%#'"$sha256"'#' \
			-e 's#%%ADDITIONS%%#'"$addition"'#' \
			-e 's#%%CMD%%#'"$cmd"'#' \
		"./Dockerfile-$dist.template" > "$variant/Dockerfile"

	travisEnv+='\n  - VARIANT='"$variant"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
