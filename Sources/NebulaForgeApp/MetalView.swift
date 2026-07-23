import MetalKit
import SwiftUI

struct MetalView: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        do {
            let metalContext = try MetalContext()
            let view = configuredView(device: metalContext.device)
            let renderer = try MetalRenderer(
                context: metalContext,
                colorPixelFormat: view.colorPixelFormat
            )
            context.coordinator.renderer = renderer
            view.interactionDelegate = context.coordinator
            model.renderer = renderer
            model.rendererError = nil
            view.delegate = renderer
            return view
        } catch let error as RendererError {
            model.rendererError = error
            let view = configuredView(device: nil)
            view.interactionDelegate = context.coordinator
            return view
        } catch {
            model.rendererError = .shaderCompilation(error.localizedDescription)
            let view = configuredView(device: nil)
            view.interactionDelegate = context.coordinator
            return view
        }
    }

    func updateNSView(_ view: MTKView, context: Context) {}

    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        (view as? InteractiveMetalView)?.interactionDelegate = nil
        coordinator.clearInteractionForce()
        coordinator.renderer = nil
    }

    private func configuredView(device: MTLDevice?) -> InteractiveMetalView {
        let view = InteractiveMetalView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.clearColor = MTLClearColor(red: 0.01, green: 0.005, blue: 0.04, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        return view
    }

    @MainActor
    final class Coordinator: InteractiveMetalViewDelegate {
        private static let orbitSensitivity: Float = 0.006
        private static let scrollSensitivity: Float = 0.02

        var renderer: MetalRenderer? {
            didSet { renderer?.updateCamera(camera) }
        }

        private var camera = Camera.default
        private let pointerInteractor = PointerInteractor()

        func pointerDown(_ event: NSEvent, in view: MTKView) {
            updateDrag(event, in: view, appliesCameraDelta: false)
        }

        func pointerDragged(_ event: NSEvent, in view: MTKView) {
            updateDrag(event, in: view, appliesCameraDelta: true)
        }

        func pointerUp() {
            clearInteractionForce()
        }

        func pointerExited() {
            clearInteractionForce()
        }

        func pointerScrolled(_ event: NSEvent) {
            camera.zoom(by: Float(event.scrollingDeltaY) * Self.scrollSensitivity)
            renderer?.updateCamera(camera)
        }

        func pointerMagnified(_ event: NSEvent) {
            camera.zoom(by: -Float(event.magnification) * camera.distance)
            renderer?.updateCamera(camera)
        }

        fileprivate func clearInteractionForce() {
            renderer?.updateInteractionForce(nil)
        }

        private func updateDrag(
            _ event: NSEvent,
            in view: MTKView,
            appliesCameraDelta: Bool
        ) {
            if let mode = PointerMode(modifiers: event.modifierFlags) {
                updateInteractionForce(mode: mode, event: event, in: view)
                return
            }

            clearInteractionForce()
            let dragModifiers = event.modifierFlags.intersection([
                .shift, .option, .control, .command
            ])
            guard appliesCameraDelta, dragModifiers.isEmpty else { return }

            camera.orbit(by: SIMD2(
                Float(event.deltaX) * Self.orbitSensitivity,
                -Float(event.deltaY) * Self.orbitSensitivity
            ))
            renderer?.updateCamera(camera)
        }

        private func updateInteractionForce(
            mode: PointerMode,
            event: NSEvent,
            in view: MTKView
        ) {
            let localPoint = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(localPoint) else {
                clearInteractionForce()
                return
            }

            let pointerEvent = PointerEvent(
                screenPoint: SIMD2(
                    Float(localPoint.x),
                    Float(view.bounds.height - localPoint.y)
                ),
                viewport: SIMD2(Float(view.bounds.width), Float(view.bounds.height))
            )
            let force = pointerInteractor.force(
                for: mode,
                event: pointerEvent,
                camera: camera
            )
            renderer?.updateInteractionForce(force)
        }
    }
}

@MainActor
private protocol InteractiveMetalViewDelegate: AnyObject {
    func pointerDown(_ event: NSEvent, in view: MTKView)
    func pointerDragged(_ event: NSEvent, in view: MTKView)
    func pointerUp()
    func pointerExited()
    func pointerScrolled(_ event: NSEvent)
    func pointerMagnified(_ event: NSEvent)
}

private final class InteractiveMetalView: MTKView {
    weak var interactionDelegate: (any InteractiveMetalViewDelegate)?
    private var pointerTrackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        super.updateTrackingAreas()
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        interactionDelegate?.pointerDown(event, in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        interactionDelegate?.pointerDragged(event, in: self)
    }

    override func mouseUp(with event: NSEvent) {
        interactionDelegate?.pointerUp()
    }

    override func mouseExited(with event: NSEvent) {
        interactionDelegate?.pointerExited()
    }

    override func scrollWheel(with event: NSEvent) {
        interactionDelegate?.pointerScrolled(event)
    }

    override func magnify(with event: NSEvent) {
        interactionDelegate?.pointerMagnified(event)
    }
}
