#!/usr/bin/env bash
# ==============================================================================
# CrimeIntel — Multi-Distro Packaging Pipeline (.tar.gz, .deb, .AppImage)
# ==============================================================================
# Builds all three Linux release formats from the Flutter release bundle:
#   1. .tar.gz (Universal portable archive)
#   2. .deb (Debian / Ubuntu / Mint native package)
#   3. .AppImage (Distro-agnostic standalone executable)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUNDLE_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
VERSION="1.0.0"

echo "======================================================"
echo " CrimeIntel Multi-Distro Packaging Pipeline (v$VERSION)"
echo "======================================================"

# Ensure output directory exists
mkdir -p "$DIST_DIR"

# ------------------------------------------------------------------------------
# 0. Build Flutter Linux Release Bundle if missing
# ------------------------------------------------------------------------------
if [ ! -f "$BUNDLE_DIR/crime_intel" ]; then
  echo "[-] Building Flutter Linux release bundle..."
  (cd "$ROOT_DIR" && flutter build linux --release)
fi

echo "[✓] Verified release bundle at $BUNDLE_DIR"

# Ensure icon exists
if [ ! -f "$ROOT_DIR/assets/icons/crime_intel.png" ]; then
  echo "[-] Extracting icon..."
  mkdir -p "$ROOT_DIR/assets/icons"
  python3 -c "
from PIL import Image
im = Image.open('$ROOT_DIR/windows/runner/resources/app_icon.ico')
best_frame = None
max_w = 0
frame = 0
while True:
    try:
        im.seek(frame)
        if im.size[0] > max_w:
            max_w = im.size[0]
            best_frame = im.copy()
        frame += 1
    except EOFError:
        break
best_frame.save('$ROOT_DIR/assets/icons/crime_intel.png')
"
fi

# Ensure desktop entry exists
if [ ! -f "$ROOT_DIR/linux/crime-intel.desktop" ]; then
  cat << 'EOF' > "$ROOT_DIR/linux/crime-intel.desktop"
[Desktop Entry]
Name=CrimeIntel
GenericName=Criminal Network Analysis System
Comment=AI-powered criminal network analysis and multi-source intelligence link analysis
Exec=crime-intel %U
Icon=crime-intel
Terminal=false
Type=Application
Categories=Utility;Security;Science;
Keywords=crime;intelligence;analysis;network;graph;investigation;
StartupWMClass=crime_intel
EOF
fi

# ------------------------------------------------------------------------------
# 1. Package .tar.gz (Universal Portable Archive)
# ------------------------------------------------------------------------------
echo ""
echo "[1/3] Packaging .tar.gz (Universal Portable Archive)..."
TAR_STAGING="/tmp/crime_intel_tar_staging"
TAR_NAME="crime-intel-linux-x64-v${VERSION}"
rm -rf "$TAR_STAGING"
mkdir -p "$TAR_STAGING/$TAR_NAME"

