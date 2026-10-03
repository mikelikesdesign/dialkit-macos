import XCTest
@testable import DialkitmacOSCLI

final class DialKitCLITests: XCTestCase {
    func testInstallHelpIsSuccessfulAndPrintedOnce() throws {
        for option in ["-h", "--help"] {
            let output = try DialKitCLI.installOutput(arguments: [option])
            XCTAssertEqual(output, DialKitCLI.installHelp)
            XCTAssertEqual(output.components(separatedBy: "Usage:").count - 1, 1)
        }
    }

    func testInstallGuideEscapesSwiftStringLiterals() throws {
        let name = "My \"App\" \\(danger)\nNext\tLine"
        let options = try InstallOptions(arguments: ["--project", "Demo.xcodeproj", "--target", "Demo", "--app-name", name])
        let guide = DialKitCLI.installGuide(for: options)
        XCTAssertTrue(guide.contains("appName: " + String(reflecting: name) + ")"))
        XCTAssertTrue(guide.contains("appName: " + String(reflecting: name + " Preview") + ")"))
        XCTAssertFalse(guide.contains("appName: \"" + name + "\""))
    }

    func testOnlyNativeTargetNamesAreAccepted() throws {
        let project = Data("""
        // !$*UTF8*$!
        { objects = {
            A = { isa = PBXNativeTarget; name = "My App"; productName = DifferentProduct; };
            B = { isa = PBXGroup; name = Products; };
            C = { isa = PBXFileReference; name = "Fake Target"; };
            D = { isa = PBXAggregateTarget; name = Aggregate; };
        }; }
        """.utf8)
        XCTAssertEqual(try DialProjectTargets.names(in: project), ["My App"])
    }

    func testDemoProjectHasOnlyItsRealTarget() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Examples/DialKitDemo/DialKitDemo.xcodeproj/project.pbxproj"))
        XCTAssertEqual(try DialProjectTargets.names(in: data), ["DialKitDemo"])
    }

    func testInvalidProjectStructureIsRejected() {
        XCTAssertThrowsError(try DialProjectTargets.names(in: Data("{}".utf8)))
        XCTAssertThrowsError(try DialProjectTargets.names(in: Data("not a plist".utf8)))
    }
}
