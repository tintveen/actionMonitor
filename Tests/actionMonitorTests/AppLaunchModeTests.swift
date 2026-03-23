import XCTest
@testable import actionMonitor

final class AppLaunchModeTests: XCTestCase {
    func testDefaultsToLiveMode() {
        XCTAssertEqual(AppLaunchMode(arguments: ["actionMonitor"]), .live)
    }

    func testDemoFlagSelectsDemoMode() {
        XCTAssertEqual(AppLaunchMode(arguments: ["actionMonitor", "--demo"]), .demo)
    }
}
