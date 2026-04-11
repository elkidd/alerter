#!/bin/bash
set -euo pipefail

PRODUCT_NAME="melding"
BUNDLE_ID="io.github.elkidd.melding"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$PRODUCT_NAME.app"
VERSION_FILE="$PROJECT_DIR/Sources/Melding/MeldingCommand.swift"

# --- Version bump (semver patch) ---
CURRENT_VERSION=$(grep 'version:' "$VERSION_FILE" | sed 's/.*version: "\(.*\)".*/\1/')
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
VERSION="$MAJOR.$MINOR.$((PATCH + 1))"

echo "==> Bumping version $CURRENT_VERSION → $VERSION"
sed -i '' "s/version: \"$CURRENT_VERSION\"/version: \"$VERSION\"/" "$VERSION_FILE"

# Clean dist
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Build
echo "==> Building release..."
swift build -c release --package-path "$PROJECT_DIR"

# Assemble .app bundle
echo "==> Assembling app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$PRODUCT_NAME"                           "$APP_BUNDLE/Contents/MacOS/"
cp "$PROJECT_DIR/Sources/Melding/Info.plist"            "$APP_BUNDLE/Contents/"
cp "$PROJECT_DIR/Sources/Melding/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

# Ad-hoc sign (no Apple Developer account required)
echo "==> Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

# Zip
ZIP_NAME="$PRODUCT_NAME-$VERSION"
ZIP_FILE="$DIST_DIR/$ZIP_NAME.zip"
echo "==> Creating zip..."
cd "$DIST_DIR" && mkdir -p "$ZIP_NAME" && cp -r "$PRODUCT_NAME.app" "$ZIP_NAME/" && zip -r "$ZIP_FILE" "$ZIP_NAME" && rm -rf "$ZIP_NAME" && cd "$PROJECT_DIR"
ZIP_SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')

# GitHub Release (commit + tag + push after build succeeds)
TAG="v$VERSION"
CURRENT_GH_USER=$(gh api user --jq .login 2>/dev/null || echo "unknown")
echo "==> Switching to elkidd GitHub account..."
gh auth switch --user elkidd
gh auth setup-git
echo "==> Committing and pushing tag $TAG..."
git -C "$PROJECT_DIR" add "$VERSION_FILE"
git -C "$PROJECT_DIR" commit -m "🔖 bump version to $VERSION"
git -C "$PROJECT_DIR" push origin master
git -C "$PROJECT_DIR" tag "$TAG"
git -C "$PROJECT_DIR" push origin "$TAG"
gh release create "$TAG" "$ZIP_FILE" \
    --repo "elkidd/melding" \
    --title "$VERSION" \
    --generate-notes
echo "==> Switching back to $CURRENT_GH_USER..."
gh auth switch --user "$CURRENT_GH_USER"

echo ""
echo "==> Done!"
echo "   $ZIP_FILE"
echo "   SHA256: $ZIP_SHA256"
echo ""
echo "   Update Homebrew formula:"
echo "   url: https://github.com/elkidd/melding/releases/download/$TAG/$PRODUCT_NAME-$VERSION.zip"
echo "   sha256: $ZIP_SHA256"
