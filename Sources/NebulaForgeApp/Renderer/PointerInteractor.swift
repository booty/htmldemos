import AppKit
import simd

enum PointerMode: UInt32 {
    case attract = 1
    case repel = 2
    case orbit = 3

    init?(modifiers: NSEvent.ModifierFlags) {
        switch modifiers.intersection([.shift, .option, .control, .command]) {
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
