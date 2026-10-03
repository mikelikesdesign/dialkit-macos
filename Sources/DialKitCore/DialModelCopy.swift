import Foundation

/// Codable round-tripping separates reference models (including references
/// nested inside structs) when capturing editable base values and presets.
package func dialCopyModel<Model: Codable>(_ model: Model) -> Model {
    // Plain value models already have copy semantics. Preserve properties they
    // intentionally exclude from CodingKeys and avoid encoding on every edit.
    func containsReference(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .class { return true }
        return mirror.children.contains { containsReference($0.value) }
    }
    guard containsReference(model) else { return model }
    let encoder = JSONEncoder()
    encoder.nonConformingFloatEncodingStrategy = .convertToString(
        positiveInfinity: "DialKit.infinity", negativeInfinity: "DialKit.-infinity", nan: "DialKit.nan"
    )
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
        positiveInfinity: "DialKit.infinity", negativeInfinity: "DialKit.-infinity", nan: "DialKit.nan"
    )
    do {
        return try decoder.decode(Model.self, from: encoder.encode(model))
    } catch {
        preconditionFailure("DialKit models must support Codable round-tripping: \(error)")
    }
}
