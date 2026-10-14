# C2 Tablet

Native iPadOS 15 diagnostic station for a self-built aircraft project. No simulator. Aircraft type remains undecided. Existing notes/projects are preserved in FieldConsole's original data directory.

## Direction

An instrument workbench with five persistent tabs: Station, Links, Mission, Tools, Journal. The memorable element is the live link strip: connection state always has words, never a color-only indicator. Real values stay absent until measured. Mission files are planning drafts, not validated flight commands.

Palette: slate #182C3B, ocean #21658C, signal amber #A45E00, day background #F2F4F6, paper #FFFFFF, night surface #1C2833. Native semantic foreground/secondary colors adapt to accessibility and night mode. System sans for navigation/body; system monospaced only for measured values and diagnostic output. Left-aligned content, 24 pt outer spacing, 16 pt panel spacing, 48 pt action targets. Adaptive columns collapse in portrait. No decorative motion, downloaded fonts, shadows, or background video.

Skill review: first design-system search returned a marketing-page pattern, rejected as unsuitable. Narrowed style search returned Data-Dense Dashboard; its operational hierarchy is useful, but small text and dense desktop targets are replaced with tablet touch sizing. Native SwiftUI stack guidance applies. This is a diagnostic instrument, so no hero, promotional copy, or arbitrary decorative charts.

## Implementation scope

- Local health and system reports; saved endpoint profiles; TCP, DNS, ping, HTTP, interface/route/socket checks.
- Receive-only MAVLink 1/2 UDP monitor with CRC checks, selected system/component, bounded capture, message counts, and freshness for each measurement. Signed messages are rejected until authentication is implemented.
- Native map and coordinate-based local waypoint drafts, GeoJSON export, route distance; camera HLS preview where supported by AVPlayer. No offline basemap promise.
- Persistent checklist, notes, existing Python projects and shortcuts, diagnostic history and share/export.
- Foreground keep-awake control, brightness, day/night appearance, device name, recovery access. No replacement kernel or blanket service disabling.

Build and validate on the actual Air 2. Protocol fixtures are unit tests, not an installed simulator. No aircraft command transmitter is included in this diagnostic release.
