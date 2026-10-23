import Foundation
import CryptoKit

/// Une ruine : ce qui reste sur le disque sans plus servir, ou dont on ignore l'origine.
public struct Ruin: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        /// Données d'une appli qui n'est plus installée.
        case orphanAppData
        /// Copie à l'identique d'un autre fichier.
        case duplicate
        /// Installeur (.dmg, .pkg) d'une appli déjà installée.
        case usedInstaller
        /// Téléchargement jamais terminé.
        case partialDownload
        /// Fichier isolé dont l'origine n'est pas évidente.
        case stray

        public var label: String {
            switch self {
            case .orphanAppData: "Données d’appli disparue"
            case .duplicate: "Doublon"
            case .usedInstaller: "Installeur déjà utilisé"
            case .partialDownload: "Téléchargement interrompu"
            case .stray: "Fichier d’origine inconnue"
            }
        }
    }

    /// Ce que l'expertise recommande (le tampon de la fiche).
    public enum Verdict: String, Sendable {
        /// Sûr : peut partir au Lazaret (30 jours pour changer d'avis).
        case isolate
        /// À regarder : l'expertise ne tranche pas seule.
        case examine

        public var stamp: String { self == .isolate ? "À ISOLER" : "À EXAMINER" }
    }

    public var id: String { url.path }
    public let url: URL
    public let kind: Kind
    public let verdict: Verdict
    public let bytes: Int64
    /// Une phrase qui résume l'enquête (« Image disque de 30 Mo téléchargée depuis… »).
    public let summary: String
    /// Les indices qui justifient le verdict.
    public let reasons: [String]
    public let clues: Clues
}

/// Une appli installée, vue par l'expertise (testable sans AppKit).
public struct InstalledApp: Sendable, Equatable {
    public let bundleID: String
    public let name: String
    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }

    /// Applis de /Applications, ~/Applications et leurs sous-dossiers (lecture des Info.plist).
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for root in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"),
                     URL(fileURLWithPath: "/System/Applications")] {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let url = enumerator?.nextObject() as? URL {
                if enumerator?.level ?? 0 > 2 { enumerator?.skipDescendants() }
                guard url.pathExtension == "app", let bundle = Bundle(url: url) else { continue }
                apps.append(InstalledApp(bundleID: bundle.bundleIdentifier ?? "",
                                         name: url.deletingPathExtension().lastPathComponent))
            }
        }
        return apps
    }
}

