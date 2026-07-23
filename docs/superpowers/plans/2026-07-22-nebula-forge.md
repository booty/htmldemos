# Nebula Forge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS Metal demo that runs an interactive three-dimensional fluid field, advects up to two million luminous tracer particles, and exposes stable live controls through SwiftUI.

**Architecture:** A Swift Package contains a testable `NebulaForgeCore` library and a SwiftUI executable. The CPU validates parameters, schedules safe timesteps, manages presets and adaptive quality, while Metal compute and render passes keep fluid, particle, HDR, trail, and bloom state resident on the GPU. Small focused renderer units share a `MetalContext` and are orchestrated by one `MetalRenderer`.

**Tech Stack:** Swift 6.2, SwiftUI, Metal, MetalKit, XCTest, Swift Package Manager, Xcode 26.2

## Global Constraints

- Target macOS Sequoia on Apple silicon with deployment target macOS 15.0.
- Use Swift, Metal Shading Language, MetalKit `MTKView`, and SwiftUI; add no third-party dependencies.
- Do not require macOS Tahoe APIs, App Store distribution, networking, accounts, or paid tools.
- Keep normal-frame simulation state on the GPU; do not read full fluid or particle arrays back to the CPU.
- Validate every public control against the exact ranges in the approved design specification.
- Default target is 60 FPS on the M1 Max; adaptive quality changes render scale, then particle count, then fluid-grid resolution.
- All shaders must bounds-check grid and particle indices.
- Run Swift commands with the selected Xcode at `/Applications/Xcode.app/Contents/Developer`.

## Planned File Structure

```text
Package.swift                                      SwiftPM products and targets
Sources/NebulaForgeCore/
  SimulationParameters.swift                      Editable values, validation, GPU snapshot
  Preset.swift                                     Four named parameter presets
  TimeStepper.swift                                Clamped delta and bounded substeps
  AdaptiveQualityController.swift                  Frame-time hysteresis and quality state
  PerformanceSnapshot.swift                       Displayable performance metrics
Sources/NebulaForgeApp/
  NebulaForgeApp.swift                             macOS app entry point and window setup
  AppModel.swift                                   Main-actor UI state and renderer commands
  ContentView.swift                                Metal canvas, overlays, error state
  ControlPanel.swift                               Grouped live controls
  PerformanceOverlay.swift                        Compact frame and GPU statistics
  MetalView.swift                                  SwiftUI-to-MTKView bridge and input routing
  Renderer/
    MetalContext.swift                             Device, queue, source library, pipeline helpers
    MetalRenderer.swift                            Frame orchestration and MTKViewDelegate
    FluidSolver.swift                              3D velocity/pressure/divergence resources and passes
    ParticleSystem.swift                           Particle buffers, spawn/update, diagnostics
    ParticleRenderer.swift                         HDR particle streak pass
    PostProcessor.swift                            Trails, bloom, fog, tone mapping
    Camera.swift                                   Orbit camera and screen-to-volume rays
    PointerInteractor.swift                        Gesture-to-force conversion
    GPUShared.swift                                Swift/MSL shared-layout mirror types
  Shaders/
    Shared.metal                                   Shared structs, sampling, bounds helpers
    Fluid.metal                                    Fluid compute kernels
    Particles.metal                                Spawn/update and particle shaders
    PostProcess.metal                              Trails, bloom, composite, tone map
Tests/NebulaForgeCoreTests/
  SimulationParametersTests.swift                 Range and preset validation
  TimeStepperTests.swift                           Delta clamp and substep behavior
  AdaptiveQualityControllerTests.swift             Hysteresis and restoration order
Tests/NebulaForgeAppTests/
  GPUSharedLayoutTests.swift                       Swift/MSL ABI sizes and alignments
  CameraTests.swift                                Ray and coordinate conversion
  MetalKernelTests.swift                           Small-texture GPU invariant tests
README.md                                          Setup, launch, controls, profiling checklist
```

---

### Task 1: Package, parameter model, and first passing tests

**Files:**
- Create: `Package.swift`
- Create: `Sources/NebulaForgeCore/SimulationParameters.swift`
- Create: `Tests/NebulaForgeCoreTests/SimulationParametersTests.swift`

**Interfaces:**
- Produces: `SimulationParameters.default`, `SimulationParameters.validated() -> SimulationParameters`, `FluidGridAxis`, `FrameRateTarget`

- [ ] **Step 1: Write the package manifest and failing validation tests**

```swift
// Package.swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NebulaForge",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NebulaForgeCore", targets: ["NebulaForgeCore"]),
        .executable(name: "NebulaForge", targets: ["NebulaForgeApp"]),
    ],
    targets: [
        .target(name: "NebulaForgeCore"),
        .executableTarget(
            name: "NebulaForgeApp",
            dependencies: ["NebulaForgeCore"],
            resources: [.copy("Shaders")]
        ),
        .testTarget(name: "NebulaForgeCoreTests", dependencies: ["NebulaForgeCore"]),
        .testTarget(name: "NebulaForgeAppTests", dependencies: ["NebulaForgeApp"]),
    ]
)
```

```swift
// Tests/NebulaForgeCoreTests/SimulationParametersTests.swift
import XCTest
@testable import NebulaForgeCore

final class SimulationParametersTests: XCTestCase {
    func testValidationClampsEveryScalarBoundary() {
        var value = SimulationParameters.default
        value.activeParticles = 3_000_000
        value.particleLifetime = -1
        value.pressureIterations = 200
        value.renderScale = 0.1
        value.trailPersistence = 2

        let result = value.validated()

        XCTAssertEqual(result.activeParticles, 2_000_000)
        XCTAssertEqual(result.particleLifetime, 0.5)
        XCTAssertEqual(result.pressureIterations, 80)
        XCTAssertEqual(result.renderScale, 0.5)
        XCTAssertEqual(result.trailPersistence, 0.98)
    }

    func testValidationReplacesNonFiniteValues() {
        var value = SimulationParameters.default
        value.viscosity = .nan
        value.exposure = .infinity
        let result = value.validated()
        XCTAssertEqual(result.viscosity, SimulationParameters.default.viscosity)
        XCTAssertEqual(result.exposure, SimulationParameters.default.exposure)
    }
}
```

- [ ] **Step 2: Run the tests and confirm the model is missing**

Run: `swift test --filter SimulationParametersTests`

