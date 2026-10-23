import Foundation

/// Le Lazaret : la corbeille du disque externe.
///
/// Ce qu'on ne veut plus y est envoyé (le Mac est libéré tout de suite), reste récupérable
/// pendant `retention`, puis est supprimé pour de bon. Historiquement, le lazaret était l'île
/// du port où l'on isolait les cargaisons douteuses : c'est exactement son rôle.
///
/// L'envoi suit le protocole des convois : copie sous nom provisoire, vérification, original
/// mis de côté, puis supprimé. Rien n'est perdu si une étape échoue.
public struct Lazaret: Sendable {
    public struct Entry: Codable, Sendable, Identifiable, Equatable {
        public var id: String { stored }
        public let original: String
        public let stored: String
        public let bytes: Int64
        public let files: Int
        public let date: Date
        public let expires: Date

        public func daysLeft(now: Date = Date()) -> Int {
            max(0, Int(ceil(expires.timeIntervalSince(now) / 86_400)))
        }
    }

    public let home: URL
    public let target: TargetVolume
    /// Durée de conservation avant suppression définitive.
    public let retention: TimeInterval

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, target: TargetVolume,
                retention: TimeInterval = 30 * 86_400) {
        self.home = home.standardizedFileURL
        self.target = target
        self.retention = retention
    }

    public var root: URL { target.url.appendingPathComponent("GoSaver Lazaret", isDirectory: true) }
    var logURL: URL { root.appendingPathComponent("registre-du-lazaret.json") }

    // MARK: - Envoi

    /// Met `source` au Lazaret. Bloquant : à appeler hors du fil principal.
    public func quarantine(_ source: URL, now: Date = Date(),
                           progress: @Sendable (Convoy.Progress) -> Void = { _ in }) throws -> Entry {
        let source = source.standardizedFileURL
        let fm = FileManager.default
        progress(.init(stage: .judging, bytesDone: 0, bytesTotal: 0))

        // Le juge garde son droit de veto : on n'isole jamais le système, iCloud, une appli isolée…
        let verdict = MobilityJudge(home: home, target: target).judge(source)
        if verdict.mobility == .forbidden, !Self.onlyBlockedByMobilityConcerns(verdict) {
            throw Convoy.Failure.refused(verdict.reason)
        }
        let contents = verdict.contents ?? MobilityJudge.scan(source)
        if contents.symlinks > 0, !target.format.keepsSymlinks {
            throw Convoy.Failure.refused("il contient des liens symboliques que \(target.format.label) ne sait pas garder ; supprime-le directement si tu n’en veux plus")
        }
        let needed = target.format.keepsSparseFiles ? contents.allocatedBytes : max(contents.logicalBytes, contents.allocatedBytes)
        if needed > target.freeBytes { throw Convoy.Failure.refused("pas assez de place sur \(target.name)") }

        // Rangé par jour d'arrivée : « GoSaver Lazaret/2026-10-22/JPEG ».
        let day = Self.dayFormatter.string(from: now)
        let shelf = root.appendingPathComponent(day, isDirectory: true)
        let stored = Convoy.uniqueChild(in: shelf, named: source.lastPathComponent)
        let partial = shelf.appendingPathComponent(stored.lastPathComponent + ".gosaver-partiel")
        let convoy = Convoy(home: home, target: target)
        do {
            try fm.createDirectory(at: shelf, withIntermediateDirectories: true)
            try convoy.copyTree(from: source, to: partial) { done in
                progress(.init(stage: .copying, bytesDone: done, bytesTotal: contents.allocatedBytes))
            }
        } catch {
            try? fm.removeItem(at: partial)
            throw Convoy.Failure.copyFailed((error as NSError).localizedDescription)
        }
        progress(.init(stage: .verifying, bytesDone: contents.allocatedBytes, bytesTotal: contents.allocatedBytes))
        if let problem = Convoy.difference(between: source, and: partial) {
            try? fm.removeItem(at: partial)
            throw Convoy.Failure.verificationFailed(problem)
        }
        do { try fm.moveItem(at: partial, to: stored) } catch {
            try? fm.removeItem(at: partial)
            throw Convoy.Failure.copyFailed((error as NSError).localizedDescription)
        }
        progress(.init(stage: .replacing, bytesDone: contents.allocatedBytes, bytesTotal: contents.allocatedBytes))
        let aside = source.deletingLastPathComponent().appendingPathComponent(".\(source.lastPathComponent).gosaver-ancien")
        do {
            if fm.fileExists(atPath: aside.path) { try fm.removeItem(at: aside) }
            try fm.moveItem(at: source, to: aside)
        } catch {
            try? fm.removeItem(at: stored)
            throw Convoy.Failure.cannotSetAside((error as NSError).localizedDescription)
        }
        try? fm.removeItem(at: aside)

        let date = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        let entry = Entry(original: source.path, stored: stored.path, bytes: contents.allocatedBytes,
                          files: contents.files, date: date, expires: date.addingTimeInterval(retention))
        try? writeLog(entries() + [entry])
        progress(.init(stage: .done, bytesDone: contents.allocatedBytes, bytesTotal: contents.allocatedBytes))
        return entry
    }

    /// Les refus du juge qui ne concernent que le *déplacement* (place, liens, taille de fichier)
    /// sont revérifiés plus bas pour le Lazaret. Restent bloquants : les refus d'emplacement
    /// (système, bac à sable… — le juge s'arrête alors avant de parcourir le contenu) et iCloud
    /// (isoler un fichier synchronisé le supprimerait de tous les appareils).
    public static func onlyBlockedByMobilityConcerns(_ verdict: MobilityVerdict) -> Bool {
        guard let contents = verdict.contents else { return false }
        return contents.inICloud == 0
    }

    // MARK: - Restauration

    /// Ramène un élément à son emplacement d'origine (avant son expiration).
    public func restore(_ entry: Entry, progress: @Sendable (Convoy.Progress) -> Void = { _ in }) throws {
        let fm = FileManager.default
        let original = URL(fileURLWithPath: entry.original)
        let stored = URL(fileURLWithPath: entry.stored)
        guard fm.fileExists(atPath: stored.path) else { throw Convoy.Failure.refused("introuvable au Lazaret") }
        guard !fm.fileExists(atPath: original.path) else {
            throw Convoy.Failure.refused("un élément occupe déjà « \(original.lastPathComponent) » à son emplacement d’origine")
        }
        let partial = original.deletingLastPathComponent().appendingPathComponent(".\(original.lastPathComponent).gosaver-partiel")
        do {
            try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Convoy(home: home, target: target).copyTree(from: stored, to: partial) { done in
                progress(.init(stage: .copying, bytesDone: done, bytesTotal: entry.bytes))
            }
        } catch {
            try? fm.removeItem(at: partial)
            throw Convoy.Failure.copyFailed((error as NSError).localizedDescription)
        }
        progress(.init(stage: .verifying, bytesDone: entry.bytes, bytesTotal: entry.bytes))
        if let problem = Convoy.difference(between: stored, and: partial) {
            try? fm.removeItem(at: partial)
            throw Convoy.Failure.verificationFailed(problem)
        }
        Convoy(home: home, target: target).normalizePermissions(partial)
        do { try fm.moveItem(at: partial, to: original) } catch {
            try? fm.removeItem(at: partial)
            throw Convoy.Failure.cannotSetAside((error as NSError).localizedDescription)
        }
        try? fm.removeItem(at: stored)
        try? removeEmptyDay(of: stored)
        try writeLog(entries().filter { $0.id != entry.id })
        progress(.init(stage: .done, bytesDone: entry.bytes, bytesTotal: entry.bytes))
    }

    // MARK: - Expiration

    /// Supprime définitivement ce qui a dépassé son délai. Renvoie ce qui a été supprimé.
    @discardableResult
    public func purgeExpired(now: Date = Date()) -> [Entry] {
        let all = entries()
        let expired = all.filter { $0.expires <= now }
        guard !expired.isEmpty else { return [] }
        var purged: [Entry] = []
        for entry in expired {
            let stored = URL(fileURLWithPath: entry.stored)
            // Sécurité : on ne supprime que ce qui est bien à l'intérieur du Lazaret.
            guard stored.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else { continue }
            if (try? FileManager.default.removeItem(at: stored)) != nil || !FileManager.default.fileExists(atPath: stored.path) {
                purged.append(entry)
                try? removeEmptyDay(of: stored)
            }
        }
        try? writeLog(all.filter { entry in !purged.contains { $0.id == entry.id } })
        return purged
    }

    /// Supprime tout de suite, sans attendre l'expiration (choix explicite de l'utilisateur).
    public func discardNow(_ entry: Entry) throws {
        let stored = URL(fileURLWithPath: entry.stored)
        guard stored.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw Convoy.Failure.refused("hors du Lazaret")
        }
        if FileManager.default.fileExists(atPath: stored.path) { try FileManager.default.removeItem(at: stored) }
        try? removeEmptyDay(of: stored)
        try writeLog(entries().filter { $0.id != entry.id })
    }

    // MARK: - Registre

    public func entries() -> [Entry] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([Entry].self, from: data)) ?? []).sorted { $0.expires < $1.expires }
    }

    private func writeLog(_ entries: [Entry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(entries).write(to: logURL, options: .atomic)
    }

    /// Retire le dossier du jour s'il est vide (les ._ et .DS_Store de macOS ne comptent pas).
    private func removeEmptyDay(of stored: URL) throws {
        let day = stored.deletingLastPathComponent()
        let left = try FileManager.default.contentsOfDirectory(atPath: day.path)
            .filter { !$0.hasPrefix("._") && $0 != ".DS_Store" }
        if left.isEmpty { try FileManager.default.removeItem(at: day) }
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
