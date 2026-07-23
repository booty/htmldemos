import AppKit
import simd
import XCTest
@testable import NebulaForgeApp

final class CameraTests: XCTestCase {
    func testCenterScreenRayPointsTowardVolumeOrigin() {
        let camera = Camera.default
        let ray = camera.ray(
            screenPoint: SIMD2(500, 500),
            viewport: SIMD2(1000, 1000)
        )

        XCTAssertGreaterThan(
            simd_dot(ray.direction, simd_normalize(-ray.origin)),
            0.999
        )
    }

    func testModifiersMapToApprovedForceModes() {
        XCTAssertEqual(PointerMode(modifiers: [.option]), .attract)
        XCTAssertEqual(PointerMode(modifiers: [.control]), .repel)
        XCTAssertEqual(PointerMode(modifiers: [.command]), .orbit)
        XCTAssertNil(PointerMode(modifiers: []))
        XCTAssertNil(PointerMode(modifiers: [.shift]))
        XCTAssertNil(PointerMode(modifiers: [.option, .control]))
        XCTAssertNil(PointerMode(modifiers: [.shift, .option]))
    }

    func testCameraClampsPitchAndDistance() {
        var camera = Camera(
            yaw: 0,
            pitch: Float.pi,
            distance: 100
        )

        XCTAssertEqual(camera.pitch, Camera.pitchLimit)
        XCTAssertEqual(camera.distance, Camera.distanceRange.upperBound)

        camera.orbit(by: SIMD2(0, -Float.pi * 2))
        camera.zoom(by: -100)

        XCTAssertEqual(camera.pitch, -Camera.pitchLimit)
        XCTAssertEqual(camera.distance, Camera.distanceRange.lowerBound)
    }

    func testPointerForceUsesNearestRayIntersectionWithFluidBounds() throws {
        let event = PointerEvent(
            screenPoint: SIMD2(500, 500),
            viewport: SIMD2(1000, 1000)
        )

        let force = try XCTUnwrap(
            PointerInteractor().force(for: .attract, event: event, camera: .default)
        )

        XCTAssertEqual(force.positionRadius.x, 0, accuracy: 0.0001)
        XCTAssertEqual(force.positionRadius.y, 0, accuracy: 0.0001)
        XCTAssertEqual(force.positionRadius.z, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(force.positionRadius.w, 0)
        XCTAssertEqual(force.modeAndPadding.x, PointerMode.attract.rawValue)
    }

    func testPointerForceIsNilWhenRayMissesFluidBounds() {
        let event = PointerEvent(
            screenPoint: SIMD2(0, 500),
            viewport: SIMD2(1000, 1000)
        )

        XCTAssertNil(
            PointerInteractor().force(for: .repel, event: event, camera: .default)
        )
    }
}
