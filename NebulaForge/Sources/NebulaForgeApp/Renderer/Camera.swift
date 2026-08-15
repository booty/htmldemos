import simd

struct Ray {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>
}

struct Camera: Equatable {
    static let pitchLimit = Float.pi * 85 / 180
    static let distanceRange: ClosedRange<Float> = 1.5...8

    var yaw: Float
    private(set) var pitch: Float
    private(set) var distance: Float
    var fieldOfView: Float
    var target: SIMD3<Float>

    static let `default` = Camera(
        yaw: 0,
        pitch: 0,
        distance: 4,
        fieldOfView: Float.pi / 4,
        target: .zero
    )

    init(
        yaw: Float,
        pitch: Float,
        distance: Float,
        fieldOfView: Float = Float.pi / 4,
        target: SIMD3<Float> = .zero
    ) {
        self.yaw = yaw
        self.pitch = pitch.clamped(to: -Self.pitchLimit...Self.pitchLimit)
        self.distance = distance.clamped(to: Self.distanceRange)
        self.fieldOfView = fieldOfView
        self.target = target
    }

    var position: SIMD3<Float> {
        let horizontalDistance = distance * cos(pitch)
        return target + SIMD3(
            horizontalDistance * sin(yaw),
            distance * sin(pitch),
            horizontalDistance * cos(yaw)
        )
    }

    var forward: SIMD3<Float> {
        simd_normalize(target - position)
    }

    var right: SIMD3<Float> {
        simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
    }

    var up: SIMD3<Float> {
        simd_normalize(simd_cross(right, forward))
    }

    func viewProjection(aspect: Float) -> simd_float4x4 {
        projectionMatrix(aspect: aspect) * viewMatrix
    }

    func ray(screenPoint: SIMD2<Float>, viewport: SIMD2<Float>) -> Ray {
        guard viewport.x > 0, viewport.y > 0 else {
            return Ray(origin: position, direction: forward)
        }

        let normalizedX = 2 * screenPoint.x / viewport.x - 1
        let normalizedY = 1 - 2 * screenPoint.y / viewport.y
        let halfHeight = tan(fieldOfView / 2)
        let aspect = viewport.x / viewport.y
        let direction = simd_normalize(
            forward
                + right * normalizedX * aspect * halfHeight
                + up * normalizedY * halfHeight
        )
        return Ray(origin: position, direction: direction)
    }

    mutating func orbit(by delta: SIMD2<Float>) {
        yaw += delta.x
        pitch = (pitch + delta.y).clamped(to: -Self.pitchLimit...Self.pitchLimit)
    }

    mutating func zoom(by delta: Float) {
        distance = (distance + delta).clamped(to: Self.distanceRange)
    }

    private var viewMatrix: simd_float4x4 {
        let eye = position
        let zAxis = -forward
        return simd_float4x4(columns: (
            SIMD4(right.x, up.x, zAxis.x, 0),
            SIMD4(right.y, up.y, zAxis.y, 0),
            SIMD4(right.z, up.z, zAxis.z, 0),
            SIMD4(-simd_dot(right, eye), -simd_dot(up, eye), -simd_dot(zAxis, eye), 1)
        ))
    }

    private func projectionMatrix(aspect: Float) -> simd_float4x4 {
        let nearPlane: Float = 0.1
        let farPlane: Float = 100
        let yScale = 1 / tan(fieldOfView / 2)
        let xScale = yScale / max(aspect, Float.leastNonzeroMagnitude)
        let zScale = farPlane / (nearPlane - farPlane)
        let zTranslation = nearPlane * farPlane / (nearPlane - farPlane)
        return simd_float4x4(columns: (
            SIMD4(xScale, 0, 0, 0),
            SIMD4(0, yScale, 0, 0),
            SIMD4(0, 0, zScale, -1),
            SIMD4(0, 0, zTranslation, 0)
        ))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
