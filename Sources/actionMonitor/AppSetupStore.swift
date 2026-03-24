import Foundation

protocol AppSetupStore: Sendable {
    func loadDidCompleteOnboarding() -> Bool
    func saveDidCompleteOnboarding(_ didCompleteOnboarding: Bool)
    func resetDidCompleteOnboarding()
}

struct UserDefaultsAppSetupStore: AppSetupStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "actionMonitor.didCompleteOnboarding"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func loadDidCompleteOnboarding() -> Bool {
        defaults.bool(forKey: key)
    }

    func saveDidCompleteOnboarding(_ didCompleteOnboarding: Bool) {
        defaults.set(didCompleteOnboarding, forKey: key)
    }

    func resetDidCompleteOnboarding() {
        defaults.removeObject(forKey: key)
    }
}

struct DemoAppSetupStore: AppSetupStore {
    func loadDidCompleteOnboarding() -> Bool {
        true
    }

    func saveDidCompleteOnboarding(_ didCompleteOnboarding: Bool) {}

    func resetDidCompleteOnboarding() {}
}
