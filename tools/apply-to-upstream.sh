#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Puts the E72 files of this repository into a checkout of rapuyama-linux
# (branch e5-port, tested with commit 2e30eb9) and applies the patches.
#
# usage: tools/apply-to-upstream.sh <path to the rapuyama-linux checkout>
#
# The checkout needs the submodules linux/kernel/linux, tools/src/ensymble,
# tools/src/elf2e32_next, symbian/oss.FCL.sf.os.kernelhwsrv and
# symbian/FCL.sf.incubator.modemadaptation (see docs/03-build.md).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
U="$(cd "${1:?usage: $0 <rapuyama-linux checkout>}" && pwd)"

want=2e30eb97081d9f0b42864fd720043f527add1343
have="$(git -C "$U" rev-parse HEAD 2>/dev/null || echo unknown)"
[ "$have" = "$want" ] || echo "warning: upstream is at $have, tested with $want" >&2

# board files
for f in "$HERE"/kernel/e72*.dts; do install -m 644 "$f" "$U/linux/boot/"; done
for f in "$HERE"/kernel/build-e72*.sh; do install -m 755 "$f" "$U/linux/kernel/"; done
for f in "$HERE"/initramfs/e72*; do install -m 755 "$f" "$U/linux/initramfs/"; done

# build helpers: native arm64 kernel build image, podman stand-in for the
# symbian-build container, minimal toolchain check used by its Dockerfile
mkdir -p "$U/tools/kbuild" "$U/tools/podman-shim" "$U/tools/container"
install -m 644 "$HERE/tools/kbuild.Dockerfile"   "$U/tools/kbuild/Dockerfile"
install -m 755 "$HERE/tools/podman-shim"         "$U/tools/podman-shim/podman"
if [ ! -e "$U/tools/container/check.sh" ]; then
	cat > "$U/tools/container/check.sh" <<'EOF'
#!/usr/bin/env bash
set -e
"$GCCE-gcc" --version | head -1
test -x "$E2E" && echo "elf2e32_next ok"
test -f "$ENSYMBLE" && echo "ensymble ok"
echo "toolchain ok"
EOF
	chmod 755 "$U/tools/container/check.sh"
fi

# kernel (submodule linux/kernel/linux, fluffleswaffles/linux branch e5)
for p in "$HERE"/kernel/patches/*.patch; do
	echo ">> kernel: $(basename "$p")"
	git -C "$U/linux/kernel/linux" apply "$p"
done

# Symbian loader: LinuxE72 (scatter boot), e72dump, tramp_scatter.S
echo ">> loader"
git -C "$U" apply "$HERE/loader/0001-loader-e72.patch"

# ensymble: run diagnostic apps on install, ENSYMBLE_NORUN=1 for menu apps
echo ">> ensymble"
git -C "$U/tools/src/ensymble" apply "$HERE/tools/ensymble-run-on-install.patch"

echo "done. next: docs/03-build.md"
