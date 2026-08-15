# HTML Graphics Demos

A collection of impressive, self-contained graphics experiments. The main format is an individual HTML demo that can be opened directly in Chrome or Firefox, with no network connection or project-wide setup required.

The visual language draws from the demoscene, Amiga games, 16-bit consoles, CRTs, pixel art, procedural animation, and other joyful bits of graphics history. Each demo is its own small world: its code, assets, and optional vendored libraries live together in one folder.

## Running a demo

Open the demo folder, then drag its main HTML file—usually `index.html`—into Chrome or Firefox. The demo's local `AGENTS.md` and README, when present, document controls, browser requirements, and any optional authoring commands.

Finished demos should work from a `file://` URL. They should not depend on CDNs, remote assets, a package install, or a development server just to be viewed.

## Demos

- [NebulaForge](NebulaForge/) — a Swift and Metal particle simulation project.

More browser demos will be added as independent folders. For the conventions governing new demos, see [`AGENTS.md`](AGENTS.md).

## Contributing a demo

Create one folder per demo. Include an obvious HTML entry point, keep runtime dependencies and assets inside that folder, and add a local `AGENTS.md` with the demo's concept, controls, launch instructions, and verification checklist. Favor original or properly licensed art, audio, and code.
