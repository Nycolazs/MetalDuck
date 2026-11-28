import Foundation

/// Provides a crash-safe alternative to `Bundle.module`.
///
/// The auto-generated `Bundle.module` accessor calls `fatalError()` when the
/// SPM resource bundle cannot be found at runtime (e.g. when the app is
/// launched outside the build directory or the bundle layout differs).
/// This extension tries the same lookup paths but returns `nil` instead of
/// crashing, so the caller can report what is missing.
extension Bundle {
    /// The SPM resource bundle, or `nil` when the bundle is unavailable.
    static let safeModule: Bundle? = {
        let bundleName = "MetalDuck_MetalDuckKit.bundle"

        var candidates: [URL?] = [
            // When running from a built .app bundle.
            Bundle.main.resourceURL,
            // Next to the executable (SPM build tree).
            Bundle.main.bundleURL,
            // Common SPM paths relative to the executable.
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
        ]
        // Under `swift test` the main bundle is the test runner, and the resources sit
        // inside or beside the test bundle instead.
        for bundle in Bundle.allBundles + [Bundle(for: BundleToken.self)] {
            candidates.append(bundle.resourceURL)
            candidates.append(bundle.bundleURL.deletingLastPathComponent())
        }

        for case let candidate? in candidates {
            if let bundle = Bundle(url: candidate.appendingPathComponent(bundleName)) {
                return bundle
            }
        }

        return nil
    }()
}

/// Lives in this module's binary, so `Bundle(for:)` finds whatever that binary is part of.
private final class BundleToken {}
