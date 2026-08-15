# Inspirations for HTML Graphics Demos

This is a field guide for making browser graphics that feel like productions rather than technology samples. It is distilled from browser demos, shader experiments, sizecoding competitions, and small web games. Use it to generate original premises, not to reproduce a particular production.

The working recipe is:

> **Visual contract + motion system + interaction + constraint = a demo worth opening twice.**

For a new demo, be able to answer four questions before writing much code:

1. What is the one-sentence image or sensation?
2. What is moving, and what makes the movement feel alive?
3. What can the viewer do that changes the image?
4. What deliberate limitation gives the piece character?

## A quick tour of the scene

“Browser demo” is a platform label, not a single style. The same ecosystem contains tiny intros, full audiovisual productions, single-shader studies, procedural illustrations, and playable games.

### Where to look

- [Pouët JavaScript productions](https://www.pouet.net/prodlist.php?platform%5B%5D=JavaScript) is the closest starting point for demoscene releases. Browse by `demo`, `intro`, `1k`, `4k`, and smaller categories, then follow online versions and party placements.
- [704.2 on Pouët](https://www.pouet.net/prod.php?which=62822) is a useful sizecoding case study: one idea exists as a JS1k entry, a standalone WebGL version, and a ShaderToy version, with reflections and fake soft shadows added as the budget changes.
- [Demozoo's Browser platform](https://demozoo.org/platforms/12/) is a clean index of browser productions, groups, dates, screenshots, and release metadata.
- [SESSIONS 2025 on Demozoo](https://demozoo.org/parties/5317/) is a reminder that browser work is shown in many forms: Browser 512b/8K/16K/32K intros alongside Code Graphics, Realtime Graphics, and Shader Jam categories.
- [Shadertoy](https://www.shadertoy.com/) is the deep end for full-screen procedural imagery. Mine it for signed-distance fields, raymarching, feedback, noise, camera tricks, and unusual ways of turning a few equations into a scene.
- [JS1k](https://js1k.com/) is the historical JavaScript code-golf archive. The [2014 Dragons demos](https://js1k.com/2014-dragons/demos) are particularly useful because their tiny entries cover raycasters, fractals, particles, games, music, simulations, and non-WebGL 3D.
- [DemoJS](https://demojs.org/) is a historical web-focused demoparty archive. Use it as a source of names, formats, and older browser-era ideas.
- [js13kGames](https://js13kgames.com/) is adjacent rather than purely demoscene: a compact browser-game competition with strong lessons in procedural assets, tiny engines, and playable presentation.

### A practical browsing order

1. Start at Pouët to absorb the language of productions: intros, releases, party results, byte budgets, credits, and “online version” links.
2. Move to Demozoo for newer browser releases and party categories.
3. Spend time in Shadertoy when the goal is pure visual synthesis rather than a complete show.
4. Use JS1k and js13kGames to learn how to make a small rule set feel like a whole world.
5. Return to the repository and turn one observed technique into an original premise with local assets and no network dependency.

## What makes the references stick

### 1. One strong visual contract

The best small demos can be described in one breath: “a tunnel made of glowing glyphs,” “a landscape that folds like fabric,” “a tiny game rendered as a broken television,” or “a procedural creature that breathes fire.” The code may contain many techniques, but the viewer experiences one coherent promise.

For a new demo, write the sentence before the implementation. Reject effects that do not strengthen it.

### 2. Constraints become art direction

Sizecoding makes limitations visible: fewer colors, fewer shapes, one shader, one loop, one primitive, or one clever approximation. The same mindset works without literally counting bytes.

Useful self-imposed budgets:

- 3–5 colors and one accent color.
- One canvas and one main simulation buffer.
- One mathematical primitive repeated obsessively.
- One 30–60 second audiovisual loop.
- Five interaction verbs or fewer.
- A 320×180 internal render scaled cleanly to the window.
- A single shader plus a deliberately simple UI layer.
- A “no texture files” or “all assets generated at runtime” rule.

The point is not austerity for its own sake. A constraint makes the visual language legible and gives future agents a concrete finish line.

### 3. Cheap signals create expensive-looking depth

Many memorable effects are stacks of small illusions rather than physically correct simulations:

- A low-resolution render, nearest-neighbor upscale, scanlines, and a vignette imply a machine.
- A height field, fog ramp, horizon line, and two scrolling texture bands imply a 3D world.
- A signed-distance shape, soft normal, fake shadow, and reflective floor imply a raymarched object.
- A particle trail, additive glow, palette cycling, and one camera shake imply energy.
- A few parallax layers, sprite silhouettes, and a narrow palette imply a complete game scene.

Choose a stack with a clear order. The first layer establishes the form; later layers should amplify it rather than compete with it.

### 4. Interaction should perturb the whole field

The strongest interaction is often not a button attached to a panel. It changes the underlying system:

- The pointer becomes gravity, wind, heat, or a flashlight.
- A drag bends a tunnel or paints a force field.
- A key changes the palette, camera, simulation rule, or rhythm.
- Holding a button charges a burst, then releases it into the scene.
- The viewer's movement reveals a parallax layer or distorts a signal.

Keep the first interaction obvious and the deeper modes discoverable. A short on-screen hint is part of the composition, not an admission of failure.

### 5. A show has time, even when it is interactive

Treat a demo as a tiny performance:

1. **Cold open:** show the visual premise immediately. Do not begin with a settings screen.
2. **Invitation:** give one clear hint: click, drag, press a key, or move the pointer.
3. **Escalation:** increase density, speed, palette, scale, or complexity after a few seconds.
4. **Reveal:** let the system transform into a second state or expose its trick.
5. **Loop:** settle into a stable idle state so the piece is pleasant to watch without input.

For a game-like demo, the same sequence becomes start, play, payoff, reset. Fast restart is a feature.

## A palette of techniques

These are ingredients, not prescriptions. Pick one primary technique and one or two supporting tricks.

| Technique | What it gives you | Browser-friendly version |
| --- | --- | --- |
| Palette cycling | Motion without geometry changes; strong retro identity | Draw to a small indexed-looking canvas or quantize colors in a shader, then rotate a compact palette over time |
| Copper bars / raster bands | Amiga-era scanline drama and readable composition | Use per-row color or offset bands; keep the bars as a framing device rather than the entire image |
| Signed-distance raymarching | Sculptural forms, glass, liquid, impossible rooms | Start with spheres, boxes, toruses, and smooth unions; add cheap normals, fog, and one fake light |
| Vector tunnel | Immediate depth and forward motion | Project rings, glyphs, sprites, or line segments with a perspective scale; vary radius and twist over time |
| Feedback trails | Smoke, electricity, motion memory, dream logic | Ping-pong two low-resolution canvases or use a shader buffer; decay, warp, and add the current frame |
| Flow fields | Organic motion for particles, ribbons, and crowds | Sample a deterministic noise or trigonometric field; integrate points with a capped step size |
| Particles / boids | Life, weather, sparks, swarms | Keep the population modest, use pooled objects, and let one attractor or repulsor create structure |
| Cellular automata | Emergent worlds from tiny local rules | Use a typed array, double buffer, and a small rule set; render cells as tiles, light, or terrain |
| Fractals / L-systems | Infinite detail and botanical or crystalline growth | Generate a bounded number of segments or iterations; animate the reveal instead of regenerating everything |
| Height-field fake 3D | Landscapes, oceans, roads, and flight | Layer scanlines or columns with perspective, fog, and a horizon; use a low internal resolution |
| Sprite / tile systems | Game memory and authored rhythm | Generate a tiny tile palette, mirror sprites, and let parallax do most of the depth work |
| Image deformation | CRTs, heat haze, portals, liquid glass | Render a scene to a texture or canvas, then offset UVs with a low-frequency field |
| Procedural typography | Titles that belong to the world | Draw glyphs from segments, pixels, or signed shapes; use text as geometry, not a generic overlay |
| Audio-reactive motion | A sense of performance and cause | Prefer generated tones or local audio; map low-frequency energy to large motion and high-frequency energy to detail |

### Retro tricks worth stealing conceptually

- **Chunkiness:** render smaller than the viewport, then scale up with an intentional filter.
- **Limited ramps:** design brightness steps by hand instead of using an unconstrained gradient.
- **Sprite cheating:** let silhouettes, shadows, and animation frames suggest more geometry than exists.
- **Parallax layers:** move a few flat layers at different speeds before reaching for full 3D.
- **Raster distortion:** bend rows, columns, or color bands to make the screen feel like hardware.
- **Palette as state:** change the palette to signal danger, a new scene, time passing, or user control.
- **Deliberate aliasing:** let pixels, stair steps, and quantization be part of the style instead of defects to smooth away.

## Interaction patterns for offline demos

Use browser input as a musical or physical control surface:

- **Attractor:** particles, stars, or ribbons follow the pointer.
- **Repulsor:** the cursor pushes away smoke, fish, snow, or a flock.
- **Brush:** dragging paints terrain, heat, color, or a path that the simulation remembers.
- **Lens:** the cursor reveals a high-resolution or alternate palette region.
- **Orbit:** pointer movement rotates a camera or a faux-3D object.
- **Charge and release:** holding the mouse or spacebar accumulates energy; release creates a burst.
- **Palette keyboard:** number keys or arrows cycle through authored palette states.
- **Mode switch:** one key changes the same underlying field from calm to hostile, frozen to liquid, or daylight to CRT night.
- **Shake:** device motion is optional; provide a click or key fallback for desktop users.
- **Idle choreography:** after inactivity, let the demo enter a gentle attract mode rather than stop.

Avoid UI that floats outside the visual language. A tiny monospace legend, a blinking prompt, or a status line embedded in the scene is usually enough.

## Browser-first constraints

The repository's demos must survive the `file://` test. Translate scene ideas into implementation choices that keep the folder portable.

### Runtime rules

- Prefer one obvious `index.html` with inline CSS and JavaScript, or a small set of relative local files.
- Do not require CDNs, remote fonts, analytics, remote textures, remote shaders, or network APIs.
- Do not rely on `fetch()` of local files, server-only module imports, or a development server for the finished experience.
- If a library earns its place, vendor it inside that demo's folder and record its license.
- Generate simple art, palettes, noise, sprites, and sound locally when that is cheaper than shipping assets.
- Use feature detection for optional WebGL, Web Audio, fullscreen, pointer lock, and high-DPI behavior. A readable fallback beats a blank canvas.

### Performance rules

- Separate CSS size from internal render size. A 320×180 or 640×360 simulation can look more intentional and run more consistently than an unconstrained full-resolution canvas.
- Cap device-pixel-ratio scaling and particle counts. Make quality a parameter, not an accident.
- Reuse arrays and objects in animation loops. Avoid allocating thousands of short-lived objects per frame.
- Pause or reduce work when the tab is hidden; restore state cleanly on resize.
- Prefer a stable 60 FPS illusion over a technically ambitious effect that stutters on integrated graphics.
- Include a low-quality mode when the effect is shader-heavy or simulation-heavy.

### Audio rules

- Start audio only after a click, key press, or another user gesture.
- A generated oscillator, noise burst, or tiny local sample is often enough; silence is a valid fallback.
- Make sound reinforce state changes. Do not add a music player just because a demo can play music.
- Provide mute and respect reduced-motion or user preference when practical.

### Authoring rules

- Keep source, generated assets, and any vendored library inside the demo folder.
- Test by dragging the main HTML file into Chrome and Firefox, not only through a local server.
- Resize the window, reload, wait through the idle state, exercise every documented control, and inspect the console.
- Keep a visible start hint and a fast reset path.

## Constraint recipes

Use these as starting points when an idea feels too broad:

### The 256-byte mindset

One primitive, one motion rule, one palette, one interaction. Example: a single signed-distance shape whose silhouette changes with the pointer and whose palette cycles every eight seconds.

### The 1K mindset

One screen, one loop, no imported assets, and a title made from the same geometry as the scene. Example: a procedural road with a horizon, fog, and one controllable vehicle.

### The 4K mindset

One primary shader or simulation, one secondary effect, and a short scene transition. Example: a raymarched cave that shifts from calm water to a collapsing crystal tunnel.

### The 16K mindset

Small authored content is allowed, but every asset must support the same world. Example: a four-room dungeon with generated tiles, a tiny soundtrack, palette-swapped enemies, and a one-button attack.

### The “Amiga cartridge” mindset

Use a fixed internal resolution, a hard palette, chunky sprites, parallax layers, and a loop that feels like a title screen or attract mode. The browser is the display hardware; the code is the cartridge.

### The “one weird rule” mindset

Take a familiar object and change one physical rule: shadows travel upward, water remembers clicks, text behaves like flocking birds, or the horizon rotates while gravity stays still.

## Original demo seeds

These are deliberately specific enough to start a folder, but open enough to become original work. Each seed gives a premise, a technique, an interaction, and a constraint.

1. **Copper Cathedral** — A wireframe nave scrolls toward the viewer while copper bars illuminate different architectural slices. Use a vector tunnel and per-row color bands. Dragging bends the nave. Limit the scene to four warm colors and one cold highlight.
2. **Modem Moon** — A moonlit landscape is reconstructed from noisy fax-like scanlines. Use a height-field fake 3D pass, palette cycling, and horizontal jitter. Move the pointer to tune the signal. Keep every asset procedural and let the scene fit in a 320×180 internal buffer.
3. **Coral ROM** — A coral reef grows from a single seed into a branching circuit board. Use an L-system or cellular automaton with a small tile palette. The pointer is heat: hover to accelerate growth, move away to let it fossilize. Allow only three growth rules and five colors.
4. **Rain on Cartridge Glass** — A tiny platform-game silhouette appears behind a layer of rain and water droplets. Use sprites, parallax, and a feedback layer. Drag a finger or mouse to wipe the glass. Keep the game world to one screen and make the weather the protagonist.
5. **The Soft Shadow Machine** — A single glossy object rotates in a black room while its fake shadow slowly becomes a second creature. Use a compact raymarcher with one light, one reflection approximation, and a shadow blob. The pointer controls the light. No texture files.
6. **Firefly Radio** — Fireflies form constellations that resemble a radio spectrum. Use a flow field, additive particles, and palette states. Click to drop a pulse that attracts nearby lights. The idle loop should create a new constellation every 20 seconds.
7. **Dungeon of Four Colors** — A one-screen dungeon uses only four colors, tile repetition, and a vibrating camera. Use a tilemap, sprite mirroring, and palette swaps. Arrow keys move; space changes which color is “solid.” No more than 32 tiles on screen.
8. **CRT Weather Report** — A fake late-night weather channel predicts impossible weather over a generated city. Use scanline distortion, bitmap typography, and procedural clouds. Number keys change the forecast and palette. The title, forecast, and image must share the same blocky glyph system.
9. **Melt the Logo** — A geometric emblem melts into a river of pixels and reforms when the pointer passes over it. Use a low-resolution buffer, a flow field, and a feedback trail. The pointer is heat. Limit the emblem to one shape and the melt to one deterministic field.
10. **Flock of Glyphs** — A swarm of letters forms words only when the viewer gets close. Use boids plus procedural typography. Mouse distance controls cohesion; pressing a key changes the phrase. Use a monochrome screen with one flashing accent.
11. **Orbital Junkyard** — A tiny space station is built from rotating silhouettes and drifting debris. Use instanced shapes, a faux perspective camera, and a palette ramp. Drag to alter gravity; click to launch a new piece of junk. Keep the camera orthographic and the station readable at thumbnail size.
12. **Tunnel for a Lost Save File** — The viewer flies through an endless tunnel made from corrupted save icons, sprites, and UI fragments. Use a vector tunnel, palette corruption, and chromatic offsets. Hold space to slow time. Every icon must be generated from a 4×4 or 8×8 grid.
13. **Liquid Glyph Synthesizer** — Three metaballs merge into letters, then dissolve into colored smoke. Use signed-distance fields or Canvas compositing. Keyboard notes change the glyph and pointer pressure changes viscosity. Limit the synth to one octave, one font-like shape system, and one low-resolution feedback buffer.
14. **Boss Fight at the Edge of the Screen** — A boss is mostly implied by a giant silhouette that never fits inside the viewport. Use parallax layers, screen shake, and procedural projectiles. Move with arrows and fire with click. Give the player one life and make the defeat animation the payoff.
15. **Pixel Aquarium for a Sleeping Computer** — Fish swim only when the pointer is still; movement wakes the screen into a noisy storm. Use boids, sprite silhouettes, and palette cycling. Click to feed the fish. Three fish species, three behaviors, one looping ambient scene.
16. **The Uphill Ocean** — Waves flow toward a horizon that bends upward as if gravity has rotated. Use a height field or layered sine displacement. Drag vertically to rotate the world. Use a strict 16-color palette and no conventional camera controls.
17. **Fractal Lantern** — A branching dragon-like curve unfolds inside a hand-held lantern, casting a different shadow on each wall. Use an L-system, a mask, and a few projected shapes. Move the lantern with the pointer. The curve must be rendered with a bounded iteration count and a deliberate reveal.
18. **Mod Tracker from a Parallel Universe** — Each key press adds one visual voice to a tiled raster composition. Use generated tones, geometric sprites, and palette changes driven by a step sequencer. The user can mute voices with number keys. Keep the pattern eight steps long.
19. **Silt Engine** — Clicks create sediment in a river; the river slowly reroutes around the deposits. Use a cellular automaton or particle-to-grid simulation. Hold the mouse to pour material. Render the world at low resolution, then upscale it with nearest-neighbor pixels.
20. **Afterimage Arcade** — A simple paddle game leaves behind a ghost of every previous frame, turning the arena into a history map. Use a feedback buffer and a minimal collision loop. The player controls the decay rate with the wheel. Two colors for the game, one color for memory.

## Composition checklist

Before calling a demo finished, ask:

- Can I describe its visual promise in one sentence?
- Is the first frame already interesting before input?
- Does the main motion have a source, rhythm, or rule?
- Does interaction affect the underlying field rather than merely toggle a UI class?
- Is there a deliberate palette and a deliberate internal resolution?
- Is there a transition, reveal, or payoff after the initial novelty?
- Does it remain pleasant in idle mode?
- Can a viewer reset it without refreshing the whole browser tab?
- Does it work when the HTML file is dragged into Chrome or Firefox?
- Are all runtime assets local and all dependencies per-demo?
- Is the console quiet, and is a slower machine given a sensible path?
- Is the inspiration transformed into an original premise rather than a renamed copy?

## Common failure modes

- **Effect soup:** ten unrelated tricks with no visual contract. Remove everything that does not support the sentence.
- **Demo as settings panel:** a beautiful renderer hidden behind controls. Show the image first; let controls deepen it.
- **Randomness as content:** noise changes every reload, but nothing has authored rhythm. Seed randomness and compose a progression.
- **Full-resolution stubbornness:** the effect is technically expensive but visually indistinct. Lower the internal resolution and make the chunkiness intentional.
- **Remote dependency drift:** the demo worked in a prototype because a CDN happened to be online. Vendor or inline what the finished piece needs.
- **No interaction grammar:** the page says “move mouse” but the viewer cannot tell what movement does. Make the first response large and immediate.
- **No ending:** the scene runs forever at one intensity. Add an escalation, state change, palette event, or resettable payoff.
- **Generic typography:** a system font floats above a carefully composed world. Make type part of the scene or keep it minimal.
- **Unreadable retro styling:** scanlines, noise, and bloom bury the image. Apply them after the composition works and keep a clean fallback.

## Source shelf

These are research destinations, not runtime dependencies. Links and live archives change; use them as places to browse for techniques, presentation ideas, and production context.

- [Pouët — JavaScript production list](https://www.pouet.net/prodlist.php?platform%5B%5D=JavaScript)
- [Pouët — 704.2, standalone 1K WebGL production](https://www.pouet.net/prod.php?which=62822)
- [Demozoo — Browser platform](https://demozoo.org/platforms/12/)
- [Demozoo — SESSIONS 2025 party results](https://demozoo.org/parties/5317/)
- [Shadertoy](https://www.shadertoy.com/)
- [JS1k — competition archive](https://js1k.com/)
- [JS1k — 2014 Dragons demos](https://js1k.com/2014-dragons/demos)
- [DemoJS](https://demojs.org/)
- [js13kGames](https://js13kgames.com/)

The goal is not to make a browser reproduce the past. The goal is to bring forward the scene's best habits: a clear premise, obsessive craft, joyful constraints, visible technique, and a tiny world that feels larger than its code.
