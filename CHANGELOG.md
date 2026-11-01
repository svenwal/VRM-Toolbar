# Changelog

All notable changes to VRM Toolbar. Newest first.

## 0.2.0 - 2026-11-01

### Added
- Notification Center widgets: <b>Battery</b> (small, medium) with a state-of-charge ring and your other values, and <b>Values</b> (small, medium, large) mirroring your Displays list. See <a href="widgets.html">Widgets</a>.

### Changed
- The app is now built together with an embedded widget extension. Rebuild with <code>./scripts/bundle.sh</code>.

## 0.1.1 - 2026-10-30

### Added
- Setting “Always show Dock icon” (General). The Dock icon is now visible by default, even when no display targets the Dock. Turn it off for a pure menu bar app.

### Fixed
- Pasting (and copying, cutting, select all, undo) did not work in text fields such as the access token, because the app had no Edit menu.

## 0.1.0 - 2026-10-26

### Added
- Menu bar, Dock icon and floating window displays for any VRM value.
- Live streaming over the VRM MQTT broker, plus polling.
- 24-hour history chart with min, max and average on hover.
- Floating windows with four materials, three layouts, typefaces, accent colours and more.
- Access token and email/password sign-in, stored in the Keychain.
- Launch at login and a configurable refresh interval.
