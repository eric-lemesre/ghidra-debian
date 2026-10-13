#!/usr/bin/env bash
# Prépare le passage à une nouvelle version amont de Ghidra : somme de
# l'archive du tag (versions.env), version de Gradle du wrapper amont et sa
# somme (debian/rules), entrée de changelog. Ne commite ni ne tague rien.
# Usage : tools/nouvelle-version.sh 12.1.5
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=versions.env
. "$ROOT/versions.env"
V=${1:?usage : $0 <version amont, par exemple 12.1.5>}
TAG=Ghidra_${V}_build
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "== archive du tag $TAG"
curl -fsSL --retry 3 -o "$tmp/src.tar.gz" "$GHIDRA_UPSTREAM/archive/refs/tags/$TAG.tar.gz"
sum=$(sha256sum "$tmp/src.tar.gz" | cut -d' ' -f1)
props=$(tar -xzOf "$tmp/src.tar.gz" --wildcards \
    '*/Ghidra/RuntimeScripts/Common/support/gradle/gradle-wrapper.properties')
app=$(tar -xzOf "$tmp/src.tar.gz" --wildcards '*/Ghidra/application.properties')

gradle=$(sed -n 's/.*gradle-\([0-9.]*\)-bin\.zip.*/\1/p' <<<"$props")
echo "== Gradle $gradle (wrapper amont)"
gsum=$(curl -fsSL --retry 3 "https://services.gradle.org/distributions/gradle-$gradle-bin.zip.sha256")
[[ $gsum =~ ^[0-9a-f]{64}$ ]] || { echo "somme Gradle illisible : $gsum" >&2; exit 1; }

# debian/rules construit avec le JDK 21 : le signaler si l'amont en exige un autre.
jdk=$(sed -n 's/^application\.java\.compiler=//p' <<<"$app")
if [ "$jdk" != 21 ]; then
    echo "ATTENTION : l'amont compile désormais pour Java $jdk (JAVA_HOME et Build-Depends à revoir)" >&2
fi

sed -i -e "s/^GHIDRA_VERSION=.*/GHIDRA_VERSION=$V/" \
       -e "s/^GHIDRA_TAG=.*/GHIDRA_TAG=$TAG/" \
       -e "s/^GHIDRA_SRC_SHA256=.*/GHIDRA_SRC_SHA256=$sum/" "$ROOT/versions.env"
sed -i -e "s/^GRADLE_VERSION := .*/GRADLE_VERSION := $gradle/" \
       -e "s/^GRADLE_SHA256 := .*/GRADLE_SHA256 := $gsum/" "$ROOT/debian/rules"
(cd "$ROOT" && DEBFULLNAME=$(git config user.name) DEBEMAIL=$(git config user.email) \
    dch --newversion "$V-0lemesre1" --distribution stable --force-distribution \
    "New upstream release $V.")

echo
git -C "$ROOT" --no-pager diff --stat
echo "Relire, construire (README), puis : git commit -am 'ghidra $V' && git tag v$V-0lemesre1"
