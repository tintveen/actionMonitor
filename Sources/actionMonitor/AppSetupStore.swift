import Foundation

protocol AppSetupStore: Sendable {
    func loadDidCompleteOnboarding() -> Bool
    func saveDidCompleteOnboarding(_ didCompleteOnboarding: Bool)
    func resetDidCompleteOnboarding()
    func loadWorkflowRefreshInterval() -> WorkflowRefreshInterval
    func saveWorkflowRefreshInterval(_ interval: WorkflowRefreshInterval)
    func resetWorkflowRefreshInterval()
}

struct UserDefaultsAppSetupStore: AppSetupStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let didCompleteOnboardingKey: String
    private let workflowRefreshIntervalKey: String

    init(
        defaults: UserDefaults = .standard,
        didCompleteOnboardingKey: String = "actionMonitor.didCompleteOnboarding",
        workflowRefreshIntervalKey: String = "actionMonitor.workflowRefreshInterval"
    ) {
        self.defaults = defaults
        self.didCompleteOnboardingKey = didCompleteOnboardingKey
        self.workflowRefreshIntervalKey = workflowRefreshIntervalKey
    }

    func loadDidCompleteOnboarding() -> Bool {
        defaults.bool(forKey: didCompleteOnboardingKey)
    }

    func saveDidCompleteOnboarding(_ didCompleteOnboarding: Bool) {
        defaults.set(didCompleteOnboarding, forKey: didCompleteOnboardingKey)
    }

    func resetDidCompleteOnboarding() {
        defaults.removeObject(forKey: didCompleteOnboardingKey)
    }

    func loadWorkflowRefreshInterval() -> WorkflowRefreshInterval {
        guard let interval = WorkflowRefreshInterval(
            rawValue: defaults.integer(forKey: workflowRefreshIntervalKey)
        ), defaults.object(forKey: workflowRefreshIntervalKey) != nil else {
            return .default
        }

        return interval
    }

    func saveWorkflowRefreshInterval(_ interval: WorkflowRefreshInterval) {
        defaults.set(interval.rawValue, forKey: workflowRefreshIntervalKey)
    }

    func resetWorkflowRefreshInterval() {
        defaults.removeObject(forKey: workflowRefreshIntervalKey)
    }
}

struct DemoAppSetupStore: AppSetupStore {
    func loadDidCompleteOnboarding() -> Bool {
        true
    }

    func saveDidCompleteOnboarding(_ didCompleteOnboarding: Bool) {}

    func resetDidCompleteOnboarding() {}

    func loadWorkflowRefreshInterval() -> WorkflowRefreshInterval {
        .default
    }

    func saveWorkflowRefreshInterval(_ interval: WorkflowRefreshInterval) {}

    func resetWorkflowRefreshInterval() {}
}
