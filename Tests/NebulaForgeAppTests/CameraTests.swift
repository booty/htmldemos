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
        XCTAssertEqual(PointerMode(modifiers: [.capsLock, .option]), .attract)
        XCTAssertEqual(PointerMode(modifiers: [.function, .command]), .orbit)
        XCTAssertNil(PointerMode(modifiers: []))
        XCTAssertNil(PointerMode(modifiers: [.shift]))
        XCTAssertNil(PointerMode(modifiers: [.option, .control]))
        XCTAssertNil(PointerMode(modifiers: [.shift, .option]))
    }

    func testPrimaryDragRoutesOptionAndCommandToForceModes() {
        XCTAssertEqual(
            PointerEventRouter.route(
                button: .primary,
                phase: .drag,
                modifiers: [.option]
            ),
            PointerRoute(action: .force(.attract), clearsForce: false)
        )
        XCTAssertEqual(
            PointerEventRouter.route(
                button: .primary,
                phase: .drag,
                modifiers: [.command]
            ),
            PointerRoute(action: .force(.orbit), clearsForce: false)
        )
    }

    func testSecondaryControlDragRoutesToRepel() {
        XCTAssertEqual(
            PointerEventRouter.route(
                button: .secondary,
                phase: .drag,
                modifiers: [.control]
            ),
            PointerRoute(action: .force(.repel), clearsForce: false)
        )
    }

    func testUnsupportedPointerRoutesDoNotOrbitOrInjectAndClearForce() {
        let plainSecondary = PointerEventRouter.route(
            button: .secondary,
            phase: .drag,
            modifiers: []
        )
        let mixedPrimary = PointerEventRouter.route(
            button: .primary,
            phase: .drag,
            modifiers: [.shift, .option]
        )

        XCTAssertEqual(plainSecondary.action, .none)
        XCTAssertTrue(plainSecondary.clearsForce)
        XCTAssertEqual(mixedPrimary.action, .none)
        XCTAssertTrue(mixedPrimary.clearsForce)
    }

    func testSecondaryMouseUpRoutesToForceClear() {
        XCTAssertEqual(
            PointerEventRouter.route(
                button: .secondary,
                phase: .up,
                modifiers: [.control]
            ),
            PointerRoute(action: .none, clearsForce: true)
        )
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
