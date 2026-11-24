import AppKit

/// The user's own copy of `Lossless.dll` from Lossless Scaling on Steam.
///
/// MetalDuck does not ship the file. The user downloads it with Steam
/// (`download_depot 993090 993091` in the Steam console) and imports it here.
/// The imported copy lives in `~/Library/Application Support/MetalDuck/`.
enum LosslessScalingLibrary {
    static let steamAppID = 993090
    static let steamDepotID = 993091
    static let fileName = "Lossless.dll"
    static let steamConsoleURL = URL(string: "steam://open/console")!
    static var downloadCommand: String { "download_depot \(steamAppID) \(steamDepotID)" }

    enum ImportError: LocalizedError {
        case unreadable
        case wrongFile(String)
        case notWindowsBinary

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "The file could not be read."
            case .wrongFile(let name):
                return "\(name) is not the frame generation library. Choose Lossless.dll from the same folder."
            case .notWindowsBinary:
                return "This is not a Windows DLL. Choose the Lossless.dll that Steam downloaded."
            }
        }
    }

    static var installedURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MetalDuck", isDirectory: true).appendingPathComponent(fileName)
    }

    /// Size in bytes of the imported copy, or `nil` when none is imported.
    static var installedSize: Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: installedURL.path)
        return (attributes?[.size] as? NSNumber)?.intValue
    }

    /// Where `download_depot` leaves the depot in the macOS Steam client, if it exists.
    static var steamDownloadFolder: URL? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent(
            "Steam/Steam.AppBundle/Steam/Contents/MacOS/steamapps/content/app_\(steamAppID)/depot_\(steamDepotID)",
            isDirectory: true
        )
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    /// Checks that `source` is a PE image and copies it over any earlier import.
    static func importFile(from source: URL) throws {
        guard source.lastPathComponent.caseInsensitiveCompare(fileName) == .orderedSame else {
            throw ImportError.wrongFile(source.lastPathComponent)
        }
        guard let handle = try? FileHandle(forReadingFrom: source) else { throw ImportError.unreadable }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4096), isPortableExecutable(header) else {
            throw ImportError.notWindowsBinary
        }

        let fileManager = FileManager.default
        let destination = installedURL
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    /// Opens the Steam console. Returns `false` when no app handles `steam://`.
    @MainActor
    @discardableResult
    static func openSteamConsole() -> Bool {
        guard NSWorkspace.shared.urlForApplication(toOpen: steamConsoleURL) != nil else { return false }
        return NSWorkspace.shared.open(steamConsoleURL)
    }

    /// "MZ" DOS header whose `e_lfanew` points at a "PE\0\0" signature.
    private static func isPortableExecutable(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 0x40, bytes[0] == 0x4D, bytes[1] == 0x5A else { return false }
        let offset = Int(bytes[0x3C]) | Int(bytes[0x3D]) << 8 | Int(bytes[0x3E]) << 16 | Int(bytes[0x3F]) << 24
        guard offset >= 0x40, offset + 4 <= bytes.count else { return false }
        return bytes[offset..<offset + 4].elementsEqual([0x50, 0x45, 0x00, 0x00])
    }
}
