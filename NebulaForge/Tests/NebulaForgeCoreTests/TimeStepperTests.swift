import XCTest
@testable import NebulaForgeCore

final class TimeStepperTests: XCTestCase {
    func testSlowFrameIsClampedAndSplit() {
        let schedule = TimeStepper().schedule(wallDelta: 1, speed: 1)

        XCTAssertEqual(schedule.stepCount, 4)
        XCTAssertEqual(schedule.stepDelta, 1.0 / 60.0, accuracy: 0.0001)
    }

    func testNonFiniteAndNegativeInputsDoNotScheduleSteps() {
        XCTAssertEqual(TimeStepper().schedule(wallDelta: .infinity, speed: 1), StepSchedule(stepCount: 0, stepDelta: 0))
        XCTAssertEqual(TimeStepper().schedule(wallDelta: -1, speed: 1), StepSchedule(stepCount: 0, stepDelta: 0))
        XCTAssertEqual(TimeStepper().schedule(wallDelta: 1.0 / 60.0, speed: -1), StepSchedule(stepCount: 0, stepDelta: 0))
    }
}
