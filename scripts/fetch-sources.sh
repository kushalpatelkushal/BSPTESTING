#!/usr/bin/env bash
# Download kernel and busybox sources into work/. Versions come from the upstream
# indexes so this does not rot when a new release lands.
#
# The kernel resolves from the gregkh/linux stable mirror on GitHub (reachable
# from CI and from networks that block kernel.org), and falls back to
# kernel.org/releases.json. Set FORCE_KERNEL_VERSION to pin an exact release.
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$WORK"

resolve_from_github() {
	local auth=()
	if [ -n "${GITHUB_TOKEN:-}" ]; then
		auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
	fi
	curl -fsSL --max-time 60 "${auth[@]}" \
		"https://api.github.com/repos/gregkh/linux/tags?per_page=100" |
		python3 -c '
import json, sys, re
def key(v):
    return [int(x) for x in v.lstrip("v").split(".")]
tags = [t["name"] for t in json.load(sys.stdin)]
stable = [t for t in tags if re.fullmatch(r"v\d+\.\d+\.\d+", t)]
stable.sort(key=key, reverse=True)
if not stable:
    sys.exit("no stable release tag found")
print(stable[0].lstrip("v"))
'
}

resolve_from_kernel_org() {
	curl -fsSL --max-time 60 https://www.kernel.org/releases.json | python3 -c '
import json, sys
def key(v):
    return [int(x) for x in v.split(".")[:3]]
rel = json.load(sys.stdin)["releases"]
stable = sorted((r for r in rel if r.get("stable")), key=lambda r: key(r["version"]), reverse=True)
longterm = [r for r in stable if r.get("longterm")]
if not (longterm or stable):
    sys.exit("no stable release in releases.json")
print((longterm or stable)[0]["version"])
'
}

kernel_version() {
	if [ -n "${FORCE_KERNEL_VERSION:-}" ]; then
		printf '%s\n' "$FORCE_KERNEL_VERSION"
		return
	fi
	resolve_from_github || resolve_from_kernel_org
}

busybox_tarball() {
	local t
	# Pinned fallback: the download index is scraped, and an HTML change must not
	# be able to break the build.
	t=$(curl -fsSL --max-time 60 https://busybox.net/downloads/ |
		grep -oE 'busybox-1\.[0-9]+\.[0-9]+\.tar\.bz2' | sort -uV | tail -1) || t=""
	if [ -z "$t" ]; then
		echo "note: could not scrape busybox.net, falling back to busybox-1.38.0" >&2
		t=busybox-1.38.0.tar.bz2
	fi
	printf '%s\n' "$t"
}

say "linux kernel"
KVER=$(kernel_version)
echo "using linux $KVER"
if [ ! -d "$WORK/linux-$KVER" ]; then
	dl_ok=0
	for url in \
		"https://codeload.github.com/gregkh/linux/tar.gz/refs/tags/v$KVER" \
		"https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/linux-$KVER.tar.xz"; do
		say "trying $url"
		if curl -fL --retry 2 --max-time 1800 -o "$WORK/linux-src.dl" "$url"; then
			dl_ok=1
			break
		fi
	done
	[ "$dl_ok" = 1 ] || { echo "could not download linux-$KVER; set FORCE_KERNEL_VERSION or check the URL"; exit 1; }
	tar -xf "$WORK/linux-src.dl" -C "$WORK"
	rm -f "$WORK/linux-src.dl"
	# Both archive hosts unpack to linux-<version>/.
	[ -d "$WORK/linux-$KVER" ] || { echo "expected $WORK/linux-$KVER after unpack"; exit 1; }
fi
printf '%s\n' "$KVER" >"$WORK/kernel.version"

say "busybox"
BBT=$(busybox_tarball)
BBVER=${BBT#busybox-}
BBVER=${BBVER%.tar.bz2}
if [ ! -d "$WORK/busybox-$BBVER" ]; then
	curl -fL --retry 3 --max-time 600 -o "$WORK/$BBT" "https://busybox.net/downloads/$BBT"
	tar -xf "$WORK/$BBT" -C "$WORK"
	rm -f "$WORK/$BBT"
fi
printf '%s\n' "$BBVER" >"$WORK/busybox.version"

say "toolchain"
# Captured into variables rather than piped through `sed -n 1p`: sed closes the
# pipe after one line, the tool then takes SIGPIPE and pipefail fails the build.
gcc_v=$("${CROSS_COMPILE}gcc" --version)
qemu_v=$("$QEMU" --version)
dtc_v=$(dtc --version)
printf '%s\n%s\n%s\n' "${gcc_v%%$'\n'*}" "${qemu_v%%$'\n'*}" "${dtc_v%%$'\n'*}"
echo "sources ready in $WORK"

say "toolchain self-test"
# busybox links a *static userspace binary*, which needs more than a cross
# compiler: the target C library headers and libc.a. Linking a three-line
# program here costs a second and names the missing package, instead of the
# same problem surfacing ten minutes later as a busybox compile error.
CHECK="$WORK/.toolcheck"
printf 'int main(void){return 0;}\n' >"$CHECK.c"
if "${CROSS_COMPILE}gcc" -static -o "$CHECK" "$CHECK.c" 2>"$CHECK.err"; then
	echo "static $ARCH linking works"
else
	cat "$CHECK.err"
	echo "the cross toolchain cannot link a static $ARCH program."
	echo "On x86 CI that means the target C library is missing: sudo apt-get install libc6-dev-$ARCH-cross"
	exit 1
fi
rm -f "$CHECK" "$CHECK.c" "$CHECK.err"
