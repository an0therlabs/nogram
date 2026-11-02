#!/bin/sh
# Builds a flat Cydia/APT repository from packages/*.deb into the directory
# given as $1 (published on the gh-pages branch). Add it in Cydia as
# https://an0therlabs.github.io/nogram/
#
# Needs dpkg-scanpackages (dpkg-dev), gzip and bzip2. Old Cydia on iOS 6
# fetches Packages.bz2 first, so all three Packages forms are written.
set -e
OUT="${1:?usage: make-cydia-repo.sh <output dir>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT/debs"
cp "$HERE"/packages/*.deb "$OUT/debs/"
cd "$OUT"
dpkg-scanpackages -m debs /dev/null > Packages 2>/dev/null
gzip -9 -k -f Packages
bzip2 -9 -k -f Packages
{
    echo "Origin: Nogram"
    echo "Label: Nogram"
    echo "Suite: stable"
    echo "Version: 1.0"
    echo "Codename: ios6"
    echo "Architectures: iphoneos-arm"
    echo "Components: main"
    echo "Description: Nogram — Telegram-style client for iOS 6"
    echo "MD5Sum:"
    for f in Packages Packages.gz Packages.bz2; do
        echo " $(md5sum "$f" | cut -d' ' -f1) $(wc -c < "$f" | tr -d ' ') $f"
    done
    echo "SHA256:"
    for f in Packages Packages.gz Packages.bz2; do
        echo " $(sha256sum "$f" | cut -d' ' -f1) $(wc -c < "$f" | tr -d ' ') $f"
    done
} > Release
touch .nojekyll
echo "repo written to $OUT"
