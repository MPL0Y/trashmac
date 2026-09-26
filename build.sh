#!/bin/sh
# Builds TrashMac.app (universal) and packages it into TrashMac.dmg.
set -e
# Newest SDK matching the installed Swift compiler (CLT can ship a newer SDK than swiftc).
SDK=${SDK:-$(xcrun --show-sdk-path --sdk macosx26.5 2>/dev/null || xcrun --show-sdk-path)}
cd "$(dirname "$0")"
rm -rf build && mkdir -p build/dmg/TrashMac.app/Contents/MacOS
APP=build/dmg/TrashMac.app

for arch in arm64 x86_64; do
  swiftc -O -sdk "$SDK" -target $arch-apple-macos13 main.swift -o build/TrashMac-$arch
done
lipo -create build/TrashMac-arm64 build/TrashMac-x86_64 -output $APP/Contents/MacOS/TrashMac

cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.trash.mac</string>
  <key>CFBundleName</key><string>TrashMac</string>
  <key>CFBundleExecutable</key><string>TrashMac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
EOF

mkdir -p build/AppIcon.iconset $APP/Contents/Resources
for sz in 16 32 128 256 512; do
  sips -z $sz $sz icon.png --out build/AppIcon.iconset/icon_${sz}x${sz}.png >/dev/null
  sips -z $((sz*2)) $((sz*2)) icon.png --out build/AppIcon.iconset/icon_${sz}x${sz}@2x.png >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o $APP/Contents/Resources/AppIcon.icns

# Identifier-based requirement so the Accessibility grant survives rebuilds (ad-hoc default pins the cdhash).
codesign --force -s - -r='designated => identifier "com.trash.mac"' $APP
ln -s /Applications build/dmg/Applications
hdiutil create -volname TrashMac -srcfolder build/dmg -ov -format UDZO TrashMac.dmg
