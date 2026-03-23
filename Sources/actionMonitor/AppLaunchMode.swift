import Foundation

enum AppLaunchMode: Equatable {
    case live
    case demo

    init(arguments: [String] = CommandLine.arguments) {
        if arguments.contains("--demo") {
            self = .demo
        } else {
            self = .live
        }
    }
}
