#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-1.0.0}"
PKG="$ROOT_DIR/package"
OUT="$ROOT_DIR/360-cli_${VERSION}_all.deb"

rm -rf "$PKG" "$OUT"
mkdir -p \
  "$PKG/DEBIAN" \
  "$PKG/usr/bin" \
  "$PKG/usr/share/360-cli/ui"

install -m 0755 "$ROOT_DIR/360.sh" "$PKG/usr/share/360-cli/360.sh"

if [[ -f "$ROOT_DIR/ui/banner.txt" ]]; then
  install -m 0644 "$ROOT_DIR/ui/banner.txt" "$PKG/usr/share/360-cli/ui/banner.txt"
fi

cat > "$PKG/usr/bin/360" <<'SH'
#!/usr/bin/env bash
exec /usr/share/360-cli/360.sh "$@"
SH
chmod 0755 "$PKG/usr/bin/360"

cat > "$PKG/DEBIAN/control" <<CTRL
Package: 360-cli
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Depends: bash, curl, python3
Maintainer: 360 Digital Co.
Description: 360 terminal client
 Terminal client for 360 Search and 360 services.
CTRL

dpkg-deb --build "$PKG" "$OUT" >/dev/null
rm -rf "$PKG"
printf '%s\n' "$OUT"
