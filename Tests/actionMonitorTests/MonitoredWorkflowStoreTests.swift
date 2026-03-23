import XCTest
@testable import actionMonitor

final class MonitoredWorkflowStoreTests: XCTestCase {
    func testFileBackedStoreReturnsEmptyWhenFileIsMissing() throws {
        let fileURL = temporaryFileURL()
        let store = FileBackedMonitoredWorkflowStore(fileURL: fileURL)

        XCTAssertEqual(try store.loadWorkflows(), [])
    }

    func testFileBackedStoreRoundTripsWorkflowsInOrder() throws {
        let fileURL = temporaryFileURL()
        let store = FileBackedMonitoredWorkflowStore(fileURL: fileURL)
        let first = MonitoredWorkflow(
            id: UUID(uuidString: "778EB9D3-854F-43AB-99B4-1C41DCE14544")!,
            displayName: "First",
            owner: "octo-org",
            repo: "first",
            branch: "main",
            workflowFile: "deploy.yml",
            siteURL: URL(string: "https://first.example.com")
        )
        let second = MonitoredWorkflow(
            id: UUID(uuidString: "4B92A697-36F9-40FC-A334-26D59A195EB3")!,
            displayName: "Second",
            owner: "octo-org",
            repo: "second",
            branch: "release",
            workflowFile: ".github/workflows/release.yml",
            siteURL: nil
        )

        try store.saveWorkflows([first, second])

        XCTAssertEqual(try store.loadWorkflows(), [first, second])
    }

    func testFileBackedStoreThrowsCorruptedFileError() throws {
        let fileURL = temporaryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL, options: .atomic)

        let store = FileBackedMonitoredWorkflowStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.loadWorkflows()) { error in
            XCTAssertEqual(
                error.localizedDescription,
                MonitoredWorkflowStoreError.corruptedFile(fileURL).localizedDescription
            )
        }
    }

    func testDraftValidationRejectsDuplicateWorkflow() {
        let existing = MonitoredWorkflow(
            id: UUID(uuidString: "4187C975-F7E3-4527-93DA-6B5276D5D7CF")!,
            displayName: "Existing",
            owner: "octo-org",
            repo: "dashboard",
            branch: "main",
            workflowFile: "deploy.yml",
            siteURL: nil
        )
        let duplicateDraft = MonitoredWorkflowDraft(
            displayName: "Duplicate",
            owner: "octo-org",
            repo: "dashboard",
            branch: "main",
            workflowFile: "deploy.yml",
            siteURLText: ""
        )

        XCTAssertThrowsError(try duplicateDraft.validated(existingWorkflows: [existing])) { error in
            XCTAssertEqual(error as? MonitoredWorkflowValidationError, .duplicateWorkflow)
        }
    }

    func testDraftValidationRejectsInvalidSiteURL() {
        let draft = MonitoredWorkflowDraft(
            displayName: "Example",
            owner: "octo-org",
            repo: "dashboard",
            branch: "main",
            workflowFile: "deploy.yml",
            siteURLText: "http://insecure.example.com"
        )

        XCTAssertThrowsError(try draft.validated(existingWorkflows: [])) { error in
            XCTAssertEqual(error as? MonitoredWorkflowValidationError, .invalidSiteURL)
        }
    }

    private func temporaryFileURL() -> URL {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: baseDirectory)
        }
        return baseDirectory.appendingPathComponent("monitored-workflows.json")
    }
}
