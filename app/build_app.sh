#!/bin/sh
# Build "HDP5000 ID Studio.app" (universal: Apple silicon + Intel) into app/build/.
set -e
cd "$(dirname "$0")"
for a in arm64 x86_64; do
  swift build -c release --triple $a-apple-macosx13.0 --scratch-path .build/$a
done
BIN=.build/IDStudio-universal
lipo -create -output "$BIN" .build/arm64/release/IDStudio .build/x86_64/release/IDStudio
APP="build/HDP5000 ID Studio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/IDStudio"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HDP5000 ID Studio</string>
  <key>CFBundleDisplayName</key><string>HDP5000 ID Studio</string>
  <key>CFBundleIdentifier</key><string>com.stdiox.hdp5000.idstudio</string>
  <key>CFBundleExecutable</key><string>IDStudio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>ID Card Design</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>com.stdiox.hdp5000.idcard</string></array>
      <key>NSDocumentClass</key><string>$(PRODUCT_MODULE_NAME).CardDocument</string>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>com.stdiox.hdp5000.idcard</string>
      <key>UTTypeDescription</key><string>ID Card Design</string>
      <key>UTTypeConformsTo</key><array><string>public.json</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>idcard</string></array></dict>
    </dict>
  </array>
</dict>
</plist>
EOF
# Remove the NSDocumentClass line: SwiftUI's DocumentGroup supplies its own document class.
sed -i '' '/NSDocumentClass/d' "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built: $(pwd)/$APP"
