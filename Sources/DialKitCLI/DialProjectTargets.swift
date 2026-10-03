import Foundation

enum DialProjectTargets {
    static func names(in projectData: Data) throws -> Set<String> {
        guard let project = try PropertyListSerialization.propertyList(from: projectData, format: nil) as? [String: Any],
              let objects = project["objects"] as? [String: [String: Any]] else {
            throw NSError(domain: "DialKitCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Xcode project structure."])
        }
        return Set(objects.values.compactMap { object in
            guard object["isa"] as? String == "PBXNativeTarget" else { return nil }
            return object["name"] as? String
        })
    }
}