Expected: FAIL with `no such module 'NebulaForgeCore'` or `cannot find 'SimulationParameters' in scope`.

- [ ] **Step 3: Implement the parameter model with all approved bounds**

```swift
// Sources/NebulaForgeCore/SimulationParameters.swift
import Foundation

public enum FluidGridAxis: Int, CaseIterable, Sendable { case n48 = 48, n64 = 64, n80 = 80, n96 = 96, n128 = 128, n160 = 160 }
public enum FrameRateTarget: Int, CaseIterable, Sendable { case fps30 = 30, fps60 = 60, fps120 = 120 }
public enum Palette: UInt32, CaseIterable, Sendable { case solar, aurora, supernova, void }

public struct SimulationParameters: Equatable, Sendable {
    public var activeParticles = 500_000
    public var emissionRate: Float = 100_000
    public var particleLifetime: Float = 7
    public var particleSize: Float = 1.8
    public var particleDrag: Float = 1.5
    public var fluidGridAxis = FluidGridAxis.n96
    public var simulationSpeed: Float = 1
    public var viscosity: Float = 0.001
    public var velocityDissipation: Float = 0.15
    public var pressureIterations = 32
    public var vorticityStrength: Float = 4
    public var gravityMagnitude: Float = 0
    public var attractionMagnitude: Float = 16
    public var orbitalForceMagnitude: Float = 20
    public var turbulenceScale: Float = 2
    public var turbulenceStrength: Float = 8
    public var emitterPosition = SIMD3<Float>(0, 0, 0)
    public var emitterRadius: Float = 0.12
    public var emitterDirection = SIMD3<Float>(0, 1, 0)
    public var emitterSpread: Float = 0.35
    public var emitterInitialVelocity: Float = 0.4
    public var palette = Palette.solar
    public var velocityColorMix: Float = 0.75
    public var exposure: Float = 0
    public var bloomIntensity: Float = 1.1
    public var bloomRadius: Float = 8
    public var trailPersistence: Float = 0.86
    public var depthFog: Float = 0.2
    public var backgroundIntensity: Float = 0.02
    public var cameraOrbitSpeed: Float = 0.12
    public var fieldOfViewDegrees: Float = 52
    public var automaticCinematicCamera = false
    public var renderScale: Float = 1
    public var targetFrameRate = FrameRateTarget.fps60
    public var adaptiveQuality = true

    public static let `default` = SimulationParameters()

    public func validated() -> Self {
        var result = self
        func finite(_ value: Float, fallback: Float, _ range: ClosedRange<Float>) -> Float {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        result.activeParticles = min(max(activeParticles, 50_000), 2_000_000)
        result.emissionRate = finite(emissionRate, fallback: 100_000, 1_000...500_000)
        result.particleLifetime = finite(particleLifetime, fallback: 7, 0.5...20)
        result.particleSize = finite(particleSize, fallback: 1.8, 0.25...8)
        result.particleDrag = finite(particleDrag, fallback: 1.5, 0...8)
        result.simulationSpeed = finite(simulationSpeed, fallback: 1, 0...2.5)
        result.viscosity = finite(viscosity, fallback: 0.001, 0...0.02)
        result.velocityDissipation = finite(velocityDissipation, fallback: 0.15, 0...4)
        result.pressureIterations = min(max(pressureIterations, 8), 80)
        result.vorticityStrength = finite(vorticityStrength, fallback: 4, 0...12)
        result.gravityMagnitude = finite(gravityMagnitude, fallback: 0, 0...20)
        result.attractionMagnitude = finite(attractionMagnitude, fallback: 16, 0...60)
        result.orbitalForceMagnitude = finite(orbitalForceMagnitude, fallback: 20, 0...60)
        result.turbulenceScale = finite(turbulenceScale, fallback: 2, 0.2...8)
        result.turbulenceStrength = finite(turbulenceStrength, fallback: 8, 0...40)
        result.emitterPosition = SIMD3(
            finite(emitterPosition.x, fallback: 0, -1...1),
            finite(emitterPosition.y, fallback: 0, -1...1),
            finite(emitterPosition.z, fallback: 0, -1...1)
        )
        result.emitterRadius = finite(emitterRadius, fallback: 0.12, 0.01...0.75)
        let directionLength = emitterDirection.length
        result.emitterDirection = directionLength.isFinite && directionLength > 0.0001 ? emitterDirection / directionLength : SIMD3(0, 1, 0)
        result.emitterSpread = finite(emitterSpread, fallback: 0.35, 0...1)
        result.emitterInitialVelocity = finite(emitterInitialVelocity, fallback: 0.4, 0...20)
        result.velocityColorMix = finite(velocityColorMix, fallback: 0.75, 0...1)
        result.exposure = finite(exposure, fallback: 0, -4...4)
        result.bloomIntensity = finite(bloomIntensity, fallback: 1.1, 0...3)
        result.bloomRadius = finite(bloomRadius, fallback: 8, 0...24)
        result.trailPersistence = finite(trailPersistence, fallback: 0.86, 0...0.98)
        result.depthFog = finite(depthFog, fallback: 0.2, 0...1)
        result.backgroundIntensity = finite(backgroundIntensity, fallback: 0.02, 0...0.4)
        result.cameraOrbitSpeed = finite(cameraOrbitSpeed, fallback: 0.12, 0...1)
        result.fieldOfViewDegrees = finite(fieldOfViewDegrees, fallback: 52, 25...90)
        result.renderScale = finite(renderScale, fallback: 1, 0.5...1)
        return result
    }
}

private extension SIMD3 where Scalar == Float {
    var length: Float { sqrt(x * x + y * y + z * z) }
}
```

- [ ] **Step 4: Run the focused and full suites**

Run: `swift test --filter SimulationParametersTests && swift test`

