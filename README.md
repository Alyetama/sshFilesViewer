<p align="center">
  <img src="docs/icon.png" width="120" alt="SSH Files Viewer icon" />
</p>

<h1 align="center">SSH Files Viewer</h1>

<p align="center">
  A beautiful, robust <strong>native macOS app</strong> to browse, preview,
  edit, and download files on your remote machines over SSH.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-macOS%2013%2B-blue" alt="Built with SwiftUI" />
</p>

## Download

Grab the latest `SSHFilesViewer.dmg` from the
[**releases page**](https://github.com/Alyetama/sshFilesViewer/releases/latest),
open it, and drag the app into your **Applications** folder.

### Opening the app the first time

SSH Files Viewer is open-source and ad-hoc signed — there's no paid Apple
Developer ID — so macOS Gatekeeper blocks it on first launch. After moving the
app into **Applications**, do one of these once:

**Option A — Terminal (quickest)**

```bash
xattr -dr com.apple.quarantine /Applications/SSHFilesViewer.app
```

Then open the app normally.

**Option B — System Settings**

1. Double-click the app. When macOS says it can't verify the developer, click **Done**.
2. Open **System Settings → Privacy & Security**.
3. Scroll to **Security** and click **Open Anyway** next to the "SSHFilesViewer was blocked" message.
4. Click **Open** to confirm. It launches normally from then on.

## Features

- **Saved connections** — manage a sidebar of remote machines, each with a live
  connection-status indicator.
- **Three auth methods** — SSH agent, a private key file, or a password
  (stored securely in the macOS **Keychain**).
- **Fast browsing** — uses OpenSSH **connection multiplexing**, so the first
  connect authenticates once and every later listing, preview, and download
  reuses the same session.
- **Full file browser** — breadcrumb navigation, back / forward / up / home,
  a live filter field, color-coded file-type icons, sizes, and modified dates.
- **Inline preview** — view text and images right inside the app, or open any
  file in its default macOS app.
- **Downloads** — one-click download to your Downloads folder (or *Download As…*
  to choose), with a live progress tray and *Reveal in Finder*.

## Why it’s robust

- **No third-party dependencies.** It drives the system `ssh` binary, so it
  transparently uses your existing `~/.ssh/config`, keys, agent, `known_hosts`,
  and even `ProxyJump`/bastion setups.
- **Careful listing parser** that preserves exact filenames (including spaces),
  handles symlinks, ACL suffixes, device files, and is portable across
  Linux/BSD remotes — no GNU-only or Python assumptions.
- **Headless password auth** via an `SSH_ASKPASS` helper with
  `SSH_ASKPASS_REQUIRE=force` — the password is never placed on a command line.
- Host keys are accepted on first use (`StrictHostKeyChecking=accept-new`).

## Build & run

```bash
./run.sh          # build a release .app and launch it
./build.sh        # just build SSHFilesViewer.app
./build.sh debug  # debug build
```

Requirements: macOS 13+, the Swift 6 toolchain (Xcode command-line tools), and
the `ssh` binary (ships with macOS).

## How it works

| Action            | Under the hood                                            |
|-------------------|-----------------------------------------------------------|
| List a folder     | `ssh host 'cd -- DIR && LC_ALL=C ls -la'` → parsed        |
| Preview a file    | `ssh host 'head -c N -- FILE'` (text/image sniffing)      |
| Download a file   | `ssh host 'cat -- FILE'` streamed to disk, with progress  |
| Connection reuse  | `ControlMaster=auto` + `ControlPersist`                   |

## Project layout

```
Sources/SSHFilesViewer/
  App.swift            – @main app + menu commands + Settings
  Models.swift         – Connection, RemoteFile, path helpers
  Persistence.swift    – connections.json + Keychain
  SSHClient.swift      – the SSH transport, ls parser, askpass helper
  Session.swift        – BrowserSession + AppModel + downloads
  Theme.swift          – icons, colors, formatting
  Views/               – ContentView, Sidebar, Editor, Browser, Preview, Settings
Tools/                 – app-icon generator
```

## Notes

- For key-based auth with a passphrase-protected key, add the key to your
  `ssh-agent` first (`ssh-add ~/.ssh/id_…`) and use the **SSH Agent** method.
- The app is ad-hoc code-signed and unsandboxed (so it can run `ssh` and write
  to your chosen download folder).

## Security

- Passwords are stored in the macOS **Keychain** and are never written to disk
  in plaintext or placed on a command line — password auth is driven through an
  `SSH_ASKPASS` helper that reads the value from the process environment.
- Every remote path is single-quote escaped before it's used in a shell command,
  and the ssh hostname is passed after `--` to prevent option injection.
- Host keys are accepted on first use (`StrictHostKeyChecking=accept-new`); after
  that, a changed key is rejected like normal OpenSSH.
- Saved connections live in `~/Library/Application Support/SSHFilesViewer/`, not
  in this repository.

## Publishing

A landing page lives in [`docs/`](docs/index.html) and is served via GitHub
Pages. Publishing is a single script (review it first — it is not run for you):

```bash
./scripts/publish.sh
```

It creates/updates the GitHub repo, sets the description and topics, enables
GitHub Pages from `main` `/docs`, and cuts a release with a zipped `.app`.

## License

[MIT](LICENSE) © Alyetama. Bundled language logos are from
[devicon](https://github.com/devicons/devicon) (MIT).
