#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# alpine armhf userland for the E72 initramfs: wlan (wpa_supplicant, iw),
# ssh client (dropbear dbclient), kexec, apk. runs inside the e72-kbuild
# container (aarch64): apk.static of the container's arch installs armhf
# packages into a root dir, then prune to the DT_NEEDED closure.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; TOP="$HERE/../.."
W="$TOP/work/rootfs-e72"; DL="$TOP/work/dl/alpine-$(uname -m)"
MIRROR=https://dl-cdn.alpinelinux.org/alpine; REL=v3.22
PKGS="musl busybox busybox-binsh alpine-keys ca-certificates-bundle apk-tools wpa_supplicant iw dropbear-dbclient dropbear-scp kexec-tools"
[ -e "$W.pruned" ] && exit 0
mkdir -p "$DL/apkt" "$DL/cache"
if [ ! -x "$DL/apkt/sbin/apk.static" ]; then
	curl -sS -fL -o "$DL/idx.tar.gz" "$MIRROR/$REL/main/$(uname -m)/APKINDEX.tar.gz"
	v=$(tar -xzOf "$DL/idx.tar.gz" APKINDEX | awk -v RS= '/\nP:apk-tools-static\n/' | sed -n 's/^V://p')
	curl -sS -fL -o "$DL/apk-tools-static.apk" "$MIRROR/$REL/main/$(uname -m)/apk-tools-static-$v.apk"
	tar -xzf "$DL/apk-tools-static.apk" -C "$DL/apkt" 2>/dev/null || true
fi
rm -rf "$W"; mkdir -p "$W/etc/apk"
printf '%s/%s/main\n%s/%s/community\n' "$MIRROR" "$REL" "$MIRROR" "$REL" > "$W/etc/apk/repositories"
"$DL/apkt/sbin/apk.static" --root "$W" --arch armhf --initdb --usermode --no-scripts \
	--allow-untrusted --cache-dir "$DL/cache" -U add $PKGS
python3 "$TOP/tools/prune_rootfs.py" "$W" sbin/wpa_supplicant sbin/wpa_passphrase sbin/wpa_cli usr/sbin/iw \
	sbin/apk usr/bin/dbclient usr/bin/scp usr/sbin/kexec lib/ld-musl-armhf.so.1
touch "$W.pruned"; du -sh "$W"