Expected: both commands PASS with 2 tests and no warnings from project sources.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/NebulaForgeCore Tests/NebulaForgeCoreTests
git commit -m "feat: add validated simulation parameters"
```

---

### Task 2: Presets, timestep scheduling, and adaptive-quality policy

**Files:**
- Create: `Sources/NebulaForgeCore/Preset.swift`
- Create: `Sources/NebulaForgeCore/TimeStepper.swift`
- Create: `Sources/NebulaForgeCore/AdaptiveQualityController.swift`
- Create: `Sources/NebulaForgeCore/PerformanceSnapshot.swift`
- Create: `Tests/NebulaForgeCoreTests/TimeStepperTests.swift`
- Create: `Tests/NebulaForgeCoreTests/AdaptiveQualityControllerTests.swift`
- Modify: `Tests/NebulaForgeCoreTests/SimulationParametersTests.swift`

**Interfaces:**
- Consumes: `SimulationParameters`, `FluidGridAxis`
- Produces: `Preset.parameters`, `TimeStepper.schedule(wallDelta:speed:) -> StepSchedule`, `AdaptiveQualityController.update(frameTime:desired:) -> QualityState`

- [ ] **Step 1: Write failing tests for presets, clamping, substeps, and quality order**

```swift
func testSlowFrameIsClampedAndSplit() {
    let schedule = TimeStepper().schedule(wallDelta: 1, speed: 1)
    XCTAssertEqual(schedule.stepCount, 4)
    XCTAssertEqual(schedule.stepDelta, 1.0 / 60.0, accuracy: 0.0001)
}

func testAdaptiveQualityLowersRenderScaleBeforeParticles() {
    var controller = AdaptiveQualityController()
    let desired = QualityState(renderScale: 1, activeParticles: 500_000, fluidGridAxis: .n96)
    var result = desired
    for _ in 0..<45 { result = controller.update(frameTime: 1.0 / 40.0, targetFPS: 60, desired: desired) }
    XCTAssertLessThan(result.renderScale, 1)
    XCTAssertEqual(result.activeParticles, 500_000)
    XCTAssertEqual(result.fluidGridAxis, .n96)
}

func testEveryPresetValidatesWithoutChangingItself() {
    for preset in Preset.allCases {
        XCTAssertEqual(preset.parameters, preset.parameters.validated())
    }
}
```

- [ ] **Step 2: Run the tests and confirm the new types are absent**

Run: `swift test --filter 'TimeStepperTests|AdaptiveQualityControllerTests|testEveryPreset'`

Expected: FAIL naming `TimeStepper`, `AdaptiveQualityController`, and `Preset`.

- [ ] **Step 3: Implement the deterministic CPU policies**

```swift
public struct StepSchedule: Equatable, Sendable { public let stepCount: Int; public let stepDelta: Float }

public struct TimeStepper: Sendable {
    public init() {}
    public func schedule(wallDelta: TimeInterval, speed: Float) -> StepSchedule {
        let safeWallDelta = min(max(wallDelta.isFinite ? wallDelta : 0, 0), 1.0 / 15.0)
        let total = safeWallDelta * Double(min(max(speed.isFinite ? speed : 1, 0), 2.5))
        guard total > 0 else { return StepSchedule(stepCount: 0, stepDelta: 0) }
        let count = min(4, max(1, Int(ceil(total / (1.0 / 60.0)))))
        return StepSchedule(stepCount: count, stepDelta: Float(total / Double(count)))
    }
}
```

```swift
public struct QualityState: Equatable, Sendable {
    public var renderScale: Float
    public var activeParticles: Int
    public var fluidGridAxis: FluidGridAxis
}

public struct AdaptiveQualityController: Sendable {
    private var smoothed = 1.0 / 60.0
    private var pressureFrames = 0
    private var recoveryFrames = 0
    private var current: QualityState?

    public init() {}

    public mutating func update(frameTime: Double, targetFPS: Int, desired: QualityState) -> QualityState {
        var quality = current ?? desired
        smoothed = smoothed * 0.9 + min(max(frameTime, 0), 0.25) * 0.1
        let budget = 1.0 / Double(targetFPS)
        pressureFrames = smoothed > budget * 1.12 ? pressureFrames + 1 : 0
        recoveryFrames = smoothed < budget * 0.82 ? recoveryFrames + 1 : 0
        if pressureFrames >= 30 {
            if quality.renderScale > 0.5 { quality.renderScale = max(0.5, quality.renderScale - 0.1) }
            else if quality.activeParticles > 50_000 { quality.activeParticles = max(50_000, Int(Double(quality.activeParticles) * 0.85)) }
            else { quality.fluidGridAxis = FluidGridAxis.allCases.last(where: { $0.rawValue < quality.fluidGridAxis.rawValue }) ?? .n48 }
            pressureFrames = 0
        } else if recoveryFrames >= 180 {
            if quality.fluidGridAxis.rawValue < desired.fluidGridAxis.rawValue { quality.fluidGridAxis = FluidGridAxis.allCases.first(where: { $0.rawValue > quality.fluidGridAxis.rawValue && $0.rawValue <= desired.fluidGridAxis.rawValue }) ?? desired.fluidGridAxis }
            else if quality.activeParticles < desired.activeParticles { quality.activeParticles = min(desired.activeParticles, Int(Double(quality.activeParticles) * 1.1)) }
            else { quality.renderScale = min(desired.renderScale, quality.renderScale + 0.05) }
            recoveryFrames = 0
        }
        current = quality
        return quality
    }
}
```

Implement the presets and deterministic randomizer with these contracts:

```swift
public enum Preset: String, CaseIterable, Identifiable, Sendable {
    case solarMaelstrom = "Solar Maelstrom", aurora = "Aurora", supernova = "Supernova", blackHole = "Black Hole"
    public var id: String { rawValue }

    public var parameters: SimulationParameters {
        var p = SimulationParameters.default
        switch self {
        case .solarMaelstrom: break
        case .aurora:
            p.activeParticles = 700_000; p.vorticityStrength = 7; p.gravityMagnitude = 2
            p.attractionMagnitude = 6; p.orbitalForceMagnitude = 10; p.trailPersistence = 0.91
            p.palette = .aurora
        case .supernova:
            p.activeParticles = 900_000; p.emissionRate = 350_000; p.particleLifetime = 3.5
            p.attractionMagnitude = 2; p.orbitalForceMagnitude = 3; p.turbulenceStrength = 22
            p.exposure = 0.8; p.bloomIntensity = 1.8
            p.palette = .supernova
        case .blackHole:
            p.activeParticles = 800_000; p.particleLifetime = 10; p.attractionMagnitude = 42
            p.orbitalForceMagnitude = 48; p.vorticityStrength = 8; p.trailPersistence = 0.93
            p.palette = .void
        }
        return p.validated()
    }

