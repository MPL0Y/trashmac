# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

TrashMac is a macOS menu bar app (single file, `main.swift`) that animates a file icon flying from the cursor into the Dock's Trash whenever something lands in `~/.Trash`. The repo also holds its landing page (`index.html`), served by Cloudflare Workers.

## Commands

```sh
./build.sh                        # universal (arm64 + x86_64) TrashMac.app → build/dmg/, packaged as TrashMac.dmg
open build/dmg/TrashMac.app       # run without mounting the DMG
npx wrangler deploy               # deploy landing page to trashmac.agenticrabbit.com
```

No Xcode project, package manager, tests, or linter. `build.sh` calls `swiftc` directly and writes `Info.plist` inline; override the SDK with `SDK=... ./build.sh` if the default pick fails. Use the menu bar item's "Test Animation" (⌘T) to exercise the animation without deleting files.

## Architecture (`main.swift`)

- **Detection**: an FSEvents stream on `~/.Trash`. The app can't stat files inside `~/.Trash` (TCC), so arrivals are inferred purely from event flags (created/renamed and not removed). Icons come from the file extension via `UTType`, not the file itself. Multi-file deletes cap at 5 flying icons.
- **Target**: `trashRect()` walks the Dock's accessibility tree for the `AXTrashDockItem` subrole and converts AX (top-left origin) coords to Cocoa (bottom-left). Needs Accessibility permission; without it, falls back to a guessed bottom-right position.
- **Animation**: each flight gets a transparent, click-through, borderless window spanning all screens at `.screenSaver` level (above the Dock), with a `CALayer` animated along a quadratic arc; the window is removed on completion.
- App runs as `.accessory` / `LSUIElement` (no Dock icon).

## Gotchas

- `build.sh` code-signs ad-hoc with an **identifier-based designated requirement** (`com.trash.mac`) so the Accessibility grant survives rebuilds. Don't change the bundle ID or drop that `-r` flag, or users must re-grant permission every build.
- `.assetsignore` whitelists only `index.html` for the Worker (`assets.directory` is the repo root) — anything else added at root stays private unless explicitly un-ignored.
- `ponytail:` comments mark deliberate shortcuts with known limits (e.g. "Put Back" also triggers an animation).
