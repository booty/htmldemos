# NebulaForge demo guide

## Purpose

NebulaForge is the repository's existing native macOS demo: a SwiftUI and Metal particle/fluid simulation. It is independent from the offline HTML demo contract in the repository root.

## Project layout

- `Package.swift` defines the Swift package, executable, library, and test targets.
- `Sources/NebulaForgeApp/` contains the SwiftUI application, Metal view, renderer, and shaders.
- `Sources/NebulaForgeCore/` contains platform-independent simulation and quality-control logic.
- `Tests/` contains core and renderer tests.

## Development

Use Swift 6.2 on macOS 15 or newer. From this directory:

- Run tests with `swift test`.
- Run the app with `swift run NebulaForge`.

Keep shader resources in `Sources/NebulaForgeApp/Shaders/` so SwiftPM continues to package them with the executable. Prefer keeping reusable simulation logic in `NebulaForgeCore` and platform-specific rendering code in `NebulaForgeApp`.

## Verification

After changes, run the relevant tests and, for renderer or shader work, launch the app and exercise the visible controls. Check that the simulation starts, pointer interaction works, presets remain usable, and there are no avoidable runtime or Metal validation errors.
