import Foundation

/// Désinstallation : une appli et ses restes, à la corbeille de macOS (récupérable jusqu'au vidage).
///
/// Ce module ne fait que *préparer* la liste, en lecture seule. La mise à la corbeille elle-même
/// passe par l'appli (NSWorkspace), comme un glisser vers la corbeille dans le Finder.
public struct Uninstaller: Sendable {
    /// Ce qu'on va retirer.
    public struct Plan: Sendable, Equatable {
        public let apps: [URL]
        /// L'emplacement à mettre à la corbeille pour l'appli (le .app, ou le dossier qui la contient).
        public let bundleLocation: URL
        public let bundleIDs: [String]
        public let names: [String]
        /// Restes dans la bibliothèque de l'utilisateur : données, caches, préférences…
        public let leftovers: [Leftover]
        /// Désinstalleur fourni par l'éditeur, à préférer s'il existe.
        public let vendorUninstaller: URL?
        /// L'appli appartient à l'administrateur : il faudra le mot de passe (Finder ou désinstalleur de l'éditeur).
        public let needsAdmin: Bool

        public var bytes: Int64 { Drainer.allocatedSize(of: bundleLocation) + leftovers.reduce(0) { $0 + $1.bytes } }
    }

    public struct Leftover: Sendable, Equatable, Identifiable {
        public var id: String { url.path }
        public let url: URL
        public let label: String
        public let bytes: Int64
    }

    public enum Refusal: Error, Equatable, LocalizedError {
        case notAnApp, appleApp(String), running(String)
        public var errorDescription: String? {
            switch self {
            case .notAnApp: "Ce n’est pas une appli."
            case .appleApp(let n): "« \(n) » fait partie de macOS : on ne la désinstalle pas."
            case .running(let n): "« \(n) » est ouverte. Quitte-la, puis recommence."
            }
        }
    }

    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home.standardizedFileURL }

    /// Prépare la désinstallation de `location` : un .app, ou un dossier de /Applications qui en contient.
    /// - Parameter running: identifiants des applis ouvertes.
    public func plan(for location: URL, running: Set<String> = []) throws -> Plan {
        let fm = FileManager.default
        let apps: [URL]
        if location.pathExtension == "app" {
            apps = [location]
        } else {
            apps = ((try? fm.contentsOfDirectory(at: location, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
        }
        // Les désinstalleurs de l'éditeur ne comptent pas comme applis à retirer.
        let realApps = apps.filter { !Self.isUninstaller($0) }
        guard !realApps.isEmpty else { throw Refusal.notAnApp }

        var ids: [String] = [], names: [String] = []
        for app in realApps {
            let name = app.deletingPathExtension().lastPathComponent
            let id = Bundle(url: app)?.bundleIdentifier ?? ""
            if id.hasPrefix("com.apple.") || location.path.hasPrefix("/System/") { throw Refusal.appleApp(name) }
            if !id.isEmpty, running.contains(id) { throw Refusal.running(name) }
            if !id.isEmpty { ids.append(id) }
            names.append(name)
        }

        let owner = (try? fm.attributesOfItem(atPath: location.path)[.ownerAccountName]) as? String
        return Plan(apps: realApps, bundleLocation: location, bundleIDs: ids, names: names,
                    leftovers: leftovers(ids: ids, names: names),
                    vendorUninstaller: apps.first(where: Self.isUninstaller),
                    needsAdmin: owner == "root" || !fm.isWritableFile(atPath: location.deletingLastPathComponent().path))
    }

    static func isUninstaller(_ app: URL) -> Bool {
        let name = app.lastPathComponent.lowercased()
        return name.contains("uninstall") || name.contains("désinstall") || name.contains("desinstall")
    }

    /// Restes connus : uniquement ce qui porte EXACTEMENT l'identifiant de l'appli
    /// (ou exactement son nom pour les dossiers de données et de caches). Jamais d'approximation.
    func leftovers(ids: [String], names: [String]) -> [Leftover] {
        let library = home.appendingPathComponent("Library")
        var candidates: [(String, String)] = []   // (chemin relatif à ~/Library, libellé)
        for id in ids {
            candidates += [
                ("Application Support/\(id)", "Données"),
                ("Caches/\(id)", "Caches"),
                ("Containers/\(id)", "Conteneur"),
                ("Preferences/\(id).plist", "Préférences"),
                ("Saved Application State/\(id).savedState", "État des fenêtres"),
                ("Logs/\(id)", "Journaux"),
                ("HTTPStorages/\(id)", "Données web"),
                ("WebKit/\(id)", "Données web"),
                ("Application Scripts/\(id)", "Scripts"),
                ("LaunchAgents/\(id).plist", "Lancement automatique"),
            ]
        }
        for name in names {
            candidates += [("Application Support/\(name)", "Données"), ("Caches/\(name)", "Caches"), ("Logs/\(name)", "Journaux")]
        }
        // Conteneurs partagés : « ÉQUIPE.identifiant » (ex. 6N38VWS5BX.ru.keepcoder.Telegram), suffixe exact.
        let groups = library.appendingPathComponent("Group Containers")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: groups.path)) ?? [] {
            if ids.contains(where: { !$0.isEmpty && name.hasSuffix("." + $0) && name.split(separator: ".").first?.count == 10 }) {
                candidates.append(("Group Containers/\(name)", "Données partagées"))
            }
        }
        var seen = Set<String>()
        return candidates.compactMap { relative, label in
            let url = library.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path), seen.insert(url.path).inserted else { return nil }
            return Leftover(url: url, label: label, bytes: Drainer.allocatedSize(of: url))
        }
    }

    /// Vrai si l'emplacement ressemble à une appli installée (pour afficher « Désinstaller »).
    public static func looksLikeApp(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let inApplications = path.hasPrefix("/Applications/") || path.contains("/Applications/")
        guard inApplications else { return false }
        if url.pathExtension == "app" { return true }
        let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return children.contains { $0.hasSuffix(".app") }
    }
}
