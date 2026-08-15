# Upward Market

## Purpose

`Upward Market` is an original procedural pixel-art climb through a warm, impossibly tall night market built into a dense city canyon. The camera rises through stacked facades, bridges, stalls, elevators, pipes, gardens, steam, paper, birds, and small silhouettes. It uses the mood of animated city nightscapes only as broad inspiration; it contains no copied characters, buildings, signs, logos, shots, or shipped artwork.

## Launch

- Open [`index.html`](./index.html) directly with `file://` by dragging it into a current Chrome, Firefox, Safari, or Edge window.
- No server, package manager, build step, network connection, remote font, CDN, or runtime asset is required.
- The canvas is 320×180 internally and scales with nearest-neighbor pixels to the available viewport. Resize and orientation changes are safe.

## Controls and accessibility

- Move a mouse, stylus, or finger over the scene to steer the lantern and reveal brighter details, hidden glyph signs, and roof gardens.
- Click/tap or press Enter/Space to emit a warm window-network pulse. The focused canvas is keyboard operable.
- Arrow Up/Down adjust ascent speed. `R` resets the deterministic seed, timeline, camera, particles, speed, and pulses.
- The canvas has a descriptive accessible name and a visually hidden instructions paragraph. The page provides a visible fallback message if 2D canvas is unavailable.
- `prefers-reduced-motion: reduce` slows the climb and independent animation, uses fewer particles, and avoids rapid flashes.

## Render architecture

- All code is inline in `index.html`. The scene buffer is a 320×180 Canvas 2D surface; a same-size light/atmosphere buffer is composited with `screen` blending.
- A deterministic procedural 16×16 tile atlas is generated on startup for windows, vents, balconies, awnings, pipes, abstract glyph signs, plants, stalls, lanterns, and tiny silhouettes.
- Deterministic hash-based facade strips keep vertical rows, bridges, rooms, elevators, stalls, cables, and gardens authored without external images. The palette is a compact ink/plum/brick/rust ramp with lantern gold, paper cream, leaf teal, and festival coral accents.
- Separate parallax rates move distant towers, facades, rooms, and foreground pipes at different vertical speeds, with subtle horizontal counter-drift. Elevators, lanterns, fans, steam, pedestrians, laundry, paper, insects, and silhouettes animate in bounded/recycled pools.
- A 50-second authored progression loops through busy market (0–6s), homes (6–15s), dark maintenance (15–24s), hidden gardens (24–34s), dawn/paper/birds (34–43s), roofline/canyon reveal (43–48s), and a foreground elevator occlusion wipe (48–50s).
- Final scanlines, deterministic CRT grain, vignette, low-resolution compositing, and nearest-neighbor display scaling make the indexed-looking pixels intentional.

## Assets and dependencies

There are no image, audio, font, library, or network dependencies. Every visual asset is generated from small atlas drawing routines at startup. Do not add a shared vendor directory or a remote import to this demo.

## Verification checklist

Before handing off changes:

1. Open `index.html` directly from disk in Chrome or Firefox and verify the initial market frame is populated.
2. Move/click/touch the canvas, focus it, use Enter/Space, Arrow Up/Down, and `R`; verify the lantern reveal, pulse, speed, and deterministic reset.
3. Resize and rotate the viewport, wait through the full 50-second loop, and check that the elevator wipe returns to the opening scene.
4. Enable reduced motion and verify slower drift/fewer particles; hide and restore the tab to verify animation resumes without a time jump.
5. Inspect the browser console for errors or warnings and the network panel for unexpected requests (there should be none).
6. Static checks should confirm no `fetch`, `import`, CDN, remote URL, or server-only dependency appears in `index.html`.
