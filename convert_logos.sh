#!/bin/bash
SVG="./Resources/macshield_icon.svg"

# Convert for AppIcon (Xcode)
rsvg-convert -w 16 -h 16 $SVG > "./MacShield/Resources/Assets.xcassets/AppIcon.appiconset/icon_16.png"
rsvg-convert -w 32 -h 32 $SVG > "./MacShield/Resources/Assets.xcassets/AppIcon.appiconset/icon_32.png"
rsvg-convert -w 64 -h 64 $SVG > "./MacShield/Resources/Assets.xcassets/AppIcon.appiconset/icon_64.png"
rsvg-convert -w 128 -h 128 $SVG > "./MacShield/Resources/Assets.xcassets/AppIcon.appiconset/icon_128.png"
rsvg-convert -w 256 -h 256 $SVG > "./MacShield/Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png"
rsvg-convert -w 512 -h 512 $SVG > "./MacShield/Resources/Assets.xcassets/AppIcon.appiconset/icon_512.png"
rsvg-convert -w 1024 -h 1024 $SVG > "./MacShield/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png"

# Convert for Chrome extensions
for d in "BrowserExtensions/chrome-extension/icons" "BrowserExtensions/Chrome"; do
    if [ -d "$d" ]; then
        rsvg-convert -w 16 -h 16 $SVG > "$d/icon16.png"
        rsvg-convert -w 48 -h 48 $SVG > "$d/icon48.png"
        rsvg-convert -w 128 -h 128 $SVG > "$d/icon128.png"
    fi
done

# Convert general icon locations
rsvg-convert -w 512 -h 512 $SVG > "./Resources/icon.png"
rsvg-convert -w 512 -h 512 $SVG > "./docs/icon.png"

echo "All PNG logos have been successfully converted from the SVG!"
