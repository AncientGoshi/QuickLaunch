# QuickLaunch

QuickLaunch is a macOS menu-bar launcher with a Rust core. With QuickLaunch running, **⌘F12** opens your saved files, folders, apps and websites. The first launch opens the target editor; later, use **⌘F12 → Edit Targets…** in the menu bar.

## Build and launch

Requires macOS 13 or later, mise and Apple Command Line Tools (`xcode-select --install` if missing). From this directory:

```sh
mise trust
mise install
mise run launch
```

`mise run build` produces an ad-hoc signed `dist/QuickLaunch.app` you can open in Finder. `mise run dmg` builds `dist/QuickLaunch.dmg`, with a custom Finder background and an Applications shortcut. Packaging also needs Python 3.9+ and uses a temporary virtual environment with hash-pinned dependencies. This local build is ad-hoc signed and not notarized. `mise run test` runs Rust tests and verifies the bundle. `mise run lint` checks formatting and Clippy (install `rustfmt` and `clippy` for the pinned Rust toolchain if needed).

## Set your targets

Enter one item per line, then click **Save**. For example:

```text
~/Documents/Project Plan.pdf
app:Calculator
https://example.com/
```

You can use absolute paths, paths starting with `~/`, installed app names prefixed with `app:`, and HTTP(S) URLs. Blank lines and whole-line `#` comments are ignored. Files and URLs open with your macOS defaults. **Also open targets when QuickLaunch starts** is optional and off by default; it does not add QuickLaunch to Login Items.

If F12 controls your speaker volume, try **Fn + ⌘ + F12**. If macOS rejects the shortcut registration, the app shows the status in its menu; **Open Saved Targets** still works there. The shortcut only works while QuickLaunch is running. Quit it from its menu-bar menu.
