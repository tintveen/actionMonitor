import Foundation

protocol MonitoredWorkflowStore: Sendable {
    func loadWorkflows() throws -> [MonitoredWorkflow]
    func saveWorkflows(_ workflows: [MonitoredWorkflow]) throws
    func resetWorkflows() throws
}

enum MonitoredWorkflowStoreError: LocalizedError {
    case corruptedFile(URL)
    case failedToLoad(URL, String)
    case failedToCreateDirectory(URL, String)
    case failedToSave(URL, String)

    var errorDescription: String? {
        switch self {
        case .corruptedFile(let url):
            return "The workflow configuration at \(url.lastPathComponent) is invalid. actionMonitor started with an empty list so you can save a fresh configuration."
        case .failedToLoad(let url, let message):
            return "Could not load workflows from \(url.lastPathComponent): \(message)"
        case .failedToCreateDirectory(let url, let message):
            return "Could not create the workflow settings folder at \(url.path): \(message)"
        case .failedToSave(let url, let message):
            return "Could not save workflows to \(url.lastPathComponent): \(message)"
        }
    }
}

struct FileBackedMonitoredWorkflowStore: MonitoredWorkflowStore {
    let fileURL: URL

    init(fileURL: URL = FileBackedMonitoredWorkflowStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    static func defaultFileURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "actionMonitor", directoryHint: .isDirectory)
            .appending(path: "monitored-workflows.json", directoryHint: .notDirectory)
    }

    func loadWorkflows() throws -> [MonitoredWorkflow] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode([MonitoredWorkflow].self, from: data)
        } catch is DecodingError {
            throw MonitoredWorkflowStoreError.corruptedFile(fileURL)
        } catch {
            throw MonitoredWorkflowStoreError.failedToLoad(fileURL, error.localizedDescription)
        }
    }

    func saveWorkflows(_ workflows: [MonitoredWorkflow]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw MonitoredWorkflowStoreError.failedToCreateDirectory(
                directoryURL,
                error.localizedDescription
            )
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(workflows)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw MonitoredWorkflowStoreError.failedToSave(fileURL, error.localizedDescription)
        }
    }

    func resetWorkflows() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw MonitoredWorkflowStoreError.failedToSave(fileURL, error.localizedDescription)
        }
    }
}

final class InMemoryMonitoredWorkflowStore: MonitoredWorkflowStore, @unchecked Sendable {
    private var workflows: [MonitoredWorkflow]

    init(initialWorkflows: [MonitoredWorkflow] = []) {
        workflows = initialWorkflows
    }

    func loadWorkflows() throws -> [MonitoredWorkflow] {
        workflows
    }

    func saveWorkflows(_ workflows: [MonitoredWorkflow]) throws {
        self.workflows = workflows
    }

    func resetWorkflows() throws {
        workflows = []
    }
}
