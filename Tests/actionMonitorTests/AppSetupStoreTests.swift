import XCTest
@testable import actionMonitor

final class AppSetupStoreTests: XCTestCase {
    func testResetRemovesPersistedOnboardingCompletionMarker() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAppSetupStore(
            defaults: defaults,
            key: "actionMonitor.didCompleteOnboarding"
        )

        store.saveDidCompleteOnboarding(true)
        XCTAssertTrue(store.loadDidCompleteOnboarding())

        store.resetDidCompleteOnboarding()

        XCTAssertFalse(store.loadDidCompleteOnboarding())
    }
}
