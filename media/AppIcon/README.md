# DialKit macOS icon

Original artwork by Josh Puckett, extracted from the inline SVG at
[joshpuckett.me/dialkit](https://joshpuckett.me/dialkit).
This is the shaded version of the slider mark used by
[DialKit](https://www.dialkit.dev).

- `DialKit-original.svg`: unmodified source artwork.
- `DialKit-macOS.svg`: original artwork framed for the Dock. The square viewBox (`6 -5 74 74`) centers the 60-unit tile at 81.1% of the canvas width, matching the scale of neighboring macOS icons. Only the root canvas and the outer cast shadow change; the original slider paths, gradients, and internal shading are preserved.
- `DialKit-macOS.png`: 1024 × 1024 transparent export. The tile is approximately 830 × 830 pixels with 97 pixels of padding on each side. A compact outer shadow replaces the website's long decorative shadow so it fits without clipping.
- `../../Sources/DialKitMacOSApp/Resources/AppIcon.icns`: macOS icon with 16, 32, 128, 256, and 512 point representations at 1× and 2×.

The PNG was exported directly from `DialKit-macOS.svg` using Chrome's SVG renderer at 1024 × 1024 with a transparent background. Do not fit the original 86 × 107 website canvas into the icon: its shadow padding shrinks the tile to 56% of the canvas and pushes it upward in the Dock. After updating the PNG, run `bash Scripts/generate-app-icon.sh` from the repository root to regenerate the ICNS file using macOS `sips` and `iconutil`.

`swift run dialkit-macos` loads the icon into the Dock at launch. Run
`bash Scripts/package-app.sh` to build `.build/package-app/Dialkit macOS.app`,
which also includes the Finder icon. This local app bundle is ad-hoc signed;
distribution signing and notarization are separate from packaging.
