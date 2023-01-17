#!/bin/bash

set -euo pipefail

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		fileCommit \
			Dockerfile \
			$(git show HEAD:./Dockerfile | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			')
	)
}

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

generateCommit="$(fileCommit "$@")"

cat <<-EOH
# this file is generated via https://github.com/espocrm/espocrm-docker/blob/$generateCommit/$self
Maintainers: Taras Machyshyn <docker@espocrm.com> (@tmachyshyn)
GitRepo: https://github.com/espocrm/espocrm-docker.git
GitCommit: $generateCommit
EOH

defaultVariant="apache"

declare -a variantList=(
	'apache'
	'fpm'
	'fpm-alpine'
)

declare -A architectures=(
	[apache]="amd64, i386, arm32v7, arm64, s390x"
	[fpm]="amd64, i386, arm32v7, arm64, s390x"
	[fpm-alpine]="amd64, i386, arm32v6, arm32v7, arm64v8, ppc64le, s390x"
)

for variant in "${variantList[@]}"
do
    dir="$variant"

    if [ ! -f "$dir/Dockerfile" ]; then
        continue
    fi

    commit=$(dirCommit "$dir")
    version="$(git show "$commit":"$dir/Dockerfile" | grep 'ESPOCRM_VERSION' | awk '{print $3}')"

	declare -a tags=("$variant" "$version-$variant")

	tags+=("$(expr "$version" : '\([0-9]*.[0-9]*\)')-$variant")
	tags+=("$(expr "$version" : '\([0-9]*\)')-$variant")

	if [ "$defaultVariant" == "$variant" ]; then
	     tags+=("latest")
	     tags+=("$version")
	     tags+=("$(expr "$version" : '\([0-9]*.[0-9]*\)')")
	     tags+=("$(expr "$version" : '\([0-9]*\)')")
	fi

	echo
	cat <<-EOE
		Tags: $(join ', ' "${tags[@]}")
		Architectures: ${architectures[$variant]}
		Directory: $dir
	EOE

done