/// L'archéologue : fouille les endroits où s'accumulent les ruines et rend une expertise par trouvaille.
/// Lecture seule ; ne déplace ni ne supprime rien.
public struct Archaeologist: Sendable {
    public let home: URL
    public let apps: [InstalledApp]
    public let now: Date
    /// Une donnée d'appli n'est « disparue » que si l'appli manque ET qu'elle n'a pas bougé depuis ce délai.
    public var orphanAge: TimeInterval = 90 * 86_400

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                apps: [InstalledApp] = InstalledApp.scan(), now: Date = Date()) {
        self.home = home.standardizedFileURL
        self.apps = apps
        self.now = now
    }

    public func excavate() -> [Ruin] {
        // Du plus précis au plus général : une trouvaille qui relève de deux familles
        // (un téléchargement interrompu en double) garde la plus précise.
        var ruins = orphanAppData() + installersAndPartials() + duplicates() + strays()
        // Une même trouvaille ne compte qu'une fois.
        var seen = Set<String>()
        ruins = ruins.filter { seen.insert($0.id).inserted }
        return ruins.sorted { ($0.verdict == .isolate ? 0 : 1, -$0.bytes) < ($1.verdict == .isolate ? 0 : 1, -$1.bytes) }
    }

    // MARK: - Données d'applis disparues

    /// Dossiers d'Application Support qui ne servent plus et que l'on ne doit jamais signaler.
    static let sharedSupportNames: Set<String> = [
        "CrashReporter", "AddressBook", "Knowledge", "CloudDocs", "MobileSync", "iCloud", "CallHistoryDB",
        "CallHistoryTransactions", "DiskImages", "FileProvider", "Animoji", "AccessibilityBundles", "Dock",
        "SyncServices", "icdd", "networkserviceproxy", "default.store", "ProtectedCloudStorage", "videosubscriptionsd",
        "Caches", "Code", "pipx", "virtualenv", "fish", "mise", "uv", "deno", "Google", "Microsoft",
    ]

    func orphanAppData() -> [Ruin] {
        let support = home.appendingPathComponent("Library/Application Support")
        let children = (try? FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil,
                                                                     options: [.skipsHiddenFiles])) ?? []
        return children.compactMap { folder -> Ruin? in
            let name = folder.lastPathComponent
            guard !name.hasPrefix("com.apple."), !Self.sharedSupportNames.contains(name),
                  owner(of: name) == nil else { return nil }
            let latest = Self.latestChange(in: folder)
            guard let latest, now.timeIntervalSince(latest) > orphanAge else { return nil }
            let clues = Clues.gather(folder)
            guard clues.bytes > 1_000_000 else { return nil }
            let days = Int(now.timeIntervalSince(latest) / 86_400)
            return Ruin(url: folder, kind: .orphanAppData, verdict: .isolate, bytes: clues.bytes,
                        summary: "Données de « \(Self.readable(name)) », une appli qui n’est plus installée ; personne n’y a touché depuis \(days) jours.",
                        reasons: ["Aucune appli installée ne correspond à « \(name) ».",
                                  "Dernière modification il y a \(days) jours."],
                        clues: clues)
        }
    }

    /// L'appli installée à qui appartient un dossier, s'il y en a une.
    /// Prudent : au moindre rapprochement plausible, on considère que l'appli existe.
    func owner(of folderName: String) -> InstalledApp? {
        let folder = folderName.lowercased()
        let folderWords = Set(Placement.tokens(folderName).filter { $0.count >= 4 })
        return apps.first { app in
            let id = app.bundleID.lowercased()
            if !id.isEmpty, folder == id || folder.hasPrefix(id) || id.hasSuffix("." + folder) || id.contains(folder) { return true }
            let appWords = Placement.tokens(app.name).filter { $0.count >= 4 }
            if !folderWords.isDisjoint(with: appWords) { return true }
            // « BraveSoftware » ↔ « Brave Browser » : un mot de l'appli au début du nom du dossier.
            return appWords.contains { folder.hasPrefix($0) }
        }
    }

    /// Date de la modification la plus récente dans un dossier (deux niveaux suffisent).
    static func latestChange(in folder: URL) -> Date? {
        var latest = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                        options: [.skipsHiddenFiles])
        var count = 0
        while let item = enumerator?.nextObject() as? URL, count < 2000 {
            count += 1
            if enumerator?.level ?? 0 > 2 { enumerator?.skipDescendants() }
            if let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               date > (latest ?? .distantPast) { latest = date }
        }
        return latest
    }

    // MARK: - Doublons

    /// Copies à l'identique dans les dossiers où l'on télécharge et range en vrac.
    func duplicates() -> [Ruin] {
        var bySize: [Int64: [URL]] = [:]
        for root in ["Downloads", "Desktop", "Documents"].map({ home.appendingPathComponent($0) }) {
            for file in Self.files(in: root) {
                let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                if size >= 50_000 { bySize[size, default: []].append(file) }
            }
        }
        var ruins: [Ruin] = []
        for (_, group) in bySize where group.count > 1 {
            var byHash: [String: [URL]] = [:]
            for file in group { if let hash = Self.hash(file) { byHash[hash, default: []].append(file) } }
            for (_, same) in byHash where same.count > 1 {
                // L'original : le nom sans « (1) », « -2 », « copie » ; à défaut, le plus ancien.
                let original = same.min { Self.copyScore($0) != Self.copyScore($1) ? Self.copyScore($0) < Self.copyScore($1)
                                                                                  : Self.created($0) < Self.created($1) }!
                for copy in same where copy != original {
                    let clues = Clues.gather(copy)
                    ruins.append(Ruin(url: copy, kind: .duplicate, verdict: .isolate, bytes: clues.bytes,
                                      summary: "Copie exacte de « \(original.lastPathComponent) » (même contenu, octet pour octet).",
                                      reasons: ["Contenu identique à \(original.path.replacingOccurrences(of: home.path, with: "~")).",
                                                "L’original reste en place."],
                                      clues: clues))
                }
            }
        }
        return ruins
    }

    /// Plus le nom ressemble à une copie, plus le score est élevé.
    static func copyScore(_ url: URL) -> Int {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        if stem.range(of: #"\(\d+\)$"#, options: .regularExpression) != nil { return 2 }
        if stem.range(of: #"[- ]\d$"#, options: .regularExpression) != nil { return 2 }
        if stem.contains("copie") || stem.contains("copy") { return 2 }
        return 0
    }

    static func created(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantFuture
    }

    /// Empreinte complète du contenu (SHA-256), lue par blocs.
    static func hash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 4_194_304), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Installeurs et téléchargements interrompus

    func installersAndPartials() -> [Ruin] {
        let downloads = home.appendingPathComponent("Downloads")
        var ruins: [Ruin] = []
        for file in Self.files(in: downloads, includeBundles: true) {
            let ext = file.pathExtension.lowercased()
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            let age = now.timeIntervalSince(modified)
            if ["crdownload", "part", "partial", "download", "opdownload"].contains(ext), age > 2 * 86_400 {
                let clues = Clues.gather(file)
                ruins.append(Ruin(url: file, kind: .partialDownload, verdict: .isolate, bytes: clues.bytes,
                                  summary: "Téléchargement jamais terminé\(clues.downloadedFrom.map { " depuis \($0)" } ?? ""), abandonné depuis \(Int(age / 86_400)) jours.",
                                  reasons: ["Extension « .\(ext) » : fichier temporaire de navigateur.", "Inutilisable tel quel."],
                                  clues: clues))
            } else if ["dmg", "pkg", "mpkg"].contains(ext), age > 3 * 86_400, let app = installedMatch(for: file) {
                let clues = Clues.gather(file)
                ruins.append(Ruin(url: file, kind: .usedInstaller, verdict: .isolate, bytes: clues.bytes,
                                  summary: "Installeur de \(app.name), déjà installé sur ce Mac.",
                                  reasons: ["« \(app.name) » est dans tes applications.", "L’installeur n’est plus nécessaire."],
                                  clues: clues))
            }
        }
        return ruins
    }

    /// L'appli installée dont le nom apparaît dans le nom de l'installeur (« PokeMMO-v62.dmg » → PokeMMO) :
    /// chaque mot significatif du nom de l'appli commence un mot du nom de l'installeur.
    func installedMatch(for installer: URL) -> InstalledApp? {
        let words = Placement.tokens(installer.deletingPathExtension().lastPathComponent)
        return apps.first { app in
            let appWords = Placement.tokens(app.name).filter { $0.count >= 4 }
            return !appWords.isEmpty && appWords.allSatisfy { appWord in words.contains { $0.hasPrefix(appWord) } }
        }
    }

    // MARK: - Fichiers d'origine inconnue

    /// Fichiers isolés au dossier personnel ou dans Téléchargements, dont le nom ne dit pas grand-chose :
    /// code, fichiers temporaires, sans extension. L'expertise enquête mais ne tranche pas seule.
    func strays() -> [Ruin] {
        let suspicious: Set<String> = ["js", "ts", "py", "sh", "tmp", "temp", "log", "json", "bin", "dat", "out", ""]
        var ruins: [Ruin] = []
        for root in [home, home.appendingPathComponent("Downloads")] {
            for file in Self.files(in: root) where suspicious.contains(file.pathExtension.lowercased()) {
                let clues = Clues.gather(file)
                ruins.append(Ruin(url: file, kind: .stray, verdict: .examine, bytes: clues.bytes,
                                  summary: Self.describe(clues), reasons: Self.reasons(clues, now: now), clues: clues))
            }
        }
        return ruins
    }

    /// Phrase d'enquête : « Code source de 584 o, téléchargé depuis github.com par Brave Browser le 5 sept., jamais ouvert. »
    static func describe(_ c: Clues) -> String {
        let what = (c.content ?? c.typeDescription ?? "Fichier").prefix(1).uppercased() + (c.content ?? c.typeDescription ?? "Fichier").dropFirst()
        var parts = ["\(what) de \(ByteText.short(c.bytes))"]
        if let site = c.downloadedFrom { parts.append("téléchargé depuis \(site)\(c.downloadedBy.map { " avec \($0)" } ?? "")") }
        else if let app = c.downloadedBy { parts.append("arrivé par \(app)") }
        if let date = c.created { parts.append("créé le \(date.formatted(.dateTime.day().month(.wide).year()))") }
        let opened = c.lastOpened.map { "ouvert pour la dernière fois le \($0.formatted(.dateTime.day().month(.wide).year()))" } ?? "jamais ouvert"
        return parts.joined(separator: ", ") + ", " + opened + "."
    }

    static func reasons(_ c: Clues, now: Date) -> [String] {
        var reasons: [String] = []
        if let content = c.content, let ext = Optional(c.url.pathExtension), !ext.isEmpty {
            reasons.append("Contenu réel : \(content) (extension « .\(ext) »).")
        }
        if let site = c.downloadedFrom { reasons.append("Provenance : \(site).") }
        if let app = c.downloadedBy { reasons.append("Téléchargé avec : \(app).") }
        if c.lastOpened == nil { reasons.append("Aucune ouverture enregistrée par macOS.") }
        else if let opened = c.lastOpened, now.timeIntervalSince(opened) > 180 * 86_400 { reasons.append("Pas ouvert depuis plus de 6 mois.") }
        return reasons
    }

    // MARK: - Outils

    static func files(in folder: URL, includeBundles: Bool = false) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        return items.filter {
            let v = try? $0.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            return v?.isRegularFile == true || (includeBundles && $0.pathExtension == "pkg")
        }
    }

    static func readable(_ name: String) -> String {
        // « com.isaacmarovitz.Whisky » → « Whisky ».
        name.contains(".") && !name.contains(" ") ? String(name.split(separator: ".").last ?? Substring(name)) : name
    }
}

