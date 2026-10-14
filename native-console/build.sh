#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
mkdir -p build/root/var/jb/Applications/FieldConsole.app build/root/DEBIAN
APP=build/root/var/jb/Applications/FieldConsole.app
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 -O2 -c Runner.c -o build/Runner.o
xcrun --sdk iphoneos swiftc -parse-as-library -swift-version 5 -target arm64-apple-ios15.0 -sdk "$SDK" -O -import-objc-header Runner.h FieldConsole.swift MAVPacket.swift Telemetry.swift Station.swift C2Views.swift build/Runner.o -o "$APP/FieldConsole" -framework SwiftUI -framework UIKit -framework Network -framework MapKit -framework AVKit
cp Info.plist "$APP/Info.plist"
cp c2_checks.py "$APP/c2_checks.py"
swift icon.swift
cp Icon120.png "$APP/Icon@2x.png"
cp Icon180.png "$APP/Icon@3x.png"
cp Icon152.png "$APP/Icon~ipad@2x.png"
cp Icon167.png "$APP/Icon-83.5@2x~ipad.png"
ldid -Sentitlements.plist "$APP/FieldConsole"
cat > build/root/DEBIAN/control <<'EOF'
Package: local.homelab.fieldconsole
Name: C2 Tablet
Version: 2.0.0
Architecture: iphoneos-arm64
Description: Native C2 tablet diagnostics, telemetry monitoring and mission drafts.
Maintainer: Homelab
Section: Utilities
Depends: firmware (>= 15.0), python3, uikittools
EOF
cat > build/root/DEBIAN/postinst <<'EOF'
#!/var/jb/bin/sh
/var/jb/usr/bin/uicache -p /var/jb/Applications/FieldConsole.app
EOF
cat > build/root/DEBIAN/prerm <<'EOF'
#!/var/jb/bin/sh
/var/jb/usr/bin/uicache -u /var/jb/Applications/FieldConsole.app
EOF
chmod 755 build/root/DEBIAN/postinst build/root/DEBIAN/prerm
dpkg-deb --root-owner-group -Zgzip --build build/root build/fieldconsole_2.0.0_iphoneos-arm64.deb
shasum -a 256 build/fieldconsole_2.0.0_iphoneos-arm64.deb > build/SHA256SUMS
