#!/usr/bin/env bash
#
# Renders a 🍅 emoji on a soft cream squircle and packs it into App/AppIcon.icns.
# Idempotent — run again to regenerate (e.g. after changing colours or emoji).
#
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

ICON_PNG="${WORK}/icon_1024.png"
ICONSET="${WORK}/AppIcon.iconset"
OUT="App/AppIcon.icns"

echo "==> render 1024x1024 PNG via AppKit"
swift - "${ICON_PNG}" <<'SWIFT'
import AppKit
import Foundation

let outPath = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

// rounded "squircle" background — cream so the tomato glyph still reads warm
let bg = NSRect(origin: .zero, size: size)
let path = NSBezierPath(roundedRect: bg, xRadius: 224, yRadius: 224)
NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.78, alpha: 1.0).setFill()
path.fill()

// centered emoji, large enough to fill most of the icon
let emoji = "🍅" as NSString
let font = NSFont.systemFont(ofSize: 760)
let attrs: [NSAttributedString.Key: Any] = [.font: font]
let textSize = emoji.size(withAttributes: attrs)
let rect = NSRect(
    x: (size.width  - textSize.width)  / 2,
    y: (size.height - textSize.height) / 2 - 60,   // optical lift; emoji sits above descender baseline
    width:  textSize.width,
    height: textSize.height
)
emoji.draw(in: rect, withAttributes: attrs)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep  = NSBitmapImageRep(data: tiff),
      let png  = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("png encode failed\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
SWIFT

echo "==> sips to all sizes"
mkdir -p "${ICONSET}"
for s in 16 32 64 128 256 512 1024; do
    sips -z "$s" "$s" "${ICON_PNG}" --out "${WORK}/icon_${s}.png" >/dev/null
done

cp "${WORK}/icon_16.png"   "${ICONSET}/icon_16x16.png"
cp "${WORK}/icon_32.png"   "${ICONSET}/icon_16x16@2x.png"
cp "${WORK}/icon_32.png"   "${ICONSET}/icon_32x32.png"
cp "${WORK}/icon_64.png"   "${ICONSET}/icon_32x32@2x.png"
cp "${WORK}/icon_128.png"  "${ICONSET}/icon_128x128.png"
cp "${WORK}/icon_256.png"  "${ICONSET}/icon_128x128@2x.png"
cp "${WORK}/icon_256.png"  "${ICONSET}/icon_256x256.png"
cp "${WORK}/icon_512.png"  "${ICONSET}/icon_256x256@2x.png"
cp "${WORK}/icon_512.png"  "${ICONSET}/icon_512x512.png"
cp "${WORK}/icon_1024.png" "${ICONSET}/icon_512x512@2x.png"

echo "==> iconutil"
iconutil -c icns "${ICONSET}" -o "${OUT}"

echo "==> ✓ ${OUT}"