    public static func randomized(seed: UInt64) -> SimulationParameters {
        var rng = SplitMix64(state: seed)
        func sample(_ range: ClosedRange<Float>) -> Float {
            range.lowerBound + Float(rng.next() & 0x00ff_ffff) / Float(0x00ff_ffff) * (range.upperBound - range.lowerBound)
        }
        var p = SimulationParameters.default
        p.vorticityStrength = sample(1...12); p.attractionMagnitude = sample(0...60)
        p.orbitalForceMagnitude = sample(0...60); p.turbulenceScale = sample(0.2...8)
        p.turbulenceStrength = sample(0...40); p.exposure = sample(-1.5...1.5)
        p.bloomIntensity = sample(0.4...2.5); p.trailPersistence = sample(0.4...0.96)
        return p.validated()
    }
}

private struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

public struct PerformanceSnapshot: Equatable, Sendable {
    public var fps: Double
    public var frameMilliseconds: Double
    public var activeParticles: Int
    public var fluidGridAxis: Int
    public var renderScale: Double
    public var gpuPassMilliseconds: [String: Double]?
}
```

- [ ] **Step 4: Run all core tests**

Run: `swift test --filter NebulaForgeCoreTests`

Expected: PASS, including the four-preset validation loop and policy ordering tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NebulaForgeCore Tests/NebulaForgeCoreTests
git commit -m "feat: add presets and frame policies"
```

---

### Task 3: SwiftUI shell and Metal bootstrap

**Files:**
- Create: `Sources/NebulaForgeApp/NebulaForgeApp.swift`
- Create: `Sources/NebulaForgeApp/AppModel.swift`
- Create: `Sources/NebulaForgeApp/ContentView.swift`
- Create: `Sources/NebulaForgeApp/MetalView.swift`
- Create: `Sources/NebulaForgeApp/Renderer/MetalContext.swift`
- Create: `Sources/NebulaForgeApp/Renderer/MetalRenderer.swift`
- Create: `Sources/NebulaForgeApp/Shaders/Shared.metal`

**Interfaces:**
- Consumes: `SimulationParameters.default`, `TimeStepper`
- Produces: `MetalContext`, `MetalRenderer`, `RendererCommand`, `AppModel.rendererError`

- [ ] **Step 1: Add a shader source that paints a diagnostic gradient**

```metal
#include <metal_stdlib>
using namespace metal;

struct FullscreenOut { float4 position [[position]]; float2 uv; };

vertex FullscreenOut fullscreenVertex(uint id [[vertex_id]]) {
    const float2 p[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
    FullscreenOut out;
    out.position = float4(p[id], 0, 1);
    out.uv = p[id] * 0.5 + 0.5;
    return out;
}

fragment float4 diagnosticFragment(FullscreenOut in [[stage_in]]) {
    return float4(0.01 + 0.03 * in.uv.y, 0.005, 0.04 + 0.1 * in.uv.x, 1);
}
```

- [ ] **Step 2: Implement `MetalContext` source loading and explicit pipeline errors**

```swift
enum RendererError: LocalizedError, Equatable {
    case noMetalDevice
    case missingShaderResource(String)
    case shaderCompilation(String)
    case pipeline(String)
    var errorDescription: String? {
        switch self {
        case .noMetalDevice: "This Mac does not expose a Metal device."
        case .missingShaderResource(let name): "Missing Metal shader resource: \(name).metal"
        case .shaderCompilation(let message): "Metal shader compilation failed: \(message)"
        case .pipeline(let stage): "Metal pipeline creation failed for \(stage)."
        }
    }
}

final class MetalContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary

    init(bundle: Bundle = .module) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RendererError.noMetalDevice }
        guard let queue = device.makeCommandQueue() else { throw RendererError.pipeline("Metal command queue") }
        let shaderNames = ["Shared", "Fluid", "Particles", "PostProcess"]
        let sources = try shaderNames.compactMap { name -> String? in
            guard let url = bundle.url(forResource: name, withExtension: "metal", subdirectory: "Shaders") else {
                return name == "Shared" ? { throw RendererError.missingShaderResource(name) }() : nil
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
        do { library = try device.makeLibrary(source: sources.joined(separator: "\n"), options: nil) }
        catch { throw RendererError.shaderCompilation(error.localizedDescription) }
        self.device = device
        self.queue = queue
    }
}
```

- [ ] **Step 3: Create the app, view bridge, and renderer delegate**

Use `@main struct NebulaForgeApp: App`, a `@MainActor @Observable final class AppModel`, and `NSViewRepresentable` for `MetalView`. Configure `MTKView` with `colorPixelFormat = .bgra8Unorm_srgb`, `preferredFramesPerSecond = 60`, `enableSetNeedsDisplay = false`, `isPaused = false`, and a `MetalRenderer` delegate. `MetalRenderer.draw(in:)` must encode the diagnostic pipeline, present the drawable, and report initialization errors into `AppModel.rendererError` for `ContentView` to display.

```swift
@main
struct NebulaForgeApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup { ContentView(model: model).frame(minWidth: 960, minHeight: 640) }
            .defaultSize(width: 1440, height: 900)
    }
}
```

- [ ] **Step 4: Build and launch the diagnostic canvas**

Run: `swift build && swift run NebulaForge`

Expected: a resizable macOS window shows a dark violet gradient; resizing does not log Metal validation errors. Stop the app with Control-C.

- [ ] **Step 5: Commit**

```bash
git add Sources/NebulaForgeApp
git commit -m "feat: bootstrap Metal SwiftUI app"
```

---

### Task 4: Shared GPU ABI and three-dimensional fluid solver

**Files:**
- Create: `Sources/NebulaForgeApp/Renderer/GPUShared.swift`
- Create: `Sources/NebulaForgeApp/Renderer/FluidSolver.swift`
- Create: `Sources/NebulaForgeApp/Shaders/Fluid.metal`
- Create: `Tests/NebulaForgeAppTests/GPUSharedLayoutTests.swift`
- Create: `Tests/NebulaForgeAppTests/MetalKernelTests.swift`
- Modify: `Sources/NebulaForgeApp/Renderer/MetalRenderer.swift`
- Modify: `Sources/NebulaForgeApp/Shaders/Shared.metal`

**Interfaces:**
- Consumes: `MetalContext`, `SimulationParameters`, `StepSchedule`
- Produces: `GPUUniforms`, `InteractionForce`, `FluidSolver.encodeStep(commandBuffer:uniforms:force:)`, `FluidSolver.velocityTexture`

- [ ] **Step 1: Write ABI and small-grid failing tests**

