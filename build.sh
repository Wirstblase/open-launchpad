#!/bin/bash
set -e

APP_NAME="OpenLaunchpad"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR=".build/release"

echo "==> Building release binary..."
swift build -c release

echo "==> Creating .app bundle..."

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>OpenLaunchpad</string>
    <key>CFBundleDisplayName</key>
    <string>OpenLaunchpad</string>
    <key>CFBundleIdentifier</key>
    <string>com.openlaunchpad.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>OpenLaunchpad</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Generate a simple app icon (3x3 grid motif, rendered via Swift)
echo "==> Generating app icon..."
cat > /tmp/genicon.swift << 'SWIFT'
import AppKit

let size = 1024.0
let margin = size * 0.09
let inner = size - margin * 2
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Light gray rounded rect background — rgb(222, 222, 222) with slight transparency
let bg = NSBezierPath(roundedRect: NSRect(x: margin, y: margin, width: inner, height: inner),
                      xRadius: inner * 0.225, yRadius: inner * 0.225)
NSColor(red: 222.0/255.0, green: 222.0/255.0, blue: 222.0/255.0, alpha: 0.82).setFill()
bg.fill()

// 3x3 grid of rounded squares, each with a random vibrant color
let dot = inner * 0.14
let gap = inner * 0.10
let startX = margin + (inner - (3 * dot + 2 * gap)) / 2
let startY = margin + (inner - (3 * dot + 2 * gap)) / 2
for row in 0..<3 {
    for col in 0..<3 {
        let x = startX + Double(col) * (dot + gap)
        let y = startY + Double(row) * (dot + gap)
        let r = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: dot, height: dot),
                             xRadius: dot / 2, yRadius: dot / 2)
        let hue = CGFloat.random(in: 0...1)
        let saturation = CGFloat.random(in: 0.5...0.9)
        let brightness = CGFloat.random(in: 0.7...1.0)
        NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0).setFill()
        r.fill()
    }
}

image.unlockFocus()

// Save as PNG
if let tiff = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: "AppIcon.png"))
    print("  PNG created")
}
SWIFT

swiftc -o /tmp/genicon /tmp/genicon.swift -framework AppKit 2>/dev/null
cd "$(dirname "$0")"
/tmp/genicon

# Convert PNG to ICNS
mkdir -p AppIcon.iconset
for s in 16 32 64 128 256 512; do
    s2=$((s * 2))
    sips -z $s $s AppIcon.png --out "AppIcon.iconset/icon_${s}x${s}.png" >/dev/null 2>&1
    sips -z $s2 $s2 AppIcon.png --out "AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null 2>&1
done
if iconutil -c icns AppIcon.iconset -o AppIcon.icns 2>&1; then
    echo "  ICNS created"
else
    echo "  WARNING: iconutil failed, using blank icon"
fi

# Copy into bundle
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
    rm -rf AppIcon.icns AppIcon.png AppIcon.iconset /tmp/genicon /tmp/genicon.swift
    # Refresh Finder icon cache
    touch "$APP_BUNDLE"
fi

# Ad-hoc code sign
echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Done: $APP_BUNDLE"
echo "Drag it to /Applications to install."
echo ""
echo "First run: if macOS blocks it, run:"
echo "  xattr -cr $APP_BUNDLE"
