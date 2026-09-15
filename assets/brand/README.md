# ThaiTalk app icon

`app-icon.png` is the original generated production asset. The five Android launcher icons are resized copies.

Generated using the built-in `image_gen.imagegen` tool (not the CLI fallback) on 2026-09-15. The image was visually inspected for a clear Thai ก glyph, speech-bubble silhouette, warm palette, and absence of English text.

Regenerate platform sizes with `node assets/brand/resize-icons.mjs` from the project root. The script requires Node.js and ffmpeg, uses Lanczos resizing only.

## Exact generation prompt

```text
Use case: logo-brand
Asset type: ThaiTalk mobile app launcher icon, production raster asset
Primary request: Create one polished, minimal, friendly Thai language learning app icon.
Scene/backdrop: Square full-bleed solid warm terracotta-orange background, approximately #D86B48. No outer border or rounded square frame; the operating system will mask the icon.
Subject: A single warm-white speech bubble with very rounded corners and a short elegant tail, containing the exact Thai consonant ก in terracotta. The Thai glyph should be recognizable and beautifully drawn, centered within the bubble, thick enough to stay clear at small sizes. A tiny mint green sparkle above the upper-right of the speech bubble may add a gentle friendly accent.
Style/medium: Premium contemporary flat vector-like brand design rendered as a crisp high-resolution bitmap. Balanced organic geometry, generous spacing, sharp clean edges.
Composition/framing: Centered simple large mark occupying roughly 62 percent of the square; all meaningful parts comfortably within a central circular safe area. Strong distinctive silhouette.
Color palette: Warm terracotta orange #D86B48, ivory white #FFF9F0, restrained mint #AFE3C1 accent.
Text (verbatim): "ก" — only this one Thai letter, no English text.
Constraints: A single finished icon only. No mockup, no device, no extra icon variations, no watermark. No gradients, shadows, texture, glossy effect, elaborate ornament, flag, or scenery.
```