```swift
func testGPUUniformLayoutIsSixteenByteAligned() {
    XCTAssertEqual(MemoryLayout<GPUUniforms>.stride % 16, 0)
    XCTAssertEqual(MemoryLayout<InteractionForce>.stride % 16, 0)
}

func testProjectionReducesDivergence() throws {
    let harness = try MetalTestHarness(gridAxis: 8)
    try harness.seedRadialVelocity()
    let before = try harness.maximumAbsoluteDivergence()
    try harness.project(iterations: 40)
    let after = try harness.maximumAbsoluteDivergence()
    XCTAssertLessThan(after, before * 0.35)
    XCTAssertTrue(after.isFinite)
}
```

- [ ] **Step 2: Run tests and confirm shared GPU types are missing**

Run: `swift test --filter 'GPUSharedLayoutTests|testProjectionReducesDivergence'`

Expected: FAIL naming `GPUUniforms`, `InteractionForce`, and `MetalTestHarness`.

- [ ] **Step 3: Define matching Swift and MSL structs**

```swift
struct GPUUniforms {
    var gridSize: SIMD4<UInt32>
    var deltaAndTime: SIMD4<Float>       // delta, elapsed, dissipation, viscosity
    var forces: SIMD4<Float>             // gravity, attraction, orbit, vorticity
    var turbulence: SIMD4<Float>         // scale, strength, emission rate, particle drag
    var emitterPositionRadius: SIMD4<Float>
    var emitterDirectionSpeed: SIMD4<Float>
    var particleCounts: SIMD4<UInt32>    // active, capacity, frame index, pressure iterations
}

struct InteractionForce {
    var positionRadius: SIMD4<Float>
    var directionStrength: SIMD4<Float>
    var modeAndPadding: SIMD4<UInt32>
}
```

Mirror the field order and vector widths exactly in `Shared.metal`. Add `static_assert` checks in MSL where supported and keep the Swift stride tests.

- [ ] **Step 4: Implement fluid textures and compute passes**

`FluidSolver` allocates private 3D `rgba16Float` velocity ping-pong textures and `r16Float` pressure/divergence textures for the selected `FluidGridAxis`. Implement these kernels in `Fluid.metal`, each with `if (any(gid >= uniforms.gridSize.xyz)) return;`:

```metal
kernel void injectForces(texture3d<half, access::read> input [[texture(0)]], texture3d<half, access::write> output [[texture(1)]], constant GPUUniforms& u [[buffer(0)]], constant InteractionForce& force [[buffer(1)]], uint3 gid [[thread_position_in_grid]]);
kernel void advectVelocity(texture3d<half, access::sample> input [[texture(0)]], texture3d<half, access::write> output [[texture(1)]], constant GPUUniforms& u [[buffer(0)]], uint3 gid [[thread_position_in_grid]]);
kernel void applyVorticity(texture3d<half, access::read> input [[texture(0)]], texture3d<half, access::write> output [[texture(1)]], constant GPUUniforms& u [[buffer(0)]], uint3 gid [[thread_position_in_grid]]);
kernel void computeDivergence(texture3d<half, access::read> velocity [[texture(0)]], texture3d<half, access::write> divergence [[texture(1)]], constant GPUUniforms& u [[buffer(0)]], uint3 gid [[thread_position_in_grid]]);
kernel void jacobiPressure(texture3d<half, access::read> pressureIn [[texture(0)]], texture3d<half, access::read> divergence [[texture(1)]], texture3d<half, access::write> pressureOut [[texture(2)]], constant GPUUniforms& u [[buffer(0)]], uint3 gid [[thread_position_in_grid]]);
kernel void subtractPressureGradient(texture3d<half, access::read> velocityIn [[texture(0)]], texture3d<half, access::read> pressure [[texture(1)]], texture3d<half, access::write> velocityOut [[texture(2)]], constant GPUUniforms& u [[buffer(0)]], uint3 gid [[thread_position_in_grid]]);
kernel void clearFluid(texture3d<half, access::write> velocity [[texture(0)]], texture3d<half, access::write> scalar [[texture(1)]], constant GPUUniforms& u [[buffer(0)]], uint3 gid [[thread_position_in_grid]]);
kernel void reduceFiniteDiagnostic(texture3d<half, access::read> velocity [[texture(0)]], device atomic_uint& flag [[buffer(0)]], constant GPUUniforms& u [[buffer(1)]], uint3 gid [[thread_position_in_grid]]);
```

Encode them in the design-specified order. Swap ping-pong textures after advection and each Jacobi iteration. Reallocate only when grid axis changes. The test harness must run the real divergence and pressure kernels on an 8³ grid and read back only its small test textures.

- [ ] **Step 5: Run unit tests and a validation launch**

Run: `swift test && MTL_DEBUG_LAYER=1 swift run NebulaForge`

Expected: tests PASS; the app continues showing the diagnostic background with no out-of-bounds or resource-usage validation messages.

- [ ] **Step 6: Commit**

```bash
git add Sources/NebulaForgeApp Tests/NebulaForgeAppTests
git commit -m "feat: add GPU fluid solver"
```

---

### Task 5: Particle simulation and deterministic respawn

**Files:**
- Create: `Sources/NebulaForgeApp/Renderer/ParticleSystem.swift`
- Create: `Sources/NebulaForgeApp/Shaders/Particles.metal`
- Modify: `Sources/NebulaForgeApp/Renderer/GPUShared.swift`
- Modify: `Sources/NebulaForgeApp/Renderer/MetalRenderer.swift`
- Modify: `Tests/NebulaForgeAppTests/MetalKernelTests.swift`

**Interfaces:**
- Consumes: `FluidSolver.velocityTexture`, `GPUUniforms`, maximum capacity 2,000,000
- Produces: `ParticleSystem.encodeUpdate(commandBuffer:velocityTexture:uniforms:)`, `ParticleSystem.currentBuffer`

- [ ] **Step 1: Add failing GPU tests for lifetime and bounds**

