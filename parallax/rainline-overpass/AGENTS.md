# Rainline Overpass

## Purpose

`Rainline Overpass` is an original procedural pixel-art city vignette: a midnight courier waits under a rain-lashed megacity while an impossible elevated interchange gradually wakes above them. It is a 42-second, looping browser graphics demo with a limited teal / amber / coral night palette. The architectural mood is intentionally broad and original; it does not use recognizable game, film, building, vehicle, character, sign, logo, shot, or palette assets.

## Launch and controls

- Open `index.html` directly from disk (`file:///.../parallax/rainline-overpass/index.html`) in a current Chrome, Firefox, Safari, or Edge. No server is needed.
- Move the pointer over the canvas to bend the rain and shift the camera wind.
- Hold the pointer button or Space to accelerate the near parallax layers, flatten the rain, lengthen streaks, and lower the camera.
- Press `R` to reset the deterministic seed and 42-second timeline.
- The canvas is focusable, labelled as an image, and has a screen-reader-only control description. The visible in-world legend returns on focus or input.
- `prefers-reduced-motion: reduce` slows the loop, reduces rain, removes lightning flashes and camera shake, and keeps the interchange reveal calm.

## Rendering architecture

- The logical render buffer is always 384×216 and is scaled with nearest-neighbor CSS pixelation; resizing the window changes only the display size.
- The scene is drawn back-to-front: dithered storm sky, distant towers, cycling mid-city windows, structural columns and looping ramps, elevated train and traffic, foreground guardrail/cables/puddles/courier, rain, lightning, scanlines, and the hint.
- Reusable offscreen canvases cache the sky texture and static distant, city, and interchange geometry. Per-frame work is limited to dynamic windows, vehicles, rain, reflections, timeline lighting, and raster effects.
- Parallax constants are intentionally ordered at approximately `0.03 / 0.08 / 0.18 / 0.42 / 0.8 / 1.35` for sky, distant skyline, city, overpass, traffic, and foreground.
- All procedural arrays are seeded from a fixed integer and preallocated with bounded counts. No runtime assets, imports, libraries, fonts, fetches, or network requests are used.

## Timeline

The authored loop is 42 seconds: a strong storm opening (0–4s), windows waking (4–11s), an elevated train pass (11–18s), a warning-light and rain escalation (18–27s), a reduced-motion-safe lightning reveal of unfinished colossal ramps (27–33s), a power dip (33–39s), and a cascading power return into a clean loop (39–42s).

## Build and verification

There is no build step or dependency installation. The checked-in `index.html` is the runnable artifact. Verification should include:

1. Open `index.html` directly from disk in Chrome or Firefox; confirm the first frame is visible and the 42-second loop advances.
2. Move, press-and-hold, release, and resize the window; confirm wind, speed, camera, nearest-neighbor scaling, and reset behavior.
3. Press `R`, toggle reduced motion in the browser/OS, and hide/show the tab; confirm deterministic reset, calmer rendering, and pause/resume timing.
4. Inspect the browser console for errors or missing resources and verify no network requests are required.
5. Run a static syntax extraction/check on the inline script and search for forbidden `fetch`, module imports, CDN/remote URLs, and external asset references.