enum ByteText {
    static func short(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

// MARK: - Appartenance d'un emplacement à une appli

extension Archaeologist {
    /// L'appli installée à qui appartient un emplacement : son paquet .app, son dossier de données,
    /// son conteneur ou son conteneur partagé. `nil` si aucune ne correspond clairement.
    public func ownerApp(for url: URL) -> InstalledApp? {
        let path = url.standardizedFileURL.path
        let name = url.lastPathComponent
        if url.pathExtension == "app" {
            let appName = url.deletingPathExtension().lastPathComponent
            return apps.first { $0.name == appName }
        }
        if path.contains("/Library/Containers/") || path.contains("/Library/Group Containers/") {
            var parts = name.split(separator: ".").map(String.init)
            // Préfixe d'équipe des conteneurs partagés (10 caractères).
            if parts.first?.count == 10, parts.first?.allSatisfy({ $0.isUppercase || $0.isNumber }) == true { parts.removeFirst() }
            let id = parts.joined(separator: ".")
            // L'identifiant lui-même, ou celui d'une extension de l'appli (« ru.keepcoder.Telegram.TelegramShare »).
            return apps.filter { !$0.bundleID.isEmpty && (id == $0.bundleID || id.hasPrefix($0.bundleID + ".")) }
                .max { $0.bundleID.count < $1.bundleID.count }
        }
        if path.contains("/Library/Application Support/") {
            return owner(of: name)
        }
        return nil
    }
}
