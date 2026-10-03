import XCTest
@testable import DialkitmacOSCLI

final class DialKitCLITests: XCTestCase {
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
