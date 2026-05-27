import Foundation

/// Lightweight localization engine that loads translations from standard
/// `*.lproj/Localizable.strings` resource files bundled with the app.
///
/// Falls back gracefully: specific language → English → raw key.
public struct Localization: Sendable {
    public static let shared = Localization()

    // MARK: - Cached bundles

    /// Lazily cached per-language sub-bundles, keyed by language code.
    private let bundleCache: [String: Bundle]

    private init() {
        var cache: [String: Bundle] = [:]
        let supportedCodes = ["en", "ru", "uk", "zh", "vi",
                              "es", "fr", "de", "it", "pt",
                              "ja", "ko", "ar", "hi"]

        for code in supportedCodes {
            // Bundle.module points to the SPM resource bundle at runtime.
            if let url = Bundle.module.url(forResource: "Localizable",
                                           withExtension: "strings",
                                           subdirectory: "\(code).lproj"),
               let bundle = Bundle(url: url.deletingLastPathComponent()) {
                cache[code] = bundle
            }
        }
        bundleCache = cache
    }

    // MARK: - Public API

    /// Returns the localised string for `key` in the given language code.
    /// Falls back to English, then to the raw key if no translation exists.
    public func translate(_ key: String, to langCode: String) -> String {
        let code = langCode.lowercased()

        // 1. Try the requested language bundle
        if let bundle = bundleCache[code] {
            let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
            if value != key { return value }
        }

        // 2. Fall back to English
        if code != "en", let enBundle = bundleCache["en"] {
            let value = enBundle.localizedString(forKey: key, value: nil, table: "Localizable")
            if value != key { return value }
        }

        // 3. Return the key itself as last resort
        return key
    }
}
