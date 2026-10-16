# Codex Usage · macOS 27

Design support: `awesome-design-md`, Apple direction, adapted for a native desktop companion.

## Direction

Use the system's actual Liquid Glass material with SwiftUI `glassEffect`, SF Pro,
SF Symbols, continuous corners, quiet blue and indigo accents, generous internal
spacing, and automatic light/dark appearance. No webview, simulated browser chrome,
wallpaper baked into the card, or additional font dependency.

## Card

Both persistent content layouts use the system Batteries medium-widget footprint:
344 × 164 points inside a 360 × 180 window (8-point outer shadow inset). This was
measured from the actual Notification Center Batteries window on the user's Mac.
Keep 24-point continuous corners, 20-point horizontal insets and centered content with at least 10-point vertical insets.
No title, card buttons, or running-task footer.

Quota only (default): two equal columns, 104-point outer ring bounds with inset 12-point strokes and centered 31-point numerals,
13-point labels “5小时” and “1周”, and 11-point medium-weight reset text. Place the two measures at the
centers of each half; balanced negative space is intentional, without extra filler.

Tokens plus quota: one horizontal composition, a 96-point-wide 24-hour total on the
left, a quiet vertical divider, and two compact 74-point outer ring bounds with 8-point strokes and centered 21-point numerals on the right. Keep
the same outer geometry when switching. Use 11-point labels and 10-point reset text; split cross-day dates and times across two lines instead of shrinking the text. Use one material surface.

The glass sits over an adaptive neutral tint to keep text readable on busy desktop
backgrounds. Background opacity alone is adjustable from 0–100% in 1% steps using a native menu slider, with quick presets. Keep foreground text, rings, and the window fully opaque; fade the glass, tint, border, and surface shadow together. Remove the redundant inner “剩余” label. Respect system Reduce Motion and Reduce Transparency. Use orange at
20% or less remaining. Unknown or expired quota is a dash, never a full ring.

## Interaction

Drag anywhere on the card. A native AppKit view handles the mouse down and
updates the frame using actual pointer coordinates; do not rely on NSHostingView's
background-drag flag or the nonactivating panel's system drag loop. Right-click
anywhere or use the menu bar to expose content layout, refresh, appearance,
refresh interval, opacity, independent ring colors via the native color panel, always-on-top, show/hide, and quit. Hide never quits the
monitor. Default window level is normal; it does not cover the active app. All
Spaces are supported. Store settings and a safe screen position using macOS
UserDefaults. Do not request Accessibility, screen recording, or API credentials.

## States and accessibility

Show explicit loading, stale quota, sign-in needed, and read-failure states in the
card or details panel. Preserve the last good statistics on temporary read errors.
Use VoiceOver labels with percent remaining and reset time,
and tabular numerals. Animate only data changes, respecting Reduce Motion.

Reset labels show the actual local calendar date/time, not elapsed-time countdowns.
Use “HH:mm 重置” today, “M月d日 HH:mm 重置” on another day, and include the year
when it differs. Interpret calendar-day boundaries in the Mac's current time zone.
An expired reset remains unknown until the next server snapshot.

## Acceptance

Verify actual light/dark rendering, 0/100/unknown/expired quota, long reset labels,
both content layouts, actual pointer drag and coordinate changes, save/restore,
context menus, hide/show, menu bar, sleep/wake refresh, and a
real local-log/account read. Deliver an Apple Silicon `.app`, not an EXE or Python
virtual environment. This is an independent desktop widget, not a WidgetKit gallery
extension (which requires an Xcode host/extension signing setup).
