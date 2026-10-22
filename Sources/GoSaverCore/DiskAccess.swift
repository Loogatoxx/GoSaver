import Foundation

/// L'« accès complet au disque » : la permission macOS (TCC) qui laisse une appli lire
/// les dossiers protégés (Mail, Safari, corbeille, conteneurs d'autres applis…).
///
/// macOS ne fournit aucune API pour demander « ai-je cette permission ? ». La méthode
/// usuelle : tenter de *lister* un dossier protégé. On ne lit jamais le contenu des fichiers.
public enum DiskAccess {
    public enum Status: Sendable, Equatable {
        case granted
        case denied
        /// Aucun dossier témoin n'existe : impossible de savoir (rare).
        case unknown
    }

    /// Dossiers témoins, protégés sur tous les Mac récents.
    public static func probes(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ["Library/Safari", "Library/Mail", ".Trash", "Library/Containers/com.apple.Safari"]
            .map { home.appendingPathComponent($0) }
    }

    public static func status(probes: [URL] = probes()) -> Status {
        var sawOne = false
        for probe in probes where FileManager.default.fileExists(atPath: probe.path) {
            sawOne = true
            if (try? FileManager.default.contentsOfDirectory(atPath: probe.path)) != nil { return .granted }
        }
        return sawOne ? .denied : .unknown
    }

    /// Adresse qui ouvre directement Réglages Système › Confidentialité › Accès complet au disque.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
