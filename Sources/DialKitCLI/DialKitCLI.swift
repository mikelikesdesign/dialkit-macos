import Foundation
import Darwin

@main
enum DialKitCLI {
    static func main() {
        dispatch(arguments: Array(CommandLine.arguments.dropFirst()))
    }

    static func dispatch(arguments: [String]) -> Never {
        guard let command = arguments.first else {
            print(help)
            exit(EXIT_SUCCESS)
        }

        switch command {
        case "run":
            runInspector(arguments: Array(arguments.dropFirst()))
        case "install":
            install(arguments: Array(arguments.dropFirst()))
        case "-h", "--help", "help":
            print(help)
            exit(EXIT_SUCCESS)
        default:
            fputs("Unknown command: \(command)\n\n\(help)\n", stderr)
            exit(EX_USAGE)
        }
    }

    private static func runInspector(arguments: [String]) -> Never {
        var passthrough = arguments
        if passthrough.first == "--" {
            passthrough.removeFirst()
        }

        let command = ["swift", "run", "dialkit-macos"] + passthrough
        let result: Int32 = command.withCStringArray { argv in
            execvp(argv[0], argv)
        }
        _ = result

        let message = String(cString: strerror(errno))
        fputs("Could not run dialkit-macos: \(message)\n", stderr)
        exit(EX_UNAVAILABLE)
    }

    private static func install(arguments: [String]) -> Never {
        do {
            print(try installOutput(arguments: arguments))
            exit(EXIT_SUCCESS)
        } catch {
            fputs("\(error.localizedDescription)\n\n\(installHelp)\n", stderr)
            exit(EX_USAGE)
        }
    }

    static func installOutput(arguments: [String]) throws -> String {
        do {
            let options = try InstallOptions(arguments: arguments)
            try validateInstallOptions(options)
            return installGuide(for: options)
        } catch InstallRequest.help {
            return installHelp
        }
    }

    private static func validateInstallOptions(_ options: InstallOptions) throws {
        let projectURL = URL(fileURLWithPath: options.projectPath)
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            throw CLIError("Project does not exist: \(options.projectPath)")
        }

        let pbxprojURL = projectURL.appendingPathComponent("project.pbxproj")
        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else {
            throw CLIError("Expected an .xcodeproj bundle with project.pbxproj: \(options.projectPath)")
        }

        let targets = try DialProjectTargets.names(in: Data(contentsOf: pbxprojURL))
        guard targets.contains(options.targetName) else {
            throw CLIError("Could not find target named \(options.targetName) in \(options.projectPath)")
        }
    }

    static func installGuide(for options: InstallOptions) -> String {
        let appName = options.appName ?? options.targetName

        return """
        Dialkit macOS package-only install preflight passed.

        Project: \(options.projectPath)
        Target: \(options.targetName)

        Xcode setup:
        1. Add this repository as a Swift Package dependency.
        2. Link these package products to the \(options.targetName) app target:
           - DialkitmacOS
           - DialkitmacOSAgent
        3. Start the agent only in debug builds:

        import SwiftUI

        #if DEBUG
        import DialkitmacOSAgent
        #endif

        @main
        struct \(sanitizedTypeName(from: appName))App: App {
            init() {
                #if DEBUG
                DialKitAgent.shared.start(appName: \(String(reflecting: appName)))
                #endif
            }

            var body: some Scene {
                WindowGroup {
                    ContentView()
                }
            }
        }

        Preview setup:

        #Preview {
            ContentView()
                .task {
                    #if DEBUG
                    DialKitAgent.shared.start(appName: \(String(reflecting: appName + " Preview")))
                    #endif
                }
        }

        Run the standalone inspector from this package:

        swift run dialkit run

        This command does not mutate the Xcode project yet. It validates the target and prints the package-only wiring so release builds stay clean.
        """
    }

    private static func sanitizedTypeName(from value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        let joined = String(scalars)
        guard let first = joined.unicodeScalars.first, CharacterSet.letters.contains(first) else {
            return "DialKit"
        }
        return joined
    }

    private static let help = """
    Dialkit macOS command line helper

    Usage:
      swift run dialkit run
      swift run dialkit install --project MyApp.xcodeproj --target MyApp

    Commands:
      run       Build and run the standalone macOS inspector with SwiftPM.
      install   Validate an Xcode project target and print the debug-only agent wiring.

    No separate Dialkit macOS.app download is required.
    """

    static let installHelp = """
    Usage:
      swift run dialkit install --project MyApp.xcodeproj --target MyApp [--app-name "My App"]
    """
}

private extension Array where Element == String {
    func withCStringArray<Result>(
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
    ) rethrows -> Result {
        let cStrings = map { strdup($0) }
        defer {
            for string in cStrings {
                free(string)
            }
        }

        var pointers = cStrings
        pointers.append(nil)

        return try pointers.withUnsafeMutableBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }
}

enum InstallRequest: Error { case help }

struct InstallOptions {
    let projectPath: String
    let targetName: String
    let appName: String?

    init(arguments: [String]) throws {
        var projectPath: String?
        var targetName: String?
        var appName: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--project":
                projectPath = try Self.value(after: argument, in: arguments, index: &index)
            case "--target":
                targetName = try Self.value(after: argument, in: arguments, index: &index)
            case "--app-name":
                appName = try Self.value(after: argument, in: arguments, index: &index)
            case "-h", "--help":
                throw InstallRequest.help
            default:
                throw CLIError("Unknown install option: \(argument)")
            }
        }

        guard let projectPath else {
            throw CLIError("Missing required option: --project")
        }

        guard let targetName else {
            throw CLIError("Missing required option: --target")
        }

        self.projectPath = projectPath
        self.targetName = targetName
        self.appName = appName
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("Missing value for \(option)")
        }

        index += 2
        return arguments[valueIndex]
    }
}

private struct CLIError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