```swift
func testExpiredParticlesRespawnInsideEmitter() throws {
    let harness = try MetalTestHarness(gridAxis: 8, particleCount: 64)
    try harness.seedExpiredParticles()
    try harness.updateParticles(delta: 1.0 / 60.0)
    for particle in try harness.readParticles() {
        XCTAssertGreaterThanOrEqual(particle.age, 0)
        XCTAssertLessThan(particle.age, particle.lifetime)
        XCTAssertLessThanOrEqual(simd_length(particle.position), 1.0)
    }
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run: `swift test --filter testExpiredParticlesRespawnInsideEmitter`

Expected: FAIL because `GPUParticle` and particle kernels do not exist.

- [ ] **Step 3: Implement the particle buffer and update kernel**

```swift
struct GPUParticle {
    var positionAge: SIMD4<Float>
    var previousPositionLifetime: SIMD4<Float>
    var velocitySeed: SIMD4<Float>
}
```

Allocate one `.storageModePrivate` particle buffer for 2,000,000 particles plus a small shared staging buffer used only during initialization. `initializeParticles` distributes deterministic seeds. `updateParticles` trilinearly samples the velocity field, blends particle velocity toward fluid velocity using exponential drag, applies gravity, advances position and age, and respawns particles whose age exceeds lifetime or whose position leaves `[-1, 1]³`. Dispatch only `activeParticles` threads and bounds-check against both active count and capacity.

- [ ] **Step 4: Run particle and full tests**

Run: `swift test --filter MetalKernelTests && swift test`

Expected: PASS; the 64-particle test reports all positions and lifetimes in bounds.

- [ ] **Step 5: Commit**

```bash
git add Sources/NebulaForgeApp Tests/NebulaForgeAppTests
git commit -m "feat: simulate GPU tracer particles"
```

---

### Task 6: Camera and pointer-force interaction

**Files:**
- Create: `Sources/NebulaForgeApp/Renderer/Camera.swift`
- Create: `Sources/NebulaForgeApp/Renderer/PointerInteractor.swift`
- Create: `Tests/NebulaForgeAppTests/CameraTests.swift`
- Modify: `Sources/NebulaForgeApp/MetalView.swift`
- Modify: `Sources/NebulaForgeApp/Renderer/MetalRenderer.swift`

**Interfaces:**
- Produces: `Camera.viewProjection(aspect:)`, `Camera.ray(screenPoint:viewport:)`, `PointerInteractor.force(for:event:camera:) -> InteractionForce?`

- [ ] **Step 1: Write failing camera and gesture-mapping tests**

```swift
func testCenterScreenRayPointsTowardVolumeOrigin() {
    let camera = Camera.default
    let ray = camera.ray(screenPoint: SIMD2(500, 500), viewport: SIMD2(1000, 1000))
    XCTAssertGreaterThan(simd_dot(ray.direction, simd_normalize(-ray.origin)), 0.999)
}

func testModifiersMapToApprovedForceModes() {
    XCTAssertEqual(PointerMode(modifiers: [.option]), .attract)
    XCTAssertEqual(PointerMode(modifiers: [.control]), .repel)
    XCTAssertEqual(PointerMode(modifiers: [.command]), .orbit)
    XCTAssertNil(PointerMode(modifiers: []))
}
```

- [ ] **Step 2: Run tests and confirm camera types are absent**

Run: `swift test --filter CameraTests`

Expected: FAIL naming `Camera` and `PointerMode`.

- [ ] **Step 3: Implement orbit camera, ray-box intersection, and gestures**

Use a right-handed perspective matrix, yaw/pitch orbit with pitch clamped to ±85°, camera distance clamped to 1.5–8 volume radii, and ray intersection with the `[-1,1]³` fluid bounds. In `MetalView.Coordinator`, route unmodified primary drag to camera orbit, Option-drag to attract, Control-drag to repel, Command-drag to orbit force, and scroll or magnification to camera distance. Clear the active force on mouse-up and when the pointer leaves the drawable.

```swift
enum PointerMode: UInt32 { case attract = 1, repel = 2, orbit = 3 }
struct Ray { let origin: SIMD3<Float>; let direction: SIMD3<Float> }
```

- [ ] **Step 4: Run tests and manually verify every gesture**

Run: `swift test --filter CameraTests && swift run NebulaForge`

Expected: tests PASS; unmodified drag orbits, scroll zooms, and modified drags do not move the camera. Force visualization can temporarily use a small debug point encoded by `MetalRenderer` and must be removed before committing.

- [ ] **Step 5: Commit**

```bash
git add Sources/NebulaForgeApp Tests/NebulaForgeAppTests
git commit -m "feat: add camera and fluid interaction"
```

---

### Task 7: HDR particle streak rendering

**Files:**
- Create: `Sources/NebulaForgeApp/Renderer/ParticleRenderer.swift`
- Modify: `Sources/NebulaForgeApp/Shaders/Particles.metal`
- Modify: `Sources/NebulaForgeApp/Renderer/MetalRenderer.swift`

**Interfaces:**
- Consumes: `ParticleSystem.currentBuffer`, `Camera.viewProjection(aspect:)`, active particle count
- Produces: `ParticleRenderer.hdrTexture`, `ParticleRenderer.encode(commandBuffer:drawableSize:renderScale:)`

- [ ] **Step 1: Add particle vertex and fragment shaders**

`particleVertex` expands each instance into a camera-facing four-vertex streak aligned with projected `position - previousPosition`. It emits depth, normalized speed, age fraction, and a soft-sprite UV. `particleFragment` discards outside a soft elliptical falloff, maps speed and age through one of four palette uniforms, and returns premultiplied HDR color.

```metal
fragment half4 particleFragment(ParticleVertexOut in [[stage_in]]) {
    float r2 = dot(in.spriteUV, in.spriteUV);
    if (r2 >= 1.0) discard_fragment();
    float alpha = smoothstep(1.0, 0.1, r2) * (1.0 - 0.35 * in.ageFraction);
    float3 color = paletteColor(in.speed, in.ageFraction, in.paletteIndex);
    return half4(half3(color * alpha), half(alpha));
}
```

- [ ] **Step 2: Implement the floating-point render targets and draw pass**

Create size-dependent `.rgba16Float` HDR color and `.depth32Float` depth textures at `drawableSize * renderScale`. Configure premultiplied additive blending (`sourceRGB = .one`, `destinationRGB = .one`) and draw four vertices with `instanceCount = activeParticles`. Recreate targets only when drawable size or render scale changes.

- [ ] **Step 3: Launch and verify the first complete particle storm**

Run: `MTL_DEBUG_LAYER=1 swift run NebulaForge`

Expected: luminous particle streaks follow the simulated velocity field; camera orbit, zoom, and all three pointer forces visibly affect motion; resize retains simulation state.

- [ ] **Step 4: Commit**

```bash
git add Sources/NebulaForgeApp
git commit -m "feat: render HDR particle storm"
```

---

### Task 8: Trails, bloom, fog, and tone mapping

**Files:**
- Create: `Sources/NebulaForgeApp/Renderer/PostProcessor.swift`
- Create: `Sources/NebulaForgeApp/Shaders/PostProcess.metal`
- Modify: `Sources/NebulaForgeApp/Renderer/MetalRenderer.swift`

**Interfaces:**
- Consumes: `ParticleRenderer.hdrTexture`, appearance fields from `SimulationParameters`
- Produces: `PostProcessor.encode(commandBuffer:source:depth:destination:parameters:)` final drawable image

- [ ] **Step 1: Implement post-process kernels with explicit edge clamping**

Add kernels `accumulateTrails`, `extractBloom`, `blurHorizontal`, `blurVertical`, and `compositeToneMap`. Every kernel checks output coordinates and clamps texture reads. Use two half-resolution `rgba16Float` bloom textures and two full-resolution trail textures. Tone-map with ACES approximation and convert through the sRGB drawable format.

```metal
float3 aces(float3 x) {
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}
```

- [ ] **Step 2: Encode post-processing and reset temporal state correctly**

`PostProcessor.encode` accumulates current HDR with the previous trail texture, extracts bright pixels, performs a radius-dependent separable blur, composites bloom and depth fog, applies exposure, and tone-maps into the drawable. Clear both trail textures after reset, preset change, render-scale change, or resize so obsolete imagery cannot flash.

- [ ] **Step 3: Run visual boundary checks**

Run: `MTL_DEBUG_LAYER=1 swift run NebulaForge`

Expected: bloom intensity 0 removes glow, trail persistence 0 removes history, persistence 0.98 decays without permanent burn-in, exposure −4 through +4 stays finite, and repeated resizing shows no stale frames or validation errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/NebulaForgeApp
git commit -m "feat: add cinematic post processing"
```

