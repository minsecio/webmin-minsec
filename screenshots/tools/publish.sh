#!/bin/sh
# Quantize screenshots/{light,dark} and force-push them as the sole commit
# of the gh-pages branch, so old sets never accumulate in history. GitHub
# Pages serves them at https://minsecio.github.io/webmin-minsec/<theme>/<name>.png
set -eu
cd "$(dirname "$0")/../.."
remote=$(git remote get-url origin)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for t in light dark; do
    mkdir -p "$tmp/$t"
    for f in screenshots/$t/*.png; do
        pngquant --quality 70-95 --speed 1 --strip --output "$tmp/$t/$(basename "$f")" "$f"
    done
done
touch "$tmp/.nojekyll"
git -C "$tmp" init -q -b gh-pages
git -C "$tmp" add -A
git -C "$tmp" -c "user.name=$(git config user.name)" -c "user.email=$(git config user.email)" \
    commit -q -m "Screenshots $(date +%F)"
git -C "$tmp" push --force "$remote" gh-pages
du -sh "$tmp"
