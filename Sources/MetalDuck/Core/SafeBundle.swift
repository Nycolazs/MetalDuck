import Foundation

/// Provides a crash-safe alternative to `Bundle.module`.
///
/// The auto-generated `Bundle.module` accessor calls `fatalError()` when the
/// SPM resource bundle cannot be found at runtime (e.g. when the app is
/// launched outside the build directory or the bundle layout differs).
/// This extension tries the same lookup paths but returns `nil` instead of
/// crashing, allowing callers to fall back gracefully.
extension Bundle {
    /// The SPM resource bundle, or `nil` when the bundle is unavailable.
    static let safeModule: Bundle? = {
        let bundleName = "MetalDuck_MetalDuck"

        let candidates = [
            // When running from a built .app bundle.
            Bundle.main.resourceURL,
            // Next to the executable (SPM build tree).
            Bundle.main.bundleURL,
            // Common SPM paths relative to the executable.
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
        ]

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundlePath, let bundle = Bundle(url: bundlePath) {
                return bundle
            }
        }

        return nil
    }()
}
