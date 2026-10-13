# Ghidra pour Debian

Paquet Debian de [Ghidra](https://github.com/NationalSecurityAgency/ghidra),
la plateforme de rétro-ingénierie logicielle de la NSA, **compilé depuis les
sources** pour Debian 13 (trixie) et les versions suivantes, en **amd64 et
arm64**.

## Pourquoi

- **Ghidra n'est pas dans Debian.** Sa construction exige Gradle 8.5 ou plus
  (Debian fournit la 4.x) et télécharge ses dépendances pendant le build, ce
  que la Debian Policy interdit dans `main`.
- **L'amont ne publie qu'une archive zip** multi-plateforme d'environ 570 Mo :
  pas de mises à jour par `apt`, et pas d'outils natifs pour Linux arm64
  (décompilateur, compilateur SLEIGH), à recompiler soi-même.
- **Kali Linux empaquette déjà Ghidra depuis les sources.** Ce dépôt reprend
  son travail (sous Apache-2.0) pour Debian, et le durcit (voir plus bas).

## Installation

Depuis le dépôt APT [apt.lemesre.org](https://apt.lemesre.org) :

```bash
curl -fsSL https://apt.lemesre.org/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/lemesre.gpg
echo "deb [signed-by=/usr/share/keyrings/lemesre.gpg] https://apt.lemesre.org stable main" \
  | sudo tee /etc/apt/sources.list.d/lemesre.list
sudo apt update && sudo apt install ghidra
```

Ou directement depuis les [Releases](../../releases) de ce dépôt :

```bash
sudo apt install ./ghidra_12.1.4-0lemesre1_amd64.deb
```

Commandes installées :

| Commande | Rôle |
| --- | --- |
| `ghidra` | interface graphique (`ghidraRun`) |
| `ghidra-analyzeHeadless` | analyse automatisée, sans interface |
| `ghidra-pyghidraRun` | PyGhidra (scripts Python 3) |

Ghidra a besoin d'un **JDK** 21 ou plus (il compile les scripts à
l'exécution) : le paquet tire `openjdk-21-jdk`, ou accepte `openjdk-25-jdk`.
Détails (choix du JDK, PyGhidra, réglages utilisateur) dans
[`debian/README.Debian`](debian/README.Debian).

## Ce qui change par rapport au zip officiel et à Kali

| | Zip officiel | Kali | Ce dépôt |
| --- | --- | --- | --- |
| Origine des binaires | NSA | sources | sources |
| Linux arm64 | outils natifs absents | oui | oui |
| Mises à jour | à la main | `apt` | `apt` |
| Gradle du build | — | téléchargé **sans** contrôle | version du wrapper amont, **SHA-256 vérifié** |
| Archive source | — | reconditionnée (`+ds`) | archive du tag, **SHA-256 épinglé** |
| Emplacement | au choix | `/usr/share/ghidra` | `/usr/lib/ghidra` (contient des binaires natifs) |
| Lanceur de bureau, icônes | non | via `kali-menu` | dans le paquet |
| Manuels PDF SLEIGH et p-code | oui | — | oui (DocBook, sans réseau) |
| Test automatique | — | — | décompilation sans interface, en utilisateur ordinaire, à chaque build |

Un build depuis les sources porte le nom de version `DEV` (celui de l'arbre
amont) et non `PUBLIC`, réservé aux archives de la NSA : les réglages vont dans
`~/.config/ghidra/ghidra_<version>_DEV`.

## Construction

Tout passe par `build.sh`, dans Debian trixie. Une seule commande, identique en
local et en CI :

```bash
docker run --rm -v "$PWD:/src" -w /src -e JOBS="$(nproc)" debian:trixie ./build.sh all
ls dist/
```

Étapes séparées : `deps` (dépendances de construction via `mk-build-deps`),
`source` (archive du tag, somme vérifiée), `deb` (`dpkg-buildpackage` ; amd64
produit aussi le paquet source), `check` (`lintian`, puis installation du
paquet et décompilation de `/usr/bin/true` par
[`tools/SmokeDecompile.java`](tools/SmokeDecompile.java), lancée par un
utilisateur sans droits). Les versions sont épinglées dans
[`versions.env`](versions.env) et, pour Gradle, dans
[`debian/rules`](debian/rules).

Compter environ 18 minutes sur 4 cœurs (la taille d'un runner GitHub), 8 Go de
disque et un paquet de 507 Mo (873 Mo installé). Le build a besoin du réseau :
Gradle, les dépendances hors Maven Central
(`gradle/support/fetchDependencies.gradle`, chacune vérifiée par SHA-256 par
l'amont) et Maven Central.

## Intégration continue

[`.github/workflows/build.yml`](.github/workflows/build.yml) construit les deux
architectures sur les runners hébergés de GitHub (`ubuntu-24.04` et
`ubuntu-24.04-arm`), par la même commande `docker run`. Lancement à la main
(`workflow_dispatch`) : les paquets restent sept jours en artefacts. Tag
`v<version Debian>` : le workflow vérifie que le tag correspond au changelog,
puis publie une Release avec les paquets binaires, le paquet source et les
sommes SHA-256. Les actions sont épinglées par empreinte de commit.

## Nouvelle version amont

```bash
tools/nouvelle-version.sh 12.1.5      # somme de l'archive, Gradle du wrapper amont, changelog
git diff                              # relire
docker run --rm -v "$PWD:/src" -w /src -e JOBS="$(nproc)" debian:trixie ./build.sh all
git commit -am "ghidra 12.1.5"
git tag v12.1.5-0lemesre1 && git push --follow-tags
```

Le script prévient si l'amont change de version de Java pour la compilation.

## Pistes

- **Build hors ligne**, comme le fait [Flathub](https://github.com/flathub/org.ghidra_sre.Ghidra) :
  lister et épingler toutes les dépendances Maven pour les fournir au build, au
  lieu de laisser Gradle les télécharger.
- **Paquet `ghidra-data`** (bases FunctionID de
  [ghidra-data](https://github.com/NationalSecurityAgency/ghidra-data)).

## Licence

Apache-2.0 ([`LICENSE`](LICENSE)), comme Ghidra et comme l'empaquetage Kali dont
ce dépôt dérive (Sophie Brun, Daniel Ruiz de Alegría). Les composants tiers
livrés par l'amont gardent leur licence (`licenses/`, `GPL/` dans
`/usr/lib/ghidra`). Ce dépôt n'est ni affilié à la NSA ni à Kali.
