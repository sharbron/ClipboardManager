import SwiftUI
import UniformTypeIdentifiers

// MARK: - Preferences Document


struct PreferencesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var settings: [String: Any] = [:]

    init() {
        // Export only the user-facing preferences. Dumping the whole persistent domain would
        // carry internal state into the file, and any non-JSON value in there (Data, Date)
        // would make serialisation fail outright.
        let store = UserDefaults.standard
        settings = Preferences.importable.reduce(into: [:]) { result, key in
            result[key] = store.object(forKey: key)
        }
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.settings = json
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
        return FileWrapper(regularFileWithContents: data)
    }
}
