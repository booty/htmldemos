# Nebula Forge Design Specification

## 1. Purpose

Nebula Forge is a native macOS graphics demo designed to showcase the GPU in an M1 Max MacBook Pro. It renders a three-dimensional, interactive fluid vortex filled with luminous particles. The experience prioritizes visual spectacle while using a stable fluid model and guarded controls so that a broad range of parameter combinations remains coherent and recoverable.

The application is a local, Mac-only demo. It does not require App Store distribution, networking, accounts, persistence, or paid tools.

## 2. Platform and Development Environment

- Target platform: macOS Sequoia on Apple silicon
- Application language: Swift
- GPU API and shader language: Metal and Metal Shading Language
- View integration: MetalKit using `MTKView`
- User interface: SwiftUI
- Development environment: Xcode
- Deployment target: macOS 15.0
- Tooling cost: free for local development and execution

Use Xcode 26 when the development Mac runs macOS Sequoia 15.6 or later. Use Xcode 16.4 on Sequoia 15.3 through 15.5. The implementation must avoid APIs that require macOS Tahoe.

## 3. Experience

The main view presents a deep-space scene containing a turbulent, glowing particle nebula. A simulated incompressible velocity field drives the particles into vortices, sheets, jets, and wakes. The visual treatment adds velocity-sensitive color, high-dynamic-range glow, motion trails, bloom, depth fog, and tone mapping.

Users can orbit the camera and inject forces directly with the pointer. Primary-button dragging with no modifier orbits the camera. Option-drag attracts nearby flow toward the pointer, Control-drag repels it, and Command-drag creates an orbital force around it. Scroll or pinch changes camera distance. A collapsible control panel allows live changes without pausing the simulation.

Four initial presets provide useful starting points:

- Solar Maelstrom
- Aurora
- Supernova
- Black Hole

The app starts in Solar Maelstrom and begins animating immediately.

## 4. Simulation Model

### 4.1 Fluid

The fluid is represented by a three-dimensional Eulerian grid stored in GPU textures. A stable-fluids-style solver performs these operations each simulation step:

1. Inject emitter velocity and interactive forces.
2. Advect the velocity field with semi-Lagrangian advection.
3. Apply viscosity and dissipation.
4. Calculate curl and apply vorticity confinement.
5. Calculate velocity divergence.
6. Solve pressure iteratively with ping-pong textures.
7. Subtract the pressure gradient to project the field toward incompressibility.

This is an artistic real-time solver, not a scientific reference solver. Its correctness criterion is stable, continuous, plausibly fluid motion across every exposed control range. Pressure projection, bounded values, and timestep safeguards must prevent routine parameter changes from causing runaway energy or non-finite state.

### 4.2 Particles

Particles are massless tracers held in GPU buffers. Each particle contains position, previous position, velocity, age, lifetime, and a compact random seed or color attribute. Particles sample the fluid velocity, apply configurable drag and external forces, advance in time, and respawn from the active emitter when their lifetime expires or they leave the simulation bounds.

GPU buffers are allocated once to a documented safe maximum. The particle-count control changes the active prefix rather than reallocating buffers during interaction.

### 4.3 Time Integration and Stability

The renderer clamps wall-clock frame deltas. Simulation speed is applied to the clamped value, and the result is divided into fixed or bounded substeps. A hard maximum on substeps prevents a stalled application from attempting to catch up indefinitely.

All user values pass through validation before reaching a shader. Parameters that can change the energy of the system are bounded and may be smoothed over multiple frames. The simulation periodically checks a small diagnostic region or reduction result for non-finite values. On detection, it clears and reseeds simulation state while retaining the selected controls.

## 5. Rendering

Particles render as camera-facing, soft sprites or short velocity-aligned streaks into a floating-point HDR target. Additive and alpha-weighted contributions create bright structures without making low-density regions opaque.

Post-processing runs entirely on the GPU:

1. Accumulate the previous frame into the current frame for motion trails, with configurable decay.
2. Extract pixels above a brightness threshold.
3. Apply a separable or multi-resolution bloom blur.
4. Composite bloom and depth fog with the particle image.
5. Tone-map and apply exposure into the display surface.

