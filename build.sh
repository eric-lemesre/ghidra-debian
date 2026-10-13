#!/usr/bin/env bash
# Construction du paquet Debian de Ghidra depuis les sources amont, dans
# Debian trixie : conteneur de la CI, ou `docker run` en local (README).
# Étapes : deps | source | deb | check | all.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=versions.env
. "$ROOT/versions.env"

JOBS=${JOBS:-$(nproc)}
WORK=${WORK:-$ROOT/work}
DIST=${DIST:-$ROOT/dist}
SRC=$WORK/ghidra-$GHIDRA_VERSION
ORIG=$WORK/ghidra_$GHIDRA_VERSION.orig.tar.gz
ARCH=$(dpkg --print-architecture)
export DEBIAN_FRONTEND=noninteractive

log() { printf '\n== %s\n' "$*" >&2; }

# Lancé en root dans un conteneur sur un dépôt monté : work/ et dist/
# reviennent au propriétaire du dépôt.
rendre_fichiers() {
    local owner
    owner=$(stat -c %u:%g "$ROOT")
    if [ "$(id -u)" -eq 0 ] && [ "$owner" != 0:0 ]; then
        chown -R "$owner" "$WORK" "$DIST" 2>/dev/null || true
    fi
}
trap rendre_fichiers EXIT

etape_deps() {
    log "dépendances de construction"
    if [ "$(id -u)" -ne 0 ]; then SUDO=sudo; else SUDO=; fi
    $SUDO apt-get update -q
    $SUDO apt-get install -y -q --no-install-recommends \
        devscripts equivs lintian ca-certificates curl
    # mk-build-deps laisse ses .buildinfo/.changes dans le répertoire courant
    local tmp
    tmp=$(mktemp -d)
    (cd "$tmp" && $SUDO mk-build-deps --install --remove \
        --tool 'apt-get -y -q --no-install-recommends' "$ROOT/debian/control")
    rm -rf "$tmp"
}

etape_source() {
    local version amont
    version=$(dpkg-parsechangelog -l "$ROOT/debian/changelog" -SVersion)
    amont=${version%-*}
    log "sources Ghidra $GHIDRA_VERSION (paquet $version)"
    if [ "$amont" != "$GHIDRA_VERSION" ]; then
        echo "debian/changelog ($version) ne porte pas GHIDRA_VERSION=$GHIDRA_VERSION" >&2
        exit 1
    fi
    # Sur un tag, la CI passe la version qu'il annonce : elle doit être celle
    # du changelog, sinon la release porterait un nom trompeur.
    if [ -n "${EXPECTED_VERSION:-}" ] && [ "$EXPECTED_VERSION" != "$version" ]; then
        echo "tag v$EXPECTED_VERSION ≠ version du changelog $version" >&2
        exit 1
    fi
    mkdir -p "$WORK"
    if [ ! -f "$ORIG" ]; then
        curl -fsSL --retry 3 -o "$ORIG.part" "$GHIDRA_UPSTREAM/archive/refs/tags/$GHIDRA_TAG.tar.gz"
        mv "$ORIG.part" "$ORIG"
    fi
    echo "$GHIDRA_SRC_SHA256  $ORIG" | sha256sum -c -
    rm -rf "$SRC" && mkdir -p "$SRC"
    tar -xzf "$ORIG" -C "$SRC" --strip-components=1
    cp -a "$ROOT/debian" "$SRC/debian"
}

etape_deb() {
    local type=-B
    # amd64 produit aussi le paquet source ; les autres architectures, les
    # binaires seuls (un même paquet source ne se publie qu'une fois).
    if [ "${BUILD_SOURCE:-}" = 1 ] || { [ -z "${BUILD_SOURCE:-}" ] && [ "$ARCH" = amd64 ]; }; then
        type=-F
    fi
    log "paquets Debian (dpkg-buildpackage $type, $JOBS tâches)"
    cd "$SRC"
    dpkg-buildpackage "$type" -us -uc -j"$JOBS"
    mkdir -p "$DIST"
    find "$WORK" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.ddeb' -o -name '*.dsc' \
        -o -name '*.debian.tar.*' -o -name '*.buildinfo' -o -name '*.changes' \) \
        -exec mv -f {} "$DIST"/ \;
    if [ "$type" = -F ]; then cp -f "$ORIG" "$DIST"/; fi
    (cd "$DIST" && rm -f "SHA256SUMS.$ARCH" && sha256sum -- * | grep -v ' SHA256SUMS\.' > "SHA256SUMS.$ARCH")
    ls -la "$DIST"
}

etape_check() {
    local deb out
    deb=$(ls "$DIST"/ghidra_*_"$ARCH".deb)
    log "contrôles de $(basename "$deb")"
    dpkg-deb -I "$deb"
    # Avertissements seulement : les surcharges assumées sont dans
    # debian/*lintian-overrides.
    lintian --no-tag-display-limit --info "$DIST"/*_"$ARCH".changes || true

    log "installation et décompilation sans interface, en utilisateur ordinaire"
    if [ "$(id -u)" -ne 0 ]; then
        echo "l'étape check installe le paquet : à lancer en root (conteneur)" >&2
        exit 1
    fi
    apt-get install -y -q --no-install-recommends "$deb"
    id fumee >/dev/null 2>&1 || useradd -m fumee
    out=$(runuser -u fumee -- mktemp -d)
    # Un utilisateur ordinaire ne peut rien écrire dans /usr/lib/ghidra : si
    # Ghidra avait besoin d'y compiler une spécification SLEIGH ou d'y poser
    # quoi que ce soit, l'analyse échouerait ici.
    runuser -u fumee -- ghidra-analyzeHeadless "$out" fumee \
        -import /usr/bin/true \
        -scriptPath "$ROOT/tools" -postScript SmokeDecompile.java "$out/true.c" \
        -deleteProject
    if ! grep -q '{' "$out/true.c" 2>/dev/null; then
        echo "ÉCHEC : aucune sortie du décompilateur" >&2
        exit 1
    fi
    sed -n '1,15p' "$out/true.c"

    log "exercices GhidraClass livrés tels que l'amont les a construits"
    local ex=/usr/lib/ghidra/docs/GhidraClass/ExerciseFiles ref f n=0
    ref=$(mktemp -d)
    tar -xzf "$ORIG" -C "$ref" --strip-components=1 --wildcards '*/GhidraDocs/GhidraClass/ExerciseFiles/*'
    while IFS= read -r -d '' f; do
        cmp -s "$f" "$ex/${f#"$ref/GhidraDocs/GhidraClass/ExerciseFiles/"}" \
            || { echo "ÉCHEC : exercice modifié par l'empaquetage : $f" >&2; exit 1; }
        n=$((n + 1))
    done < <(find "$ref/GhidraDocs/GhidraClass/ExerciseFiles" -type f -print0)
    rm -rf "$ref"
    echo "$n fichiers identiques à l'archive"
    log "test de fumée réussi"
}

case "${1:-all}" in
    deps)   etape_deps ;;
    source) etape_source ;;
    deb)    etape_deb ;;
    check)  etape_check ;;
    all)    etape_deps; etape_source; etape_deb; etape_check ;;
    *) echo "usage : $0 {deps|source|deb|check|all}" >&2; exit 2 ;;
esac
