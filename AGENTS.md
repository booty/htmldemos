# Repository guide

## Purpose

This repository is a collection of impressive, self-contained graphics demos. The primary format is a browser demo that can be opened offline by dragging its main HTML file into Chrome or Firefox.

The creative north star is the demoscene: Amiga-era visuals, 16-bit games, CRTs, raster effects, procedural textures, chunky pixels, unusual palettes, particles, sprites, and sound. Use those references as inspiration for original work; do not copy proprietary game assets, logos, music, or code without permission.

## What Kind of Demos We're Making

Use ./INSPIRATION.md for examples and inspiration

## Best Practices / Goals

- Performance target is an M1 MAX laptop
- Don't use the "Superpowers" plugin/skill unless explicitly asked to do so, especially on small tasks.
- Impress me with graphics
- For now, it's okay to work directly on git branch `main` since this is a solo toy/learning repo

## Repository Shape

- Each demo lives in its own top-level folder.
- Each demo folder is a nearly independent project with its own entry point, assets, dependencies, instructions, and local `AGENTS.md`.
- A demo's `AGENTS.md` extends this file and may add more specific rules for that demo. Read it before changing anything inside the demo.
- Keep the repository root small. Root-level files should generally be shared documentation or configuration, not demo-specific code, assets, dependencies, or build output.
- Do not create a shared `vendor/`, `assets/`, or runtime library directory for all demos. If a library is needed, vendor it inside the demo that uses it.
- Existing non-HTML projects keep their own toolchain and local conventions until they are intentionally migrated. The browser-specific rules below apply to HTML graphics demos.

## HTML Demo Contract

Every new browser demo should meet these expectations:

- Make the main entry point obvious, preferably `index.html`.
- Keep the experience self-contained and runnable from a `file://` URL. Opening the HTML file directly should be the primary way to run it.
- Prefer inline HTML, CSS, and JavaScript when practical. Relative local files are fine when they make the demo clearer or more maintainable.
- Do not require a network connection at runtime. Do not load CDNs, remote fonts, analytics, remote images, remote shaders, or other external services.
- Avoid APIs that only work when served over HTTP, such as runtime `fetch()` of local files or server-dependent module imports. If a feature needs a local server, provide a direct-file fallback or reconsider the implementation.
- Keep all vendored libraries and third-party assets inside the demo folder, document their licenses, and include only what the demo actually needs.
- Use relative paths so a demo remains portable when its folder is copied elsewhere.
- Do not rely on a package manager, transpiler, bundler, or development server being installed to view the finished demo. Build tooling may exist for authoring, but the checked-in result must be directly runnable.
- Use feature detection and graceful fallbacks for optional browser capabilities. A demo should fail visibly and informatively rather than silently rendering a blank page.
- Make the canvas or scene adapt to the viewport and device pixel ratio without creating an avoidable performance problem. Cap expensive resolution or particle counts where appropriate.
- Give users a short visible hint for interaction, such as mouse, touch, keyboard, or click-to-start audio. Support reset or reload behavior when the experience has meaningful state.
- Keep the browser console free of avoidable errors and warnings.

## Visual and interaction direction

Aim for a strong visual premise rather than a generic technology showcase. Good demos may use limited palettes, pixel-art composition, sprite sheets, fake scanlines, palette cycling, copper bars, parallax, ray marching, metaballs, vector tunnels, fluid motion, procedural landscapes, or audio-reactive effects.

Prioritize:

- A compelling first frame and a clear sense of motion.
- Deliberate palette, typography, composition, and layering.
- Responsive interaction that changes the visual result rather than serving as decoration.
- Small details that reward watching: transitions, particles, animation cycles, hidden modes, and sound design when appropriate.
- Original assets or assets with clear permission and attribution.

Do not sacrifice readability or stability for visual noise. A demo may be intense, surreal, or deliberately retro, but users should still understand how to start it and how to interact with it.

## Per-demo documentation

Each demo folder should contain a concise `AGENTS.md` describing:

- The demo's purpose and visual concept.
- The exact file to open and any optional development command.
- Controls and browser requirements.
- The local asset and dependency layout.
- Any build or generation step needed after editing source files.
- A short verification checklist.

If a demo has a README, keep it focused on the demo itself. Do not move repository-wide policy into individual demo folders.

## Workflow

Before editing a demo:

1. Read the root guidance and the demo's local `AGENTS.md`.
2. Identify the direct HTML entry point, local assets, and any vendored dependencies.
3. Preserve unrelated changes and avoid modifying another demo as part of a focused task.

After editing a browser demo:

1. Open the main HTML file directly from disk in Chrome or Firefox.
2. Exercise the documented controls, resize the window, and check the initial and reset states.
3. Inspect the console for errors, missing local resources, and unexpected network requests.
4. Check that paths still work when the whole demo folder is moved or copied.
5. If a build step is used, verify both the source workflow and the checked-in offline output.

Prefer simple, inspectable solutions. Add infrastructure only when it materially improves a demo, and keep that infrastructure local to the demo.

## Root files

Keep these files concise and intentional:

- `AGENTS.md` contains shared instructions for contributors and coding agents.
- `CLAUDE.md` imports `AGENTS.md` and does not duplicate its contents.
- `README.md` explains the project to human visitors and links to demos.

Do not add root-level framework configuration, dependency manifests, or shared build systems merely for convenience. A root-level tool is appropriate only when it serves the repository as a whole and does not make individual demos less portable.
