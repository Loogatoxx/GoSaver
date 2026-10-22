import AppKit
import GoSaverCore

/// Traduit les noms techniques en noms lisibles :
/// « 6N38VWS5BX.ru.keepcoder.Telegram » → « Telegram ».
@MainActor
enum PlaceNames {
    private static var cache: [String: String] = [:]

    static func display(_ place: Place) -> String {
        let raw = place.name
        // Enclave « Caches — com.utmapp.UTM » : on traduit le propriétaire.
        if let dash = raw.range(of: " — ") {
            return raw[..<dash.lowerBound] + " — " + display(raw: String(raw[dash.upperBound...]))
        }
        return display(raw: raw)
    }

    static func display(raw: String) -> String {
        if let hit = cache[raw] { return hit }
        let name = resolve(raw) ?? fallback(raw)
        cache[raw] = name
        return name
    }

    /// Cherche une appli installée dont l'identifiant correspond, en retirant
    /// au besoin le préfixe d'équipe et les suffixes (« .ShipIt », « .helper »).
    private static func resolve(_ raw: String) -> String? {
        var parts = raw.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        // Préfixe d'équipe Apple : 10 caractères majuscules/chiffres.
        if parts[0].count == 10, parts[0].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            parts.removeFirst()
        }
        while parts.count >= 2 {
            let id = parts.joined(separator: ".")
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return withoutAppSuffix(FileManager.default.displayName(atPath: url.path))
            }
            parts.removeLast()
        }
        return nil
    }

    /// Nom lisible quand aucune appli ne correspond.
    private static func fallback(_ raw: String) -> String {
        // Conteneur identifié par un UUID (8-4-4-4-12 caractères hexadécimaux) : rien de lisible.
        if raw.count == 36, raw.split(separator: "-").map(\.count) == [8, 4, 4, 4, 12] {
            return "Conteneur anonyme"
        }
        return withoutAppSuffix(raw)
    }

    /// Retire « .app » seulement en fin de nom (« com.apple.geod » doit rester intact).
    private static func withoutAppSuffix(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
