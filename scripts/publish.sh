#!/usr/bin/env bash
#
# Publishes SSHFilesViewer to GitHub: creates/updates the repo (description,
# topics, website), enables GitHub Pages (served from /docs), builds a DMG and
# attaches it to a release. The DMG is built fresh here and is NOT committed.
#
# This script is NOT run automatically. Review it, log in (`gh auth login`),
# then run it yourself:  ./scripts/publish.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="Alyetama/sshFilesViewer"
VERSION="v1.0.0"
DESCRIPTION="A beautiful, robust native macOS app to browse, preview, edit, and download files on your remote machines over SSH."
HOMEPAGE="https://alyetama.github.io/sshFilesViewer/"
DMG="SSHFilesViewer.dmg"

command -v gh >/dev/null || { echo "✗ GitHub CLI (gh) not found — install it first."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✗ Not logged in. Run: gh auth login"; exit 1; }

# 1. Create the repo on first run (no-op if it exists), pushing main.
if ! gh repo view "$REPO" >/dev/null 2>&1; then
	echo "▸ Creating $REPO …"
	gh repo create "$REPO" --public --source=. --remote=origin --push --description "$DESCRIPTION"
else
	echo "▸ Repo exists — pushing main …"
	git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$REPO.git"
	git push -u origin main
fi

# 2. Description, website, and topics (shown on the GitHub repo page).
echo "▸ Setting description, website, and topics …"
gh repo edit "$REPO" \
	--description "$DESCRIPTION" \
	--homepage "$HOMEPAGE" \
	--add-topic macos \
	--add-topic macos-app \
	--add-topic swift \
	--add-topic swiftui \
	--add-topic ssh \
	--add-topic sftp \
	--add-topic file-browser \
	--add-topic file-manager \
	--add-topic remote \
	--add-topic syntax-highlighting \
	--add-topic developer-tools

# 3. Enable GitHub Pages, served from /docs on main.
echo "▸ Enabling GitHub Pages (main /docs) …"
gh api -X POST "repos/$REPO/pages" \
	-f "source[branch]=main" -f "source[path]=/docs" 2>/dev/null \
	|| gh api -X PUT "repos/$REPO/pages" \
		-f "source[branch]=main" -f "source[path]=/docs" 2>/dev/null || true
echo "  Pages: $HOMEPAGE"

# 4. Build the app and package a drag-to-Applications DMG.
echo "▸ Building release …"
./build.sh release
echo "▸ Building $DMG …"
STAGING="$(mktemp -d)"
cp -R SSHFilesViewer.app "$STAGING/SSHFilesViewer.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "SSH Files Viewer" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "  → $DMG ($(du -h "$DMG" | cut -f1))"

# 5. Cut a release with the DMG. (The Pages "Download" button points at
#    releases/latest/download/SSHFilesViewer.dmg, so keep this asset name.)
NOTES_FILE="$(mktemp)"
cat > "$NOTES_FILE" <<'NOTES'
Native macOS app to browse, preview (syntax-highlighted code, images, CSV
tables), edit + save, and download files on your remote machines over SSH.

### Install
Open `SSHFilesViewer.dmg` and drag the app into **Applications**.

### Opening it the first time
The app is open-source and ad-hoc signed (no paid Apple Developer ID), so macOS
Gatekeeper blocks it on first launch. Do one of these once:

**Terminal (quickest)**
```
xattr -dr com.apple.quarantine /Applications/SSHFilesViewer.app
```
then open it normally.

**System Settings**
1. Double-click the app, then click **Done** on the warning.
2. **System Settings → Privacy & Security**.
3. Click **Open Anyway** next to the "SSHFilesViewer was blocked" message, then **Open**.
NOTES

echo "▸ Creating release $VERSION …"
gh release create "$VERSION" "$DMG" \
	--repo "$REPO" \
	--title "SSH Files Viewer ${VERSION#v}" \
	--notes-file "$NOTES_FILE"
rm -f "$NOTES_FILE"

echo "✓ Published."
echo "  Release:  https://github.com/$REPO/releases/tag/$VERSION"
echo "  Download: https://github.com/$REPO/releases/latest/download/$DMG"
echo "  Website:  $HOMEPAGE"
