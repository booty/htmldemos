import AppKit
import simd

enum PointerMode: UInt32 {
    case attract = 1
    case repel = 2
    case orbit = 3

    /// Caps Lock and Function describe keyboard state rather than a pointer
    /// gesture, so they are ignored. Gesture modifiers must otherwise match
    /// one supported single-key combination exactly.
    init?(modifiers: NSEvent.ModifierFlags) {
        switch modifiers.gestureModifiers {
        case [.option]:
            self = .attract
        case [.control]:
            self = .repel
        case [.command]:
            self = .orbit
        default:
            return nil
        }
    }
}

enum PointerButton: Equatable {
    case primary
    case secondary
}

enum PointerPhase: Equatable {
    case down
    case drag
    case up
}

enum PointerAction: Equatable {
    case none
    case cameraOrbit
    case force(PointerMode)
}

struct PointerRoute: Equatable {
    let action: PointerAction
    let clearsForce: Bool
}

enum PointerEventRouter {
    static func route(
        button: PointerButton,
        phase: PointerPhase,
        modifiers: NSEvent.ModifierFlags
    ) -> PointerRoute {
        guard phase != .up else {
            return PointerRoute(action: .none, clearsForce: true)
        }

        let mode = PointerMode(modifiers: modifiers)
        switch button {
        case .primary:
            if let mode {
                return PointerRoute(action: .force(mode), clearsForce: false)
            }
            let action: PointerAction = phase == .drag && modifiers.gestureModifiers.isEmpty
                ? .cameraOrbit
                : .none
            return PointerRoute(action: action, clearsForce: true)
        case .secondary:
            if mode == .repel {
                return PointerRoute(action: .force(.repel), clearsForce: false)
            }
            return PointerRoute(action: .none, clearsForce: true)
        }
    }
}

struct PointerEvent {
    let screenPoint: SIMD2<Float>
    let viewport: SIMD2<Float>
}

struct PointerInteractor {
    var radius: Float = 0.35
    var strength: Float = 14

    func force(
        for mode: PointerMode,
        event: PointerEvent,
        camera: Camera
    ) -> InteractionForce? {
        let ray = camera.ray(
            screenPoint: event.screenPoint,
            viewport: event.viewport
        )
        guard let position = ray.intersectionWithFluidBounds() else {
            return nil
        }

        return InteractionForce(
            positionRadius: SIMD4(position, radius),
            directionStrength: SIMD4(camera.up, strength),
            modeAndPadding: SIMD4(mode.rawValue, 0, 0, 0)
        )
    }
}

private extension Ray {
    func intersectionWithFluidBounds() -> SIMD3<Float>? {
        let lowerBound = SIMD3<Float>(repeating: -1)
        let upperBound = SIMD3<Float>(repeating: 1)
        var entry = -Float.infinity
        var exit = Float.infinity

        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-6 {
                guard origin[axis] >= lowerBound[axis], origin[axis] <= upperBound[axis] else {
                    return nil
                }
                continue
            }

            let inverseDirection = 1 / direction[axis]
            let first = (lowerBound[axis] - origin[axis]) * inverseDirection
            let second = (upperBound[axis] - origin[axis]) * inverseDirection
            entry = max(entry, min(first, second))
            exit = min(exit, max(first, second))
            guard entry <= exit else { return nil }
        }

        guard exit >= 0 else { return nil }
        let distance = entry >= 0 ? entry : exit
        return origin + direction * distance
    }
}

private extension NSEvent.ModifierFlags {
    var gestureModifiers: NSEvent.ModifierFlags {
        intersection([.shift, .option, .control, .command])
    }
}
