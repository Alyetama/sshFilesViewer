#!/usr/bin/env bash
#
# Publishes SSHFilesViewer to GitHub: creates/updates the repo, sets the
# description + topics, enables GitHub Pages (served from /docs), and cuts a
# release with a zipped .app.
#
# This script is NOT run automatically. Review it, make sure you're logged in
# (`gh auth status`), then run it yourself:  ./scripts/publish.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="Alyetama/sshFilesViewer"
VERSION="v1.0.0"
DESCRIPTION="A beautiful, robust native macOS app to browse, preview, edit, and download files on your remote machines over SSH."

command -v gh >/dev/null || { echo "✗ GitHub CLI (gh) not found — install it first."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✗ Not logged in. Run: gh auth login"; exit 1; }

# 1. Create the repo on the first run (no-op if it already exists), pushing main.
if ! gh repo view "$REPO" >/dev/null 2>&1; then
	echo "▸ Creating $REPO …"
	gh repo create "$REPO" --public --source=. --remote=origin --push \
		--description "$DESCRIPTION"
else
	echo "▸ Repo exists — pushing main …"
	git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$REPO.git"
	git push -u origin main
fi

# 2. Description + topics (shown on the GitHub repo page).
echo "▸ Setting description and topics …"
gh repo edit "$REPO" --description "$DESCRIPTION" \
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
		-f "source[branch]=main" -f "source[path]=/docs"
echo "  Pages will be at: https://${REPO%%/*}.github.io/${REPO##*/}/"

# 4. Build a release .app, zip it (preserving the bundle), and cut a release.
echo "▸ Building release …"
./build.sh release
echo "▸ Zipping app …"
rm -f SSHFilesViewer.zip
ditto -c -k --sequesterRsrc --keepParent SSHFilesViewer.app SSHFilesViewer.zip
echo "▸ Creating release $VERSION …"
gh release create "$VERSION" SSHFilesViewer.zip \
	--repo "$REPO" \
	--title "SSH Files Viewer ${VERSION#v}" \
	--notes "Native macOS SSH file browser: browse, preview (syntax-highlighted code, images, CSV tables), edit + save, and download files on your remote machines. Ad-hoc signed — right-click → Open on first launch."

echo "✓ Published. Release: https://github.com/$REPO/releases/tag/$VERSION"