---

### Task 9: Complete control panel, presets, and app commands

**Files:**
- Create: `Sources/NebulaForgeApp/ControlPanel.swift`
- Modify: `Sources/NebulaForgeApp/AppModel.swift`
- Modify: `Sources/NebulaForgeApp/ContentView.swift`
- Modify: `Sources/NebulaForgeApp/Renderer/MetalRenderer.swift`

**Interfaces:**
- Consumes: `SimulationParameters`, `Preset`, renderer functions `pause`, `singleStep`, `reset`, `apply`
- Produces: complete validated live GUI and preset switching

- [ ] **Step 1: Implement main-actor command routing**

```swift
@MainActor @Observable
final class AppModel {
    var parameters = Preset.solarMaelstrom.parameters
    var selectedPreset = Preset.solarMaelstrom
    var isPaused = false
    var panelVisible = true
    var performanceVisible = false
    var rendererError: RendererError?
    weak var renderer: MetalRenderer?

    func applyParameters() { parameters = parameters.validated(); renderer?.apply(parameters) }
    func applyPreset(_ preset: Preset) { selectedPreset = preset; parameters = preset.parameters; renderer?.reset(parameters) }
    func togglePause() { isPaused.toggle(); renderer?.setPaused(isPaused) }
    func singleStep() { renderer?.singleStep() }
    func reset() { renderer?.reset(parameters.validated()) }
    func randomize() { parameters = Preset.randomized(seed: UInt64.random(in: .min ... .max)); applyParameters() }
}
```

- [ ] **Step 2: Build the collapsible grouped panel**

Create groups Simulation, Forces, Emitter, Appearance, Camera, and Quality. Bind every design control, show exact units in labels, use logarithmic mapping for emission rate, particle count, viscosity, and particle size, and apply changes through `AppModel.applyParameters()`. Add tooltips with `.help`, preset picker, pause/resume, single-step, reset, randomize, overlay toggle, and a button or keyboard shortcut to collapse the panel.

- [ ] **Step 3: Verify every control at both boundaries**

Run: `swift test && swift run NebulaForge`

Expected: all tests PASS; each control updates live; preset switching clears temporal state; pause freezes simulation while camera movement and UI remain responsive; single-step advances exactly one 1/60-second step; randomize never exceeds validated ranges.

- [ ] **Step 4: Commit**

```bash
git add Sources/NebulaForgeApp
git commit -m "feat: add live simulation controls"
```

---

### Task 10: Performance overlay and adaptive-quality integration

**Files:**
- Create: `Sources/NebulaForgeApp/PerformanceOverlay.swift`
- Modify: `Sources/NebulaForgeApp/Renderer/MetalRenderer.swift`
- Modify: `Sources/NebulaForgeApp/AppModel.swift`
- Modify: `Sources/NebulaForgeApp/ContentView.swift`

**Interfaces:**
- Consumes: `AdaptiveQualityController`, `PerformanceSnapshot`
- Produces: smoothed metrics and gradual quality transitions

- [ ] **Step 1: Integrate CPU frame measurement and optional GPU counters**

Measure frame time with `CACurrentMediaTime`, smooth it over 30 frames, and publish `PerformanceSnapshot` to `AppModel` no more than four times per second. If `MTLCounterSampleBuffer` timestamps are supported, bracket fluid, particle, render, and post-process stages; otherwise leave per-pass values `nil`.

- [ ] **Step 2: Apply adaptive quality without reallocating every frame**

Feed smoothed frame time into `AdaptiveQualityController`. Apply render-scale changes immediately at the next frame boundary, active-particle changes as an integer prefix, and grid changes only after the quality policy emits a discrete `FluidGridAxis`. Clear the newly allocated fluid grid and reseed particles after a grid change. Disable this path completely when `adaptiveQuality` is false.

- [ ] **Step 3: Build and exercise the overlay**

```swift
struct PerformanceOverlay: View {
    let value: PerformanceSnapshot
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
            GridRow { Text("FPS"); Text(value.fps, format: .number.precision(.fractionLength(0))) }
            GridRow { Text("Frame"); Text("\(value.frameMilliseconds, specifier: "%.2f") ms") }
            GridRow { Text("Particles"); Text(value.activeParticles.formatted()) }
            GridRow { Text("Grid"); Text("\(value.fluidGridAxis)³") }
            GridRow { Text("Scale"); Text("\(value.renderScale, specifier: "%.2f")×") }
        }.font(.system(.caption, design: .monospaced)).padding(10).background(.black.opacity(0.55), in: .rect(cornerRadius: 8))
    }
}
```

