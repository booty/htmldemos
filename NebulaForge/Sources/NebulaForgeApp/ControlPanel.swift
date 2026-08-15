import Foundation
import NebulaForgeCore
import SwiftUI

struct LogarithmicScale {
    let range: ClosedRange<Double>

    private let offset: Double

    init(range: ClosedRange<Double>) {
        precondition(range.lowerBound >= 0 && range.upperBound > range.lowerBound)
        self.range = range
        offset = range.lowerBound == 0
            ? max(range.upperBound / 10_000, Double.leastNonzeroMagnitude)
            : 0
    }

    func position(of value: Double) -> Double {
        let value = min(max(value, range.lowerBound), range.upperBound)
        let lower = log(range.lowerBound + offset)
        let upper = log(range.upperBound + offset)
        return (log(value + offset) - lower) / (upper - lower)
    }

    func value(at position: Double) -> Double {
        let position = min(max(position, 0), 1)
        let lower = log(range.lowerBound + offset)
        let upper = log(range.upperBound + offset)
        let value = exp(lower + (upper - lower) * position) - offset
        if position == 0 {
            return range.lowerBound
        }
        if position == 1 {
            return range.upperBound
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

struct ControlPanel: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            header
            presetPicker
            commandButtons
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    group("Simulation", systemImage: "waveform.path.ecg") {
                        simulationControls
                    }
                    group("Forces", systemImage: "tornado") {
                        forceControls
                    }
                    group("Emitter", systemImage: "sparkles") {
                        emitterControls
                    }
                    group("Appearance", systemImage: "paintpalette") {
                        appearanceControls
                    }
                    group("Camera", systemImage: "camera.aperture") {
                        cameraControls
                    }
                    group("Quality", systemImage: "slider.horizontal.3") {
                        qualityControls
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(14)
        .frame(width: 380)
        .frame(maxHeight: 820)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.14))
        }
        .shadow(color: .black.opacity(0.35), radius: 22, y: 8)
        .accessibilityIdentifier("control-panel")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("NEBULA FORGE")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text(model.isPaused ? "SIMULATION PAUSED" : "LIVE SIMULATION")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(model.isPaused ? .orange : .mint)
            }
            Spacer()
            Button {
                model.panelVisible = false
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("Collapse controls (⇧⌘C)")
            .accessibilityLabel("Collapse controls")
        }
    }

    private var presetPicker: some View {
        HStack {
            Label("Preset", systemImage: "wand.and.stars")
            Spacer()
            Picker(
                "Preset",
                selection: Binding(
                    get: { model.selectedPreset },
                    set: { selection in
                        if case .preset(let preset) = selection {
                            model.applyPreset(preset)
                        }
                    }
                )
            ) {
                Text("Custom").tag(PresetSelection.custom)
                ForEach(Preset.allCases) { preset in
                    Text(preset.rawValue).tag(PresetSelection.preset(preset))
                }
            }
            .labelsHidden()
            .frame(width: 190)
            .help("Load a validated look and clear fluid, particles, and trail history.")
            .accessibilityIdentifier("preset-picker")
        }
    }

    private var commandButtons: some View {
        HStack(spacing: 7) {
            commandButton(
                model.isPaused ? "Resume" : "Pause",
                systemImage: model.isPaused ? "play.fill" : "pause.fill",
                help: model.isPaused
                    ? "Resume continuous simulation."
                    : "Freeze simulation while keeping camera and controls live.",
                action: model.togglePause
            )
            commandButton(
                "Step",
                systemImage: "forward.frame.fill",
                help: "Advance one exact 1/60-second simulation step.",
                disabled: !model.isPaused,
                action: model.singleStep
            )
            commandButton(
                "Reset",
                systemImage: "arrow.counterclockwise",
                help: "Clear and deterministically reseed the current fluid and particles.",
                action: model.reset
            )
            commandButton(
                "Random",
                systemImage: "dice.fill",
                help: "Generate a bounded, validated variation without reallocating resources.",
                action: model.randomize
            )
        }
    }

    @ViewBuilder
    private var simulationControls: some View {
        logarithmicIntegerSlider(
            "Active particles",
            value: integerBinding(\.activeParticles),
            range: 50_000...2_000_000,
            step: 1_000,
            unit: "particles",
            help: "Number of active GPU tracer particles; storage remains allocated at the safe maximum."
        )
        logarithmicFloatSlider(
            "Emission rate",
            value: floatBinding(\.emissionRate),
            range: 1_000...500_000,
            unit: "particles/s",
            format: { $0.formatted(.number.precision(.fractionLength(0))) },
            help: "Tracer births requested per simulation second."
        )
        floatSlider(
            "Particle lifetime",
            value: floatBinding(\.particleLifetime),
            range: 0.5...20,
            step: 0.1,
            unit: "s",
            format: oneDecimal,
            help: "Seconds before a tracer expires and returns to the emitter."
        )
        logarithmicFloatSlider(
            "Particle size",
            value: floatBinding(\.particleSize),
            range: 0.25...8,
            unit: "px",
            format: twoDecimals,
            help: "Rendered point diameter in internal render pixels."
        )
        floatSlider(
            "Particle drag",
            value: floatBinding(\.particleDrag),
            range: 0...8,
            step: 0.05,
            unit: "s⁻¹",
            format: twoDecimals,
            help: "Rate at which particle velocity follows the fluid."
        )
        enumPicker(
            "Fluid grid",
            selection: binding(\.fluidGridAxis),
            values: FluidGridAxis.allCases,
            label: { "\($0.rawValue)³ cells" },
            help: "Cells on each axis. Changing this clears and rebuilds fluid and particles."
        )
        floatSlider(
            "Simulation speed",
            value: floatBinding(\.simulationSpeed),
            range: 0...2.5,
            step: 0.05,
            unit: "×",
            format: twoDecimals,
            help: "Multiplier applied to wall-clock simulation time."
        )
        logarithmicFloatSlider(
            "Viscosity",
            value: floatBinding(\.viscosity),
            range: 0...0.02,
            unit: "",
            format: fourDecimals,
            help: "Zero-preserving logarithmic control for velocity diffusion."
        )
        floatSlider(
            "Velocity dissipation",
            value: floatBinding(\.velocityDissipation),
            range: 0...4,
            step: 0.02,
            unit: "s⁻¹",
            format: twoDecimals,
            help: "Rate at which the fluid velocity field loses energy."
        )
        integerSlider(
            "Pressure iterations",
            value: integerBinding(\.pressureIterations),
            range: 8...80,
            step: 1,
            unit: "iterations",
            help: "Jacobi projection iterations performed per fluid step."
        )
    }

    @ViewBuilder
    private var forceControls: some View {
        floatSlider(
            "Vorticity strength",
            value: floatBinding(\.vorticityStrength),
            range: 0...12,
            step: 0.1,
            unit: "",
            format: oneDecimal,
            help: "Confinement force that restores small swirling structures."
        )
        floatSlider(
            "Gravity magnitude",
            value: floatBinding(\.gravityMagnitude),
            range: 0...20,
            step: 0.25,
            unit: "units/s²",
            format: twoDecimals,
            help: "Downward acceleration applied to fluid and particles."
        )
        floatSlider(
            "Attraction magnitude",
            value: floatBinding(\.attractionMagnitude),
            range: 0...60,
            step: 0.5,
            unit: "units/s²",
            format: oneDecimal,
            help: "Strength used by the central and Option-drag attraction force."
        )
        floatSlider(
            "Orbital-force magnitude",
            value: floatBinding(\.orbitalForceMagnitude),
            range: 0...60,
            step: 0.5,
            unit: "units/s²",
            format: oneDecimal,
            help: "Strength of Command-drag tangential force."
        )
        floatSlider(
            "Turbulence scale",
            value: floatBinding(\.turbulenceScale),
            range: 0.2...8,
            step: 0.05,
            unit: "cycles/volume",
            format: twoDecimals,
            help: "Spatial frequency of procedural turbulence."
        )
        floatSlider(
            "Turbulence strength",
            value: floatBinding(\.turbulenceStrength),
            range: 0...40,
            step: 0.25,
            unit: "units/s²",
            format: twoDecimals,
            help: "Acceleration contributed by procedural turbulence."
        )
    }

    @ViewBuilder
    private var emitterControls: some View {
        vectorSliders(
            "Position",
            vector: vectorBinding(\.emitterPosition),
            range: -1...1,
            unit: "scene units",
            help: "Emitter center inside the normalized simulation volume."
        )
        floatSlider(
            "Radius",
            value: floatBinding(\.emitterRadius),
            range: 0.01...0.75,
            step: 0.01,
            unit: "scene units",
            format: twoDecimals,
            help: "Radius of the spherical particle source."
        )
        vectorSliders(
            "Direction",
            vector: vectorBinding(\.emitterDirection),
            range: -1...1,
            unit: "normalized",
            help: "Normalized launch direction. Zero length safely falls back to +Y."
        )
        floatSlider(
            "Spread",
            value: floatBinding(\.emitterSpread),
            range: 0...1,
            step: 0.01,
            unit: "normalized",
            format: twoDecimals,
            help: "Launch cone width from a narrow jet to a broad spray."
        )
        floatSlider(
            "Initial velocity",
            value: floatBinding(\.emitterInitialVelocity),
            range: 0...20,
            step: 0.1,
            unit: "units/s",
            format: oneDecimal,
            help: "Particle speed at birth."
        )
    }

    @ViewBuilder
    private var appearanceControls: some View {
        enumPicker(
            "Palette",
            selection: binding(\.palette),
            values: Palette.allCases,
            label: paletteName,
            help: "Color ramp applied to particle velocity and age."
        )
        floatSlider(
            "Velocity color mix",
            value: floatBinding(\.velocityColorMix),
            range: 0...1,
            step: 0.01,
            unit: "%",
            format: percent,
            help: "Blend between age-based and velocity-based coloring."
        )
        floatSlider(
            "Exposure",
            value: floatBinding(\.exposure),
            range: -4...4,
            step: 0.1,
            unit: "EV",
            format: oneDecimal,
            help: "Tone-mapping exposure from −4 to +4 stops."
        )
        floatSlider(
            "Bloom intensity",
            value: floatBinding(\.bloomIntensity),
            range: 0...3,
            step: 0.05,
            unit: "",
            format: twoDecimals,
            help: "Strength of glow extracted from bright particles; zero disables glow."
        )
        floatSlider(
            "Bloom radius",
            value: floatBinding(\.bloomRadius),
            range: 0...24,
            step: 1,
            unit: "px",
            format: { $0.formatted(.number.precision(.fractionLength(0))) },
            help: "Separable blur radius in internal render pixels."
        )
        floatSlider(
            "Trail persistence",
            value: floatBinding(\.trailPersistence),
            range: 0...0.98,
            step: 0.01,
            unit: "",
            format: twoDecimals,
            help: "Fraction of prior HDR history retained per frame; zero removes history."
        )
        floatSlider(
            "Depth fog",
            value: floatBinding(\.depthFog),
            range: 0...1,
            step: 0.01,
            unit: "%",
            format: percent,
            help: "Depth-dependent atmospheric attenuation."
        )
        floatSlider(
            "Background intensity",
            value: floatBinding(\.backgroundIntensity),
            range: 0...0.4,
            step: 0.005,
            unit: "",
            format: threeDecimals,
            help: "Linear intensity of the deep-space background."
        )
    }

    @ViewBuilder
    private var cameraControls: some View {
        floatSlider(
            "Orbit speed",
            value: floatBinding(\.cameraOrbitSpeed),
            range: 0...1,
            step: 0.01,
            unit: "rad/s",
            format: twoDecimals,
            help: "Yaw rate used by the automatic cinematic camera."
        )
        floatSlider(
            "Field of view",
            value: floatBinding(\.fieldOfViewDegrees),
            range: 25...90,
            step: 1,
            unit: "°",
            format: { $0.formatted(.number.precision(.fractionLength(0))) },
            help: "Vertical camera field of view in degrees."
        )
        Toggle(
            "Automatic cinematic camera",
            isOn: binding(\.automaticCinematicCamera)
        )
        .toggleStyle(.switch)
        .help("Orbit the camera independently of simulation pause.")
    }

    @ViewBuilder
    private var qualityControls: some View {
        enumPicker(
            "Render scale",
            selection: binding(\.renderScale),
            values: [
                Float(0.5), 0.55, 0.6, 0.65, 0.7, 0.75,
                0.8, 0.85, 0.9, 0.95, 1,
            ],
            label: { "\(twoDecimals(Double($0)))×" },
            help: "Internal HDR resolution relative to drawable pixels. Changes clear trail history."
        )
        enumPicker(
            "Target frame rate",
            selection: binding(\.targetFrameRate),
            values: FrameRateTarget.allCases,
            label: { "\($0.rawValue) FPS" },
            help: "Metal view presentation target: 30, 60, or 120 frames per second."
        )
        Toggle("Adaptive quality", isOn: binding(\.adaptiveQuality))
            .toggleStyle(.switch)
            .help("Allow the Task 10 quality policy to reduce load under sustained frame pressure.")
        Toggle("Performance overlay", isOn: Binding(
            get: { model.performanceVisible },
            set: { model.performanceVisible = $0 }
        ))
        .toggleStyle(.switch)
        .help("Show or hide performance metrics when Task 10 supplies them.")
    }

    private func group<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup {
            VStack(spacing: 11) {
                content()
            }
            .padding(.top, 10)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
        }
        .padding(10)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }

    private func commandButton(
        _ title: String,
        systemImage: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(title)
    }

    private func floatSlider(
        _ title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float,
        unit: String,
        format: @escaping (Double) -> String,
        help: String
    ) -> some View {
        VStack(spacing: 4) {
            valueRow(title, value: format(Double(value.wrappedValue)), unit: unit)
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
        }
        .help(help)
    }

    private func logarithmicFloatSlider(
        _ title: String,
        value: Binding<Float>,
        range: ClosedRange<Double>,
        unit: String,
        format: @escaping (Double) -> String,
        help: String
    ) -> some View {
        let scale = LogarithmicScale(range: range)
        let position = Binding<Double>(
            get: { scale.position(of: Double(value.wrappedValue)) },
            set: { value.wrappedValue = Float(scale.value(at: $0)) }
        )
        return VStack(spacing: 4) {
            valueRow(title, value: format(Double(value.wrappedValue)), unit: unit)
            Slider(value: position, in: 0...1)
                .accessibilityLabel(title)
        }
        .help(help)
    }

    private func integerSlider(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        unit: String,
        help: String
    ) -> some View {
        let doubleValue = Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = Int($0.rounded()) }
        )
        return VStack(spacing: 4) {
            valueRow(
                title,
                value: value.wrappedValue.formatted(),
                unit: unit
            )
            Slider(
                value: doubleValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .accessibilityLabel(title)
        }
        .help(help)
    }

    private func logarithmicIntegerSlider(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        unit: String,
        help: String
    ) -> some View {
        let scale = LogarithmicScale(
            range: Double(range.lowerBound)...Double(range.upperBound)
        )
        let position = Binding<Double>(
            get: { scale.position(of: Double(value.wrappedValue)) },
            set: {
                let raw = Int(scale.value(at: $0).rounded())
                value.wrappedValue = min(
                    max((raw / step) * step, range.lowerBound),
                    range.upperBound
                )
            }
        )
        return VStack(spacing: 4) {
            valueRow(title, value: value.wrappedValue.formatted(), unit: unit)
            Slider(value: position, in: 0...1)
                .accessibilityLabel(title)
        }
        .help(help)
    }

    private func vectorSliders(
        _ title: String,
        vector: Binding<SIMD3<Float>>,
        range: ClosedRange<Float>,
        unit: String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(title) (\(unit))")
                .font(.caption)
                .foregroundStyle(.secondary)
            vectorComponent("X", vector: vector, keyPath: \.x, range: range)
            vectorComponent("Y", vector: vector, keyPath: \.y, range: range)
            vectorComponent("Z", vector: vector, keyPath: \.z, range: range)
        }
        .help(help)
    }

    private func vectorComponent(
        _ axis: String,
        vector: Binding<SIMD3<Float>>,
        keyPath: WritableKeyPath<SIMD3<Float>, Float>,
        range: ClosedRange<Float>
    ) -> some View {
        let value = Binding<Float>(
            get: { vector.wrappedValue[keyPath: keyPath] },
            set: { component in
                var changed = vector.wrappedValue
                changed[keyPath: keyPath] = component
                vector.wrappedValue = changed
            }
        )
        return HStack {
            Text(axis)
                .font(.system(.caption2, design: .monospaced))
                .frame(width: 12)
            Slider(value: value, in: range, step: 0.01)
            Text(twoDecimals(Double(value.wrappedValue)))
                .font(.system(.caption2, design: .monospaced))
                .frame(width: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(axis) \(value.wrappedValue)")
    }

    private func enumPicker<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        values: [Value],
        label: @escaping (Value) -> String,
        help: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 155)
        }
        .help(help)
    }

    private func valueRow(
        _ title: String,
        value: String,
        unit: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(unit.isEmpty ? value : "\(value) \(unit)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<SimulationParameters, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.parameters[keyPath: keyPath] },
            set: {
                model.parameters[keyPath: keyPath] = $0
                model.applyParameters()
            }
        )
    }

    private func floatBinding(
        _ keyPath: WritableKeyPath<SimulationParameters, Float>
    ) -> Binding<Float> {
        binding(keyPath)
    }

    private func integerBinding(
        _ keyPath: WritableKeyPath<SimulationParameters, Int>
    ) -> Binding<Int> {
        binding(keyPath)
    }

    private func vectorBinding(
        _ keyPath: WritableKeyPath<SimulationParameters, SIMD3<Float>>
    ) -> Binding<SIMD3<Float>> {
        binding(keyPath)
    }

    private func paletteName(_ palette: Palette) -> String {
        switch palette {
        case .solar: "Solar"
        case .aurora: "Aurora"
        case .supernova: "Supernova"
        case .void: "Void"
        }
    }

    private func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func twoDecimals(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func threeDecimals(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)))
    }

    private func fourDecimals(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(4)))
    }

    private func percent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(0)))
    }
}
