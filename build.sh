#!/usr/bin/env bash
# nerdctl-full の tarball から Ubuntu 向け .deb を作る
#
# usage: ./build.sh [VERSION] [ARCH]
#   VERSION: 例 2.1.6 (省略時は GitHub の latest)
#   ARCH   : amd64 | arm64 (省略時は amd64)
#
# 必要なもの: bash, curl, tar, sha256sum, sed, nfpm
# ※ 実行ビットを保つため Linux 上 (WSL なら Linux 側 FS が無難) で実行すること
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-${VERSION:-}}"
ARCH="${2:-${ARCH:-amd64}}"
PREFIX=/opt/nerdctl
OUT_DIR="${OUT_DIR:-./dist}"

case "$ARCH" in
	amd64|arm64) ;;
	*) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

command -v nfpm >/dev/null || {
	echo "nfpm not found: https://nfpm.goreleaser.com/install/" >&2
	exit 1
}

if [ -z "$VERSION" ]; then
	latest_url=$(curl -fsSLo /dev/null -w '%{url_effective}' https://github.com/containerd/nerdctl/releases/latest)
	VERSION="${latest_url##*/v}"
fi
VERSION="${VERSION#v}"

TARBALL="nerdctl-full-${VERSION}-linux-${ARCH}.tar.gz"
BASE_URL="https://github.com/containerd/nerdctl/releases/download/v${VERSION}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
DL="$WORK/download"
STAGING="$WORK/staging"
mkdir -p "$DL" "$STAGING$PREFIX" "$STAGING/systemd"

echo ">> downloading $TARBALL"
curl -fSL --retry 3 -o "$DL/$TARBALL" "$BASE_URL/$TARBALL"
curl -fsSL --retry 3 -o "$DL/SHA256SUMS" "$BASE_URL/SHA256SUMS"
(cd "$DL" && grep " ${TARBALL}\$" SHA256SUMS | sha256sum -c -)

echo ">> extracting to $PREFIX"
tar -xzf "$DL/$TARBALL" -C "$STAGING$PREFIX" --no-same-owner

# systemd ユニット: /usr/local/bin -> /opt/nerdctl/bin に書き換え、
# shim / runc / CNI を見つけられるよう PATH を通す
UNIT_PATH="${PREFIX}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
for unit in containerd.service buildkit.service stargz-snapshotter.service; do
	src="$STAGING$PREFIX/lib/systemd/system/$unit"
	[ -f "$src" ] || { echo "missing unit in tarball: $unit" >&2; exit 1; }
	sed -e "s#/usr/local/bin/#${PREFIX}/bin/#g" \
	    -e "/^\[Service\]/a Environment=\"PATH=${UNIT_PATH}\"" \
	    "$src" > "$STAGING/systemd/$unit"
done
# 二重配置を避けるため /opt 側のユニットは削除
rm -rf "$STAGING$PREFIX/lib/systemd"
rmdir "$STAGING$PREFIX/lib" 2>/dev/null || true

# nfpm は contents.src の環境変数を展開しないため、ここで埋め込む
sed "s#\${STAGING}#${STAGING}#g" nfpm.yaml > "$WORK/nfpm.yaml"

mkdir -p "$OUT_DIR"
echo ">> building deb"
VERSION="$VERSION" ARCH="$ARCH" \
	nfpm package --config "$WORK/nfpm.yaml" --packager deb --target "$OUT_DIR/"

ls -l "$OUT_DIR"/*.deb
