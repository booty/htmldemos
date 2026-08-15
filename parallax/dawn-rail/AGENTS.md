# Dawn Rail

## Purpose

`Dawn Rail` is a self-contained pixel-art graphics demo about a small commuter train crossing a flooded industrial district at sunrise and entering a green, farmed future. It is procedural and original: the city, train details, water, turbines, birds, vegetation, condensation, and route display are drawn from compact arrays and Canvas 2D primitives.

## Launch

Open [`index.html`](./index.html) directly from disk (`file://`) in a current Chrome or Firefox release. No local server, package manager, build step, network connection, external font, image, or runtime dependency is required.

## Controls and accessibility

- Move the pointer horizontally to shift the seat/camera; the left and right arrow keys provide a keyboard equivalent.
- Drag vertically to change the shade crop and exposure; Up/Down change it in steps.
- Click or press Space to clear window condensation. It slowly reforms.
- `Q` toggles reflection/bird quality. A sustained slow frame rate automatically chooses the lower-cost quality.
- `P` cycles fixed night, sunrise, and green-day palettes without changing the sixty-second timeline.
- `R` resets the timeline, palette, camera, shade, and condensation.

The canvas is focusable and has an accessible description with the same controls. The scene pauses in a hidden tab, clamps frame deltas, caps its internal resolution at 480×270, and checks `prefers-reduced-motion`: close passes slow down, water distortion is reduced, the final train transition dissolves rather than flashing, and there is no exit flash.

## Rendering model

The internal render is a deliberate 480×270 logical canvas, upscaled with nearest-neighbor CSS. The authored skyline data is stored as compact segment descriptors (`x`, width, height, style) in `STRIPS`; `renderStrip` repeats these horizontal bands at layer speeds from roughly `.01` through `.24`, while the foreground scheduler includes passing objects up to `2.2`.

City geometry is first drawn into a transparent `skylineBuffer`. The water pass copies individual skyline-buffer scanline slices into a reflection buffer, offsets each row by quantized sine motion, and uses `source-atop` palette substitution to turn the copied pixels into water reflections. Water bands and a small sunrise reflection are then layered over that buffer. Factories, cranes, apartments, towers, terraces, turbines, transmission-like structures, levees, signals, poles, grass, fences, debris, and rail gear are procedural. Foreground objects use a separate unbounded `worldTime` clock and tiled wrap copies, so they move continuously across the 60-second palette loop instead of being culled at arbitrary lifetime boundaries.

The timeline is authored across 60 seconds: flooded pre-dawn district (0–8s), industrial poles/columns (8–18s), open water and first sun (18–28s), glyph-heavy tunnel (28–38s), gold exit (38–48s), terraces/rooftop farms/turbines/birds (48–56s), and an opposing-train wipe back to night (56–60s).

## Assets and dependencies

There are no local assets or third-party dependencies. All palettes, glyphs, scenery descriptors, procedural sprites, and animation schedules live inline in `index.html`. Do not add a shared vendor folder or a build system for this demo.

## Verification checklist

1. Open `index.html` directly from disk in Chrome or Firefox.
2. Confirm the first frame shows the train frame, route display, skyline, water, and condensation.
3. Exercise pointer movement, vertical drag, click/Space, arrows, `Q`, `P`, and `R`; resize the window and reload.
4. Check the console for errors, missing local resources, and network requests; there should be none.
5. Confirm the scene pauses when the tab is hidden and remains readable with reduced-motion preferences enabled.
6. For static checks, extract the inline script with a JavaScript parser when available and search for forbidden remote URLs, `fetch`, or module imports. No build or generated output is expected.
