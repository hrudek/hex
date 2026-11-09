# Typr branding

`typr-logo.svg` is the original outlined **typr.** wordmark on `#040000` and
is the source of truth. It has no external font dependency.

From the repository root, regenerate the shared SwiftUI vector and the
transparent 2048 × 2048 PNG icon layer with:

```sh
python3 ios/Branding/generate.py
python3 ios/Branding/generate.py --check
```

Rendering requires `rsvg-convert` (librsvg); `--check` uses only Python's standard
library. The generator centers the visible wordmark while preserving its source
proportions. The PNG has no baked-in background or rounded corners. Icon Composer
provides the solid `#040000` background and iOS mask. Its 0.5 layer scale maps the
2048-pixel artwork to the 1024-point composition; shadows and translucency are
disabled. The same white-on-dark artwork works in dark/tinted appearances.

`AppIcon.icon` remains a resource of the application target, with
`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`; no duplicate AppIcon asset catalog
is needed. `TyprWordmark.swift` is compiled by the app, keyboard and widget
extension. The app/setup/keyboard marks, UIKit keyboard key and Live Activity
all draw this path, adapting their foreground color to their existing surface
and state. The waveform remains a functional audio meter, not a brand logo.
The launch screen has no logo; its existing background color matches the icon.