Run: `swift test --filter AdaptiveQualityControllerTests && swift run NebulaForge`

Expected: policy tests PASS; overlay updates without flicker; forced stress lowers render scale before particle count and grid; recovery reverses grid, particles, then render scale without oscillating.

- [ ] **Step 4: Commit**

```bash
git add Sources/NebulaForgeApp
git commit -m "feat: add adaptive quality metrics"
```

---

### Task 11: Recovery, lifecycle, and user-visible errors

**Files:**
- Modify: `Sources/NebulaForgeApp/Renderer/FluidSolver.swift`
- Modify: `Sources/NebulaForgeApp/Renderer/ParticleSystem.swift`
- Modify: `Sources/NebulaForgeApp/Renderer/MetalRenderer.swift`
- Modify: `Sources/NebulaForgeApp/MetalView.swift`
- Modify: `Sources/NebulaForgeApp/ContentView.swift`
- Modify: `Tests/NebulaForgeAppTests/MetalKernelTests.swift`

**Interfaces:**
- Produces: diagnostic reduction every 120 frames, automatic state recovery, drawable lifecycle handling

- [ ] **Step 1: Add a failing non-finite recovery test**

```swift
func testNonFiniteDiagnosticTriggersReseed() throws {
    let harness = try MetalTestHarness(gridAxis: 8, particleCount: 64)
    try harness.injectNaN()
    XCTAssertFalse(try harness.diagnosticIsFinite())
    try harness.recoverIfNeeded()
    XCTAssertTrue(try harness.diagnosticIsFinite())
    XCTAssertTrue(try harness.readParticles().allSatisfy {
        $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite
    })
}
```

- [ ] **Step 2: Implement the diagnostic and recovery path**

Every 120 rendered frames, reduce finite-state flags into a four-byte shared buffer. Inspect that tiny buffer only after the command buffer completes. If false, schedule `clearFluid` and `initializeParticles` on the next frame, clear trail textures, preserve validated controls, and publish a transient “Simulation recovered” status. Never stall the current frame waiting for the diagnostic.

- [ ] **Step 3: Handle drawable and app lifecycle changes**

Skip GPU work when `currentDrawable` or `currentRenderPassDescriptor` is unavailable. On resume, discard accumulated wall time through `TimeStepper` clamping. Recreate only size-dependent post-process targets for drawable-size and backing-scale changes. Surface initialization and pipeline failures as a centered error card containing the failing stage and Metal message.

- [ ] **Step 4: Run recovery tests and lifecycle checks**

Run: `swift test --filter 'testNonFiniteDiagnosticTriggersReseed|MetalKernelTests' && MTL_DEBUG_LAYER=1 swift run NebulaForge`

Expected: tests PASS; injected non-finite state recovers; repeated minimize/restore, full-screen, resize, display move, pause/resume, and background/foreground cycles remain responsive and preserve valid state.

- [ ] **Step 5: Commit**

```bash
git add Sources/NebulaForgeApp Tests/NebulaForgeAppTests
git commit -m "fix: recover invalid GPU simulation state"
```

---

### Task 12: Final verification, profiling, and operator documentation

**Files:**
- Create: `README.md`
- Modify: `Sources/NebulaForgeCore/Preset.swift`
- Modify: any file implicated by measured failures

**Interfaces:**
- Produces: reproducible setup instructions and verified default M1 Max profile

- [ ] **Step 1: Write the README before final verification**

Document:

```text
Requirements: macOS Sequoia 15.6+, Xcode 26.2, Apple silicon
Open in Xcode: open Package.swift
Terminal launch: swift run -c release NebulaForge
Tests: swift test
Controls: drag orbit; Option attract; Control repel; Command orbit force; scroll/pinch zoom
Profiling: Product > Capture GPU Frame; Scheme Diagnostics > Metal API Validation and Shader Validation
Recovery: reset button and automatic non-finite reseed behavior
```

Also list the four presets, every control group, and the expected difference between manual stress settings and adaptive quality.

- [ ] **Step 2: Run the complete automated verification**

Run: `swift test -c debug && swift test -c release && swift build -c release`

Expected: all commands exit 0 with no test failures and no compiler warnings from project sources.

- [ ] **Step 3: Run shader compilation and validation checks**

Run: `swift test -c release --filter MetalKernelTests`

Run: `MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 swift run -c release NebulaForge`

Expected: the test creates the combined runtime Metal library and executes every kernel without failures; the release app launches with Metal API and shader validation enabled and logs no validation findings. Stop the app after exercising one reset and one resize.

- [ ] **Step 4: Profile the release build on the M1 Max**

Run: `swift run -c release NebulaForge`

In Xcode, capture a representative GPU frame with Metal API Validation and Shader Validation enabled. Exercise Solar Maelstrom full-screen for five minutes, all preset switches, every control minimum and maximum, 25 randomizations, rapid slider movement, repeated resize/full-screen/background cycles, and a 30-minute unattended run. Record default FPS, frame time, active particles, fluid grid, render scale, and pass timings in the README.

Expected: approximately 60 FPS at the measured default, no validation findings, no persistent non-finite state, no unbounded memory growth, and graceful stress degradation. If the default misses the target, change only preset defaults within approved ranges and repeat the full measurement.

- [ ] **Step 5: Confirm the clean working tree and commit documentation/calibration**

```bash
git add README.md Sources Tests Package.swift
git commit -m "docs: verify Nebula Forge release"
git status --short
```

Expected: commit succeeds and `git status --short` prints nothing.

---

## Final Acceptance Checklist

- [ ] App launches into Solar Maelstrom and animates immediately.
- [ ] Fluid pressure projection and particle bounds tests pass.
- [ ] All controls remain inside their approved tested ranges.
- [ ] Attract, repel, orbit-force, camera orbit, and zoom gestures work.
- [ ] Pause, single-step, reset, randomize, presets, and panel collapse work.
- [ ] Trails, bloom, fog, exposure, palettes, and tone mapping remain finite at boundaries.
- [ ] Resize, Retina scale, full-screen, background, and resume preserve or safely rebuild state.
- [ ] Non-finite diagnostic automatically clears and reseeds state while preserving controls.
- [ ] Adaptive quality degrades and restores in the specified order with hysteresis.
- [ ] Default release preset is measured near 60 FPS on the target M1 Max.
- [ ] Metal validation and shader validation report no findings.
- [ ] Debug and release tests pass and the repository is clean.
