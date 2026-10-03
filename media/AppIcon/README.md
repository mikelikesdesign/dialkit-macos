# DialKit macOS icon

Original artwork by Josh Puckett, extracted from the inline SVG at
[joshpuckett.me/dialkit](https://joshpuckett.me/dialkit).
This is the shaded version of the slider mark used by
[DialKit](https://www.dialkit.dev).

- `DialKit-original.svg`: unmodified source artwork.
- `DialKit-macOS.svg`: byte-for-byte copy of the original SVG, including its original viewBox, paths, gradients, filters, and full shadow.
- `DialKit-macOS.png`: original SVG uniformly fitted into a 1024 × 1024 transparent square. The original 86:107 canvas is preserved without cropping or stretching, with transparent padding on the sides.
- `../../Sources/DialKitMacOSApp/Resources/AppIcon.icns`: macOS icon with 16, 32, 128, 256, and 512 point representations at 1× and 2×.

The PNG was exported using Chrome's SVG renderer in a 1024 × 1024 transparent HTML canvas with zero body margin and a 1024 × 1024 `img` using `object-fit: contain`. This preserves the original SVG filters and aspect ratio. After updating the PNG, run `bash Scripts/generate-app-icon.sh` from the repository root to regenerate the ICNS file using macOS `sips` and `iconutil`.

`swift run dialkit-macos` loads the icon into the Dock at launch. Run
`bash Scripts/package-app.sh` to build `.build/package-app/Dialkit macOS.app`,
which also includes the Finder icon. This local app bundle is ad-hoc signed;
distribution signing and notarization are separate from packaging.