Particle color is derived from a selected palette and may mix particle age, speed, and depth. The background remains restrained so the fluid silhouette stays legible.

Simulation resolution and render resolution are independent. Window resizing recreates only size-dependent render targets; it does not discard the fluid or particle state.

## 6. Architecture

### 6.1 SwiftUI Application Shell

The application shell owns window configuration, the Metal view bridge, the control panel, preset selection, and the optional performance overlay. It does not perform per-particle or per-cell work.

### 6.2 Simulation Controller

`SimulationController` owns the editable parameter model, default values, validation rules, preset application, pause, single-step, reset, randomization, and adaptive-quality preferences. Each frame it produces an immutable validated parameter snapshot for the renderer.

### 6.3 Metal Renderer

`MetalRenderer` owns the Metal device, command queue, pipeline states, GPU resources, frame scheduling, camera state, and pass orchestration. It encodes simulation compute passes before rendering and post-processing passes in the same frame command sequence where practical.

The renderer is separated into focused units with narrow responsibilities:

- Fluid resources and compute passes
- Particle resources and compute pass
- Scene and particle renderer
- Post-processing pipeline
- Camera and pointer-force conversion
- Performance measurement and adaptive-quality policy

GPU simulation state remains resident in Metal resources. Normal frames do not read particle or fluid arrays back to the CPU.

### 6.4 Data Flow

For every displayed frame:

1. SwiftUI updates the editable parameter state in response to user input.
2. `SimulationController` validates the state and emits a snapshot.
3. `MetalRenderer` determines a safe timestep and substep count.
4. Compute passes advance the fluid and particles.
5. The scene pass renders particles into HDR targets.
6. Post-processing creates trails, bloom, fog, and the final tone-mapped image.
7. Performance measurements update the overlay and adaptive-quality controller.

## 7. Controls

### 7.1 Simulation

- Active particle count
- Emission rate
- Particle lifetime, size, and drag
- Fluid-grid resolution
- Simulation speed
- Viscosity
- Velocity dissipation
- Pressure iteration count
- Vorticity strength
- Gravity
- Central attraction
- Orbital force
- Turbulence scale and strength
- Emitter position, radius, direction, spread, and initial velocity

### 7.2 Appearance

- Palette
- Velocity-to-color mixing
- Exposure
- Bloom intensity and radius
- Trail persistence
- Depth fog
- Background intensity
- Camera orbit speed
- Field of view
- Automatic cinematic camera

### 7.3 Operation and Quality

- Pause and resume
- Single simulation step
- Reset simulation
- Randomize within validated ranges
- Preset selection
- Render scale
- Frame-rate target
- Adaptive-quality toggle
- Performance-overlay toggle

Controls use descriptive labels, tooltips, sensible units, and logarithmic response where the useful range spans orders of magnitude. Each exposed minimum and maximum must be exercised by automated or manual stress testing.

### 7.4 Initial Validated Ranges

The following ranges define the first implementation envelope. Calibration on the target M1 Max may narrow a range but must not widen it without repeating maximum-setting and randomized stress tests.

| Parameter | Initial range | Default |
| --- | ---: | ---: |
| Active particles | 50,000–2,000,000 | 500,000 |
| Emission rate | 1,000–500,000 particles/s | 100,000 particles/s |
| Particle lifetime | 0.5–20 s | 7 s |
| Particle drag | 0–8 s⁻¹ | 1.5 s⁻¹ |
| Fluid-grid axis | 48, 64, 80, 96, 128, or 160 cells | 96 cells |
| Simulation speed | 0–2.5× | 1× |
| Viscosity | 0–0.02 | 0.001 |
| Velocity dissipation | 0–4 s⁻¹ | 0.15 s⁻¹ |
| Pressure iterations | 8–80 | 32 |
| Vorticity strength | 0–12 | 4 |
| Gravity magnitude | 0–20 simulation units/s² | 0 |
| Attraction magnitude | 0–60 simulation units/s² | 16 |
| Orbital-force magnitude | 0–60 simulation units/s² | 20 |
| Turbulence scale | 0.2–8 cycles/volume | 2 |
| Turbulence strength | 0–40 simulation units/s² | 8 |
| Exposure | −4–4 EV | 0 EV |
| Bloom intensity | 0–3 | 1.1 |
| Trail persistence | 0–0.98 | 0.86 |
| Render scale | 0.5–1.0× | 1.0× |
| Target frame rate | 30, 60, or 120 FPS | 60 FPS |

