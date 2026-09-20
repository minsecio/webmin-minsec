#!/bin/sh
# Regenerate screenshots/{light,dark} with fake data.
# Needs playwright-core in node_modules (npm i --no-save playwright-core),
# a Playwright Chromium under ~/.cache/ms-playwright, passwordless sudo,
# and a real minsec binary (it renders the fake config tree). Runs a
# throwaway Webmin on 127.0.0.1:9999 from a private copy of /etc/webmin.
set -eu
cd "$(dirname "$0")/../.."
tools=$PWD/screenshots/tools
work=$(mktemp -d)
rm -rf screenshots/debug
chmod 755 "$work"
cleanup() {
    rc=$?
    set +e
    pid=$(cat "$work/var/miniserv.pid" 2>/dev/null)
    [ -n "$pid" ] && sudo -n kill "$pid"
    [ -n "$sockd" ] && kill "$sockd"
    if [ "$rc" -ne 0 ]; then
        rm -rf screenshots/debug
        cp -r "$work/shots" screenshots/debug 2>/dev/null
        cp "$work/var/miniserv.error" "$work/sockd.log" screenshots/debug/ 2>/dev/null
    fi
    sudo -n rm -rf "$work"
    exit "$rc"
}
trap cleanup EXIT
sockd=""


perl "$tools/fake-minsec.pl" setup "$work/minsec"
perl "$tools/fake-minsec.pl" serve "$work/minsec/minsec.sock" > "$work/sockd.log" 2>&1 &
sockd=$!
mkdir -p "$work/bin"
cat > "$work/bin/minsec" <<SH
#!/bin/sh
case "\$1" in
    --config-dir) exec /usr/bin/minsec "\$@" ;;
    *) exec /usr/bin/minsec --config-dir "$work/minsec/etc" "\$@" ;;
esac
SH
printf '#!/bin/sh\ncat "%s/nft.json"\n' "$tools" > "$work/bin/nft"
chmod 755 "$work/bin/minsec" "$work/bin/nft"

etc=$work/etc
sudo -n cp -a /etc/webmin "$etc"
sudo -n chown -R "$(id -u):$(id -g)" "$etc"
mkdir -p "$work/var"
sed -i \
    -e 's|^port=.*|port=9999|' -e 's|^listen=.*|listen=9999|' -e 's|^ipv6=.*|ipv6=0|' \
    -e 's|^syslog=.*|syslog=0|' -e 's|^passdelay=.*|passdelay=0|' -e 's|^blockhost_failures=.*|blockhost_failures=1000|' \
    -e "s|^logfile=.*|logfile=$work/var/miniserv.log|" -e "s|^errorlog=.*|errorlog=$work/var/miniserv.error|" \
    -e "s|^pidfile=.*|pidfile=$work/var/miniserv.pid|" \
    -e "s|^env_WEBMIN_CONFIG=.*|env_WEBMIN_CONFIG=$etc|" -e "s|^env_WEBMIN_VAR=.*|env_WEBMIN_VAR=$work/var|" \
    -e "s|/etc/webmin/|$etc/|g" "$etc/miniserv.conf"
grep -q '^bind=' "$etc/miniserv.conf" || echo bind=127.0.0.1 >> "$etc/miniserv.conf"
echo "root:$(perl -e 'print crypt("shots", "sh")'):0" > "$etc/miniserv.users"
mkdir -p "$etc/minsec"
cat > "$etc/minsec/config" <<CFG
minsec_cmd=$work/bin/minsec
config_dir=$work/minsec/etc
nft_cmd=$work/bin/nft
service_name=minsec
perpage=50
CFG
printf 'view=1\nevents=1\nnftables=1\nbans=1\nfilters=1\nconfig=1\nraw=1\nservice=1\nboot=1\n' > "$etc/minsec/root.acl"
rm -f "$etc"/authentic-theme/settings-*.js

export SHOT_BASE=http://127.0.0.1:9999
export SHOT_LOG="$work/minsec/sshd-sample.log"
export SHOT_MASK=$(printf '{"%s/minsec/etc":"/etc/minsec","%s/minsec/minsec.sock":"/run/minsec/minsec.sock","%s/minsec/state":"/var/lib/minsec","%s":"web1.example.com"}' \
    "$work" "$work" "$work" "$(hostname -f)")
for scheme in light dark; do
    night=0; [ "$scheme" = dark ] && night=1
    printf 'settings_force_night_mode=%s;\nsettings_palette_auto=false;\n' "$night" > "$etc/authentic-theme/settings-root.js"
    sudo -n /usr/libexec/webmin/miniserv.pl "$etc/miniserv.conf"
    sleep 2
    SHOT_OUT="$work/shots/$scheme" node "$tools/shoot.cjs" "$scheme"
    sudo -n kill "$(cat "$work/var/miniserv.pid")"
    sleep 1
done
rm -rf screenshots/light screenshots/dark
mv "$work/shots/light" "$work/shots/dark" screenshots/
