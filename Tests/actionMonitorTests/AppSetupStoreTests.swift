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
            didCompleteOnboardingKey: "actionMonitor.didCompleteOnboarding",
            workflowRefreshIntervalKey: "actionMonitor.workflowRefreshInterval"
        )

        store.saveDidCompleteOnboarding(true)
        XCTAssertTrue(store.loadDidCompleteOnboarding())

        store.resetDidCompleteOnboarding()

        XCTAssertFalse(store.loadDidCompleteOnboarding())
    }

    func testWorkflowRefreshIntervalDefaultsToOneMinuteWhenUnset() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAppSetupStore(
            defaults: defaults,
            didCompleteOnboardingKey: "actionMonitor.didCompleteOnboarding",
            workflowRefreshIntervalKey: "actionMonitor.workflowRefreshInterval"
        )

        XCTAssertEqual(store.loadWorkflowRefreshInterval(), .default)
    }

    func testWorkflowRefreshIntervalCanBeSavedAndReset() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAppSetupStore(
            defaults: defaults,
            didCompleteOnboardingKey: "actionMonitor.didCompleteOnboarding",
            workflowRefreshIntervalKey: "actionMonitor.workflowRefreshInterval"
        )

        store.saveWorkflowRefreshInterval(.twoMinutes)
        XCTAssertEqual(store.loadWorkflowRefreshInterval(), .twoMinutes)

        store.resetWorkflowRefreshInterval()
        XCTAssertEqual(store.loadWorkflowRefreshInterval(), .default)
    }
}
