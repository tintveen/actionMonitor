import XCTest
@testable import deployBar

final class AppLaunchModeTests: XCTestCase {
    func testDefaultsToLiveMode() {
        XCTAssertEqual(AppLaunchMode(arguments: ["deployBar"]), .live)
    }

    func testDemoFlagSelectsDemoMode() {
        XCTAssertEqual(AppLaunchMode(arguments: ["deployBar", "--demo"]), .demo)
    }
}
