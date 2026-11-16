# hima. brand assets

The mark is a coral rounded square with a bold ink `h` and a yellow dot, echoing
the `hima.` wordmark. Colors are the Design.md 3.1 tokens: `#FF6389` coral,
`#2F124F` ink, `#FFE65A` yellow.

| File | Purpose |
|---|---|
| `icon.svg` | Master: the rounded-square mark on a transparent canvas. |
| `icon.png` | 1024px full-bleed coral render, used for the iOS app icons. |
| `icon_rounded.png` | 1024px render with transparent corners, used for the Android legacy launcher icon and the iOS launch image. |
| `icon_foreground.svg` | Android adaptive foreground: transparent, mark scaled into the 66/108 safe zone. |
| `icon_foreground.png` | 1024px render of the above. |

iOS and the Android adaptive icon get their corner radius from the platform
mask, so those renders are full-bleed coral. Apple also rejects icons with an
alpha channel, which is why the iOS icons are flattened rather than rounded.

## Regenerating

The platform icons are committed, so a normal build needs nothing. To change the
mark, edit the SVGs and re-render with ImageMagick:

```sh
cd app
magick -background "#FF6389" assets/brand/icon.svg -flatten -resize 1024x1024 -strip -depth 8 assets/brand/icon.png
magick -background none assets/brand/icon_foreground.svg -resize 1024x1024 -strip -depth 8 assets/brand/icon_foreground.png
magick -background none assets/brand/icon.svg -resize 1024x1024 -strip -depth 8 assets/brand/icon_rounded.png
```

Then resize into `android/app/src/main/res/mipmap-*/` (`ic_launcher.png` at 48,
72, 96, 144, 192 px; `ic_launcher_foreground.png` at 108, 162, 216, 324, 432 px)
and `ios/Runner/Assets.xcassets/` (`AppIcon.appiconset` from `icon.png` with
`-background "#FF6389" -alpha remove -alpha off`, `LaunchImage.imageset` from
`icon_rounded.png` at 120, 240, 360 px).

The splash mark is drawn as the vector drawables
`android/app/src/main/res/drawable/splash_logo.xml` (120dp) and
`drawable/splash_icon.xml` (288dp, artwork in the inner 2/3 for the Android 12+
circular mask). They repeat the same geometry as `icon.svg`; update them
together.