Force-direction vectors, colors, emitter position, and camera controls use bounded normalized or scene-relative values. Presets may select any value inside these bounds but cannot bypass validation.

## 8. Performance and Adaptive Quality

The default target is a steady 60 frames per second on an M1 Max at native-looking Retina quality. Default fluid resolution and particle count will be selected from measurements on the target computer rather than assumed in the code. Higher manual settings are allowed for stress testing.

When adaptive quality is enabled, the controller uses a smoothed frame-time measurement and hysteresis. It first adjusts internal render scale, then active particle count, and only then fluid-grid resolution. Adjustments occur gradually and infrequently to avoid visible oscillation. User-selected settings remain the desired maxima and are restored gradually when performance recovers.

The performance overlay displays frames per second, frame time, active particle count, fluid-grid dimensions, render scale, and GPU pass timings when Metal counter sampling is available. Lack of counter-sampling support must not prevent the demo from running.

## 9. Error Handling and Recovery

- If no suitable Metal device exists, show an explanatory in-app error instead of an empty window.
- If a shader library or pipeline cannot be created, show the failing stage and underlying Metal error.
- Replace invalid persisted or programmatic parameters with documented defaults.
- Recover from non-finite simulation data by clearing and reseeding GPU state without changing controls.
- Recreate size-dependent textures after resize, display change, or render-scale change.
- Suspend expensive frame work while the application is not drawable, then resume with a clamped timestep.
- Treat unavailable optional profiling features as disabled capabilities, not fatal errors.

## 10. Verification

### 10.1 Automated Tests

- Parameter validation at, below, and above every public bound
- Preset validation and reproducibility
- Timestep clamping and substep selection
- Adaptive-quality hysteresis and restoration behavior
- Camera and pointer coordinate conversion
- Deterministic small-grid checks for bounded fluid output and reduced divergence
- Deterministic particle checks for respawning, lifetime, and simulation bounds

GPU tests may use small buffers and textures to keep their runtime short. Tests should confirm invariants and tolerances rather than require exact cross-GPU floating-point equality.

### 10.2 Manual and Performance Tests

- Shader validation enabled during development
- Metal frame capture for resource and synchronization inspection
- Minimum, default, maximum, and randomized parameter stress presets
- Rapid slider movement while rendering
- Repeated resize, Retina scale, full-screen, pause, resume, and background cycles
- An extended run that checks memory stability and recovery from transient slow frames
- M1 Max measurements at default quality and maximum stress settings

## 11. Initial Scope and Non-Goals

The first release includes one simulation environment, one emitter system, interactive local forces, four presets, the complete live control panel, the performance overlay, and the visual effects described above.

The following are explicitly outside the initial scope:

- Windows, Linux, iOS, or web support
- Scientific validation or export of fluid datasets
- General-purpose scene editing
- Multiple independent fluid volumes
- Audio-reactive input
- Video export or screen recording
- App Store packaging and distribution
- Networked or multiplayer interaction

These features can be considered later without changing the simulation and renderer boundaries defined here.

## 12. Completion Criteria

The first release is complete when:

- The app launches directly into a visually compelling animated preset.
- Every documented control updates the running demo and remains within a tested safe range.
- Pointer interaction visibly affects the flow in attract, repel, and orbit modes.
- The default preset sustains approximately 60 FPS on the target M1 Max during a representative full-screen run.
- Resizing, pausing, backgrounding, reset, and preset switching do not corrupt GPU state or crash the app.
- Deliberate stress settings degrade gracefully through adaptive quality or reduced frame rate without producing persistent non-finite simulation state.
- Automated tests pass and the manual Metal validation checklist has been completed.