cp -r "$BUNDLE_DIR"/* "$TAR_STAGING/$TAR_NAME/"
cp "$ROOT_DIR/scripts/setup.sh" "$TAR_STAGING/$TAR_NAME/setup.sh"
chmod +x "$TAR_STAGING/$TAR_NAME/setup.sh"
mkdir -p "$TAR_STAGING/$TAR_NAME/scripts"
cp "$ROOT_DIR/scripts/setup.sh" "$TAR_STAGING/$TAR_NAME/scripts/setup.sh"
chmod +x "$TAR_STAGING/$TAR_NAME/scripts/setup.sh"
cp "$ROOT_DIR/.env.example" "$TAR_STAGING/$TAR_NAME/.env.example"
cp "$ROOT_DIR/INSTALL.md" "$TAR_STAGING/$TAR_NAME/INSTALL.md"
cp "$ROOT_DIR/README.md" "$TAR_STAGING/$TAR_NAME/README.md"

tar -czf "$DIST_DIR/$TAR_NAME.tar.gz" -C "$TAR_STAGING" "$TAR_NAME"
rm -rf "$TAR_STAGING"
echo "  [✓] Created $DIST_DIR/$TAR_NAME.tar.gz"

# ------------------------------------------------------------------------------
# 2. Package .deb (Debian / Ubuntu Native Package)
# ------------------------------------------------------------------------------
echo ""
echo "[2/3] Packaging .deb (Debian / Ubuntu Native Package)..."
DEB_STAGING="/tmp/crime_intel_deb_staging"
DEB_NAME="crime-intel_${VERSION}_amd64"
rm -rf "$DEB_STAGING"

# Directory structure
mkdir -p "$DEB_STAGING/DEBIAN"
mkdir -p "$DEB_STAGING/opt/crime-intel"
mkdir -p "$DEB_STAGING/usr/bin"
mkdir -p "$DEB_STAGING/usr/share/applications"
mkdir -p "$DEB_STAGING/usr/share/pixmaps"
mkdir -p "$DEB_STAGING/usr/share/icons/hicolor/256x256/apps"

# Control file
cat << EOF > "$DEB_STAGING/DEBIAN/control"
Package: crime-intel
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Team BlaZe <https://github.com/BlaZe08-Dev/Crime-Intel>
Depends: libc6 (>= 2.31), libgtk-3-0, libglib2.0-0
Description: AI-Powered Criminal Network Analysis System
 CrimeIntel is an intelligent workstation application built with Flutter
 for Linux desktop. Features include synthetic criminal record analysis,
 retrieval-grounded LLM assistant (RAG), automatically derived entity graphs,
 and a tamper-evident cryptographic audit log.
EOF

# Install payload to /opt/crime-intel
cp -r "$BUNDLE_DIR"/* "$DEB_STAGING/opt/crime-intel/"
cp "$ROOT_DIR/scripts/setup.sh" "$DEB_STAGING/opt/crime-intel/setup.sh"
chmod +x "$DEB_STAGING/opt/crime-intel/setup.sh"
cp "$ROOT_DIR/.env.example" "$DEB_STAGING/opt/crime-intel/.env.example"
cp "$ROOT_DIR/INSTALL.md" "$DEB_STAGING/opt/crime-intel/INSTALL.md"
cp "$ROOT_DIR/README.md" "$DEB_STAGING/opt/crime-intel/README.md"

# /usr/bin launcher script
cat << 'EOF' > "$DEB_STAGING/usr/bin/crime-intel"
#!/usr/bin/env bash
# CrimeIntel Application Launcher
APP_DIR="/opt/crime-intel"
USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/crime-intel"
mkdir -p "$USER_CONFIG_DIR"

if [ ! -f "$USER_CONFIG_DIR/.env" ] && [ -f "$APP_DIR/.env.example" ]; then
  cp "$APP_DIR/.env.example" "$USER_CONFIG_DIR/.env"
fi

# Use working directory .env if present; otherwise user config dir
if [ ! -f ".env" ]; then
  cd "$USER_CONFIG_DIR"
fi

exec "$APP_DIR/crime_intel" "$@"
EOF
chmod 755 "$DEB_STAGING/usr/bin/crime-intel"

# /usr/bin setup helper script
cat << 'EOF' > "$DEB_STAGING/usr/bin/crime-intel-setup"
#!/usr/bin/env bash
exec /opt/crime-intel/setup.sh "$@"
EOF
chmod 755 "$DEB_STAGING/usr/bin/crime-intel-setup"

# Desktop integration and icons
cp "$ROOT_DIR/linux/crime-intel.desktop" "$DEB_STAGING/usr/share/applications/crime-intel.desktop"
chmod 644 "$DEB_STAGING/usr/share/applications/crime-intel.desktop"
cp "$ROOT_DIR/assets/icons/crime_intel.png" "$DEB_STAGING/usr/share/pixmaps/crime-intel.png"
chmod 644 "$DEB_STAGING/usr/share/pixmaps/crime-intel.png"
cp "$ROOT_DIR/assets/icons/crime_intel.png" "$DEB_STAGING/usr/share/icons/hicolor/256x256/apps/crime-intel.png"
chmod 644 "$DEB_STAGING/usr/share/icons/hicolor/256x256/apps/crime-intel.png"

# Build .deb
dpkg-deb --build --root-owner-group "$DEB_STAGING" "$DIST_DIR/$DEB_NAME.deb"
rm -rf "$DEB_STAGING"
echo "  [✓] Created $DIST_DIR/$DEB_NAME.deb"

# ------------------------------------------------------------------------------
# 3. Package AppImage (Distro-Agnostic Standalone Executable)
# ------------------------------------------------------------------------------
echo ""
echo "[3/3] Packaging AppImage (Distro-Agnostic Standalone Executable)..."
APPDIR="/tmp/CrimeIntel.AppDir"
APPIMAGE_NAME="CrimeIntel-${VERSION}-x86_64.AppImage"
rm -rf "$APPDIR"

mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/usr/share/crime-intel"

# Copy binary, libs, and assets
cp -r "$BUNDLE_DIR"/* "$APPDIR/usr/bin/"
cp "$ROOT_DIR/linux/crime-intel.desktop" "$APPDIR/crime-intel.desktop"
cp "$ROOT_DIR/linux/crime-intel.desktop" "$APPDIR/usr/share/applications/crime-intel.desktop"
cp "$ROOT_DIR/assets/icons/crime_intel.png" "$APPDIR/crime-intel.png"
cp "$ROOT_DIR/assets/icons/crime_intel.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/crime-intel.png"
ln -sf crime-intel.png "$APPDIR/.DirIcon"

cp "$ROOT_DIR/scripts/setup.sh" "$APPDIR/usr/share/crime-intel/setup.sh"
cp "$ROOT_DIR/.env.example" "$APPDIR/usr/share/crime-intel/.env.example"
cp "$ROOT_DIR/INSTALL.md" "$APPDIR/usr/share/crime-intel/INSTALL.md"
cp "$ROOT_DIR/README.md" "$APPDIR/usr/share/crime-intel/README.md"

# AppRun launcher
cat << 'EOF' > "$APPDIR/AppRun"
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/usr/bin/lib:${LD_LIBRARY_PATH:-}"

USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/crime-intel"
mkdir -p "$USER_CONFIG_DIR"

if [ ! -f "$USER_CONFIG_DIR/.env" ] && [ -f "${HERE}/usr/share/crime-intel/.env.example" ]; then
  cp "${HERE}/usr/share/crime-intel/.env.example" "$USER_CONFIG_DIR/.env"
fi

if [ ! -f ".env" ]; then
  cd "$USER_CONFIG_DIR"
fi

exec "${HERE}/usr/bin/crime_intel" "$@"
EOF
chmod 755 "$APPDIR/AppRun"

# Ensure appimagetool is ready
APPIMAGETOOL="/tmp/squashfs-root/AppRun"
if [ ! -x "$APPIMAGETOOL" ]; then
  echo "[-] Preparing appimagetool..."
  curl -fsSL -o /tmp/appimagetool "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x /tmp/appimagetool
  (cd /tmp && /tmp/appimagetool --appimage-extract)
fi

# Build AppImage
ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$DIST_DIR/$APPIMAGE_NAME"
chmod +x "$DIST_DIR/$APPIMAGE_NAME"
rm -rf "$APPDIR"
echo "  [✓] Created $DIST_DIR/$APPIMAGE_NAME"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo "======================================================"
echo " Packaging Completed Successfully!"
echo "======================================================"
ls -lh "$DIST_DIR"
