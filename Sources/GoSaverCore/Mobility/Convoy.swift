import Foundation
import CryptoKit

/// Le convoi : envoie un dossier vers l'Outre-mer (disque externe), ou le rapatrie.
///
/// Protocole « copier, vérifier, puis remplacer » — à aucun moment un fichier n'existe
/// seulement dans un état incertain :
/// 1. on rejuge l'élément (seuls « Libre » et « Avec lien » partent) ;
/// 2. on copie sous un nom provisoire (`….gosaver-partiel`) ;
/// 3. on vérifie la copie (nombre de fichiers, tailles, empreintes de début et de fin) ;
/// 4. on renomme la copie à son nom définitif ;
/// 5. on met l'original de côté par un simple renommage (instantané, réversible) ;
/// 6. pour « Avec lien », on pose le lien symbolique à l'emplacement d'origine ;
/// 7. on supprime l'original mis de côté, et on note le convoi dans le registre de bord.
/// Tout échec avant l'étape 7 annule proprement : l'original revient, la copie est effacée.
public struct Convoy: Sendable {
    public enum Stage: Sendable, Equatable {
        case judging, copying, verifying, replacing, done
    }

    public struct Progress: Sendable {
        public let stage: Stage
        public let bytesDone: Int64
        public let bytesTotal: Int64
    }

    public enum Failure: Error, Sendable, Equatable, LocalizedError {
        case refused(String)
        case copyFailed(String)
        case verificationFailed(String)
        case cannotSetAside(String)

        public var errorDescription: String? {
            switch self {
            case .refused(let why): "Envoi refusé : \(why)"
            case .copyFailed(let why): "La copie a échoué : \(why). L’original n’a pas été touché."
            case .verificationFailed(let why): "La copie ne correspond pas à l’original (\(why)). Elle a été effacée, l’original n’a pas été touché."
            case .cannotSetAside(let why): "L’original n’a pas pu être mis de côté (\(why)) : sans doute ouvert dans une appli. La copie a été effacée."
            }
        }
    }

    /// Ce qui a été fait, tel que noté dans le registre de bord.
    public struct Record: Codable, Sendable, Identifiable, Equatable {
        /// L'emplacement d'origine et l'heure d'envoi identifient un convoi
        /// (plusieurs convois peuvent être fusionnés dans le même dossier).
        public var id: String { "\(original)@\(Int(date.timeIntervalSince1970))" }
        public let original: String
        /// Dossier envoyé sur le disque, ou dossier existant dans lequel son contenu a été versé.
        public let destination: String
        public let linked: Bool
        public let bytes: Int64
        public let files: Int
        public let date: Date
        /// Fusion : nom d'origine → nom dans le dossier de destination (renommé en cas de conflit).
        public var mergedItems: [String: String]? = nil
    }

    public let home: URL
    public let target: TargetVolume

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, target: TargetVolume) {
        self.home = home.standardizedFileURL
        self.target = target
    }

    /// Dossier d'accueil sur le disque externe.
    public var harbor: URL { target.url.appendingPathComponent("GoSaver Outre-mer", isDirectory: true) }

    // MARK: - Envoi

    /// Envoie `source` outre-mer. Bloquant : à appeler hors du fil principal.
    /// - Parameters:
    ///   - folder: dossier du disque où le ranger (`nil` : dossier d'accueil « GoSaver Outre-mer »).
    ///   - merge: verser le contenu dans `folder` au lieu d'y créer un sous-dossier (même nom).
    ///     Jamais pour un envoi « avec lien » : le lien doit pointer vers un dossier qui n'appartient qu'à lui.
    public func send(_ source: URL, into folder: URL? = nil, merge: Bool = false,
                     progress: @Sendable (Progress) -> Void = { _ in }) throws -> Record {
        let source = source.standardizedFileURL
        progress(Progress(stage: .judging, bytesDone: 0, bytesTotal: 0))

        // 1. Rejuger juste avant : l'état du disque a pu changer depuis l'affichage de la fiche.
        let verdict = MobilityJudge(home: home, target: target).judge(source)
        guard verdict.mobility == .free || verdict.mobility == .withLink else {
            throw Failure.refused(verdict.reason)
        }
        let linked = verdict.mobility == .withLink
        let total = verdict.contents?.allocatedBytes ?? 0
        let fm = FileManager.default

        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        let merging = merge && !linked && isDirectory && folder.map { fm.fileExists(atPath: $0.path) } == true

        // 2. Copie sous un nom provisoire : dans le dossier choisi, ou dans le dossier d'accueil
        // en reproduisant le chemin depuis le dossier personnel.
        let destination: URL
        if let folder, merging {
            destination = folder
        } else if let folder {
            destination = Self.uniqueChild(in: folder, named: source.lastPathComponent)
        } else {
            destination = uniqueDestination(for: source)
        }
        let partial = merging
            ? destination.deletingLastPathComponent().appendingPathComponent(".\(source.lastPathComponent).gosaver-partiel")
            : destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".gosaver-partiel")
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: partial.path) { try fm.removeItem(at: partial) }
            try copyTree(from: source, to: partial) { done in
                progress(Progress(stage: .copying, bytesDone: done, bytesTotal: total))
            }
        } catch {
            try? fm.removeItem(at: partial)
            throw Failure.copyFailed((error as NSError).localizedDescription)
        }

        // 3. Vérification.
        progress(Progress(stage: .verifying, bytesDone: total, bytesTotal: total))
        if let problem = Self.difference(between: source, and: partial) {
            try? fm.removeItem(at: partial)
            throw Failure.verificationFailed(problem)
        }

        // 4. La copie prend sa place définitive : renommée, ou versée élément par élément (fusion).
        var merged: [String: String]?
        if merging {
            do { merged = try Self.pour(partial, into: destination) } catch {
                try? fm.removeItem(at: partial)
                throw Failure.copyFailed((error as NSError).localizedDescription)
            }
        } else {
            do { try fm.moveItem(at: partial, to: destination) } catch {
                try? fm.removeItem(at: partial)
                throw Failure.copyFailed((error as NSError).localizedDescription)
            }
        }
        /// Retire du disque ce que cet envoi y a mis (en cas d'annulation).
        func undoArrival() {
            if let merged {
                for name in merged.values { try? fm.removeItem(at: destination.appendingPathComponent(name)) }
            } else {
                try? fm.removeItem(at: destination)
            }
        }

        // 5. L'original est mis de côté (renommage sur le même disque : instantané, réversible).
        progress(Progress(stage: .replacing, bytesDone: total, bytesTotal: total))
        let aside = source.deletingLastPathComponent().appendingPathComponent(".\(source.lastPathComponent).gosaver-ancien")
        do {
            if fm.fileExists(atPath: aside.path) { try fm.removeItem(at: aside) }
            try fm.moveItem(at: source, to: aside)
        } catch {
            undoArrival()
            throw Failure.cannotSetAside((error as NSError).localizedDescription)
        }

        // 6. Lien symbolique, si l'appli attend le dossier à son ancien emplacement.
        if linked {
            do { try fm.createSymbolicLink(at: source, withDestinationURL: destination) } catch {
                // Retour en arrière complet : l'original revient à sa place.
                try? fm.moveItem(at: aside, to: source)
                try? fm.removeItem(at: destination)
                throw Failure.cannotSetAside("lien impossible : \((error as NSError).localizedDescription)")
            }
        }

        // 7. Suppression de l'original mis de côté, puis registre de bord.
        try? fm.removeItem(at: aside)
        let record = Record(original: source.path, destination: destination.path, linked: linked,
                            bytes: total, files: verdict.contents?.files ?? 0,
                            // Arrondie à la seconde : le format ISO 8601 du registre ne garde pas les fractions.
                            date: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
                            mergedItems: merged)
        try? appendToLog(record)
        progress(Progress(stage: .done, bytesDone: total, bytesTotal: total))
        return record
    }

    // MARK: - Rapatriement

    /// Ramène un élément envoyé à son emplacement d'origine (même protocole, dans l'autre sens).
    public func bringBack(_ record: Record, progress: @Sendable (Progress) -> Void = { _ in }) throws {
        let fm = FileManager.default
        let original = URL(fileURLWithPath: record.original)
        let remote = URL(fileURLWithPath: record.destination)
        guard fm.fileExists(atPath: remote.path) else { throw Failure.refused("introuvable sur \(target.name)") }

        // L'emplacement d'origine doit être libre (ou n'être que notre lien).
        let values = try? original.resourceValues(forKeys: [.isSymbolicLinkKey])
        let isOurLink = values?.isSymbolicLink == true
        if fm.fileExists(atPath: original.path), !isOurLink {
            throw Failure.refused("un élément occupe déjà \(original.lastPathComponent) à son emplacement d’origine")
        }
        let partial = original.deletingLastPathComponent().appendingPathComponent(".\(original.lastPathComponent).gosaver-partiel")
        // Ce qu'il faut ramener : tout le dossier, ou seulement les éléments versés lors d'une fusion.
        let pieces: [(remote: URL, local: URL)] = record.mergedItems.map { items in
            items.map { (remote.appendingPathComponent($0.value), partial.appendingPathComponent($0.key)) }
        } ?? [(remote, partial)]
        do {
            try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: partial.path) { try fm.removeItem(at: partial) }
            if record.mergedItems != nil { try fm.createDirectory(at: partial, withIntermediateDirectories: false) }
            var copied: Int64 = 0
            for piece in pieces {
                try copyTree(from: piece.remote, to: piece.local) { done in
                    progress(Progress(stage: .copying, bytesDone: copied + done, bytesTotal: record.bytes))
                }
                copied += Drainer.allocatedSize(of: piece.local)
            }
        } catch {
            try? fm.removeItem(at: partial)
            throw Failure.copyFailed((error as NSError).localizedDescription)
        }
        progress(Progress(stage: .verifying, bytesDone: record.bytes, bytesTotal: record.bytes))
        for piece in pieces {
            if let problem = Self.difference(between: piece.remote, and: piece.local) {
                try? fm.removeItem(at: partial)
                throw Failure.verificationFailed(problem)
            }
        }
        progress(Progress(stage: .replacing, bytesDone: record.bytes, bytesTotal: record.bytes))
        normalizePermissions(partial)
        if isOurLink { try? fm.removeItem(at: original) }
        do { try fm.moveItem(at: partial, to: original) } catch {
            try? fm.removeItem(at: partial)
            if isOurLink { try? fm.createSymbolicLink(at: original, withDestinationURL: remote) }
            throw Failure.cannotSetAside((error as NSError).localizedDescription)
        }
        for piece in pieces { try? fm.removeItem(at: piece.remote) }
        try? removeFromLog(record)
        progress(Progress(stage: .done, bytesDone: record.bytes, bytesTotal: record.bytes))
    }

    // MARK: - Reclassement

    /// Range autrement un envoi déjà fait, sur le même disque : un simple renommage, instantané.
    /// `merge` verse le contenu dans `folder` (dossier du même nom) au lieu d'y créer un sous-dossier.
    @discardableResult
    public func relocate(_ record: Record, to folder: URL, merge: Bool = false) throws -> Record {
        let fm = FileManager.default
        guard record.mergedItems == nil else { throw Failure.refused("ce convoi a déjà été versé dans un dossier existant") }
        let remote = URL(fileURLWithPath: record.destination)
        guard fm.fileExists(atPath: remote.path) else { throw Failure.refused("introuvable sur \(target.name)") }
        guard fm.fileExists(atPath: folder.path) else { throw Failure.refused("le dossier choisi n’existe plus") }

        var updated: Record
        if merge, !record.linked {
            let merged = try Self.pour(remote, into: folder)
            updated = Record(original: record.original, destination: folder.path, linked: false,
                             bytes: record.bytes, files: record.files, date: record.date, mergedItems: merged)
        } else {
            let destination = Self.uniqueChild(in: folder, named: remote.lastPathComponent)
            try fm.moveItem(at: remote, to: destination)
            if record.linked {
                // Le lien du disque interne suit le dossier à sa nouvelle adresse.
                let original = URL(fileURLWithPath: record.original)
                try? fm.removeItem(at: original)
                try fm.createSymbolicLink(at: original, withDestinationURL: destination)
            }
            updated = Record(original: record.original, destination: destination.path, linked: record.linked,
                             bytes: record.bytes, files: record.files, date: record.date)
        }
        try writeLog(records().map { $0.id == record.id ? updated : $0 })
        return updated
    }

    /// Verse le contenu de `source` dans `folder` (même disque : renommages). En cas de conflit
    /// de nom, l'élément arrivant est renommé « … (depuis le Mac) » : rien n'est jamais écrasé.
    /// `source`, vidé, est supprimé. Renvoie nom d'origine → nom dans `folder`.
    static func pour(_ source: URL, into folder: URL) throws -> [String: String] {
        let fm = FileManager.default
        var moved: [String: String] = [:]
        do {
            for name in try fm.contentsOfDirectory(atPath: source.path) where name != ".DS_Store" {
                let target = uniqueChild(in: folder, named: name, suffix: "depuis le Mac")
                try fm.moveItem(at: source.appendingPathComponent(name), to: target)
                moved[name] = target.lastPathComponent
            }
        } catch {
            // Retour en arrière : ce qui a déjà été versé revient dans `source`.
            for (name, placed) in moved {
                try? fm.moveItem(at: folder.appendingPathComponent(placed), to: source.appendingPathComponent(name))
            }
            throw error
        }
        try? fm.removeItem(at: source)
        return moved
    }

    /// `folder/name`, ou `folder/name (2)`… (ou `name (suffixe)`) si le nom est pris.
    static func uniqueChild(in folder: URL, named name: String, suffix: String? = nil) -> URL {
        let base = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        let ext = base.pathExtension
        let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var n = 1
        while true {
            let label = suffix.map { n == 1 ? $0 : "\($0) \(n)" } ?? "\(n + 1)"
            let candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) (\(label))" : "\(stem) (\(label)).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    // MARK: - Registre de bord

    /// Registre de bord : stocké sur le disque externe lui-même, il voyage avec les données.
    public var logURL: URL { harbor.appendingPathComponent("registre-de-bord.json") }

    public func records() -> [Record] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Record].self, from: data)) ?? []
    }

    func appendToLog(_ record: Record) throws { try writeLog(records() + [record]) }
    func removeFromLog(_ record: Record) throws { try writeLog(records().filter { $0.id != record.id }) }

    private func writeLog(_ records: [Record]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: harbor, withIntermediateDirectories: true)
        try encoder.encode(records).write(to: logURL, options: .atomic)
    }

    // MARK: - Outils

    /// Chemin sur le disque externe : on reproduit l'arborescence depuis le dossier personnel
    /// (« Downloads/JPEG »), avec « (2) », « (3) »… si le nom est déjà pris.
    func uniqueDestination(for source: URL) -> URL {
        let homePath = home.path + "/"
        let relative = source.path.hasPrefix(homePath) ? String(source.path.dropFirst(homePath.count)) : source.lastPathComponent
        let base = harbor.appendingPathComponent(relative)
        var candidate = base
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let ext = base.pathExtension
            let stem = base.deletingPathExtension().lastPathComponent
            let name = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            candidate = base.deletingLastPathComponent().appendingPathComponent(name)
            n += 1
        }
        return candidate
    }

    /// Copie fichier par fichier (pour suivre l'avancement). Les liens symboliques sont recopiés
    /// en tant que liens — le juge a déjà refusé ceux que le disque cible ne sait pas garder.
    func copyTree(from source: URL, to destination: URL, progress: (Int64) -> Void) throws {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey]
        let rootValues = try source.resourceValues(forKeys: keys)
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            try fm.copyItem(at: source, to: destination)
            progress(Int64(rootValues.totalFileAllocatedSize ?? 0))
            return
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        var done: Int64 = 0
        // L'énumérateur « par chaîne » donne directement des chemins relatifs : aucun calcul
        // de préfixe (fragile à cause de /var ↔ /private/var).
        for relative in Self.relativePaths(under: source) {
            let item = source.appendingPathComponent(relative)
            let target = destination.appendingPathComponent(relative)
            let v = try item.resourceValues(forKeys: keys)
            if v.isSymbolicLink == true {
                let link = try fm.destinationOfSymbolicLink(atPath: item.path)
                try fm.createSymbolicLink(atPath: target.path, withDestinationPath: link)
            } else if v.isDirectory == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fm.copyItem(at: item, to: target)
                done += Int64(v.totalFileAllocatedSize ?? 0)
                progress(done)
            }
        }
    }

    /// Au retour d'un disque qui ne garde pas les droits (exFAT), macOS invente des droits
    /// « rwx------ ». On remet ceux d'un document ordinaire : fichiers rw-r--r--, dossiers rwxr-xr-x.
    func normalizePermissions(_ root: URL) {
        guard !target.format.keepsPermissions else { return }
        let fm = FileManager.default
        func fix(_ url: URL) {
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard v?.isSymbolicLink != true else { return }
            try? fm.setAttributes([.posixPermissions: v?.isDirectory == true ? 0o755 : 0o644], ofItemAtPath: url.path)
        }
        fix(root)
        for relative in Self.relativePaths(under: root) { fix(root.appendingPathComponent(relative)) }
    }

    /// Chemins relatifs de tout ce que contient un dossier (sans suivre les liens).
    static func relativePaths(under root: URL) -> [String] {
        var paths: [String] = []
        let enumerator = FileManager.default.enumerator(atPath: root.path)
        while let relative = enumerator?.nextObject() as? String { paths.append(relative) }
        return paths
    }

    /// Compare deux arborescences : mêmes fichiers, mêmes tailles, mêmes empreintes
    /// du premier et du dernier mégaoctet. Renvoie la première différence, ou `nil`.
    /// (Comparer chaque octet de 30 Go prendrait des minutes ; début + fin + taille
    /// détecte les copies tronquées ou corrompues, les cas réels d'échec d'une copie.)
    static func difference(between a: URL, and b: URL) -> String? {
        let left = inventory(a), right = inventory(b)
        guard left.count == right.count else { return "\(left.count) fichiers d’un côté, \(right.count) de l’autre" }
        for (path, size) in left {
            guard let other = right[path] else { return "« \(path) » manque" }
            guard other == size else { return "« \(path) » n’a pas la même taille" }
            let fa = path.isEmpty ? a : a.appendingPathComponent(path)
            let fb = path.isEmpty ? b : b.appendingPathComponent(path)
            guard fingerprint(fa) == fingerprint(fb) else { return "« \(path) » a un contenu différent" }
        }
        return nil
    }

    /// Fichiers ordinaires (chemin relatif → taille annoncée). Les ._ créés par macOS sur exFAT sont ignorés.
    static func inventory(_ root: URL) -> [String: Int64] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let rootValues = try? root.resourceValues(forKeys: keys)
        if rootValues?.isRegularFile == true { return ["": Int64(rootValues?.fileSize ?? 0)] }
        var result: [String: Int64] = [:]
        for relative in relativePaths(under: root) where !(relative as NSString).lastPathComponent.hasPrefix("._") {
            let v = try? root.appendingPathComponent(relative).resourceValues(forKeys: keys)
            guard v?.isRegularFile == true else { continue }
            result[relative] = Int64(v?.fileSize ?? 0)
        }
        return result
    }

    /// Empreinte SHA-256 du premier et du dernier mégaoctet d'un fichier.
    static func fingerprint(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = 1_048_576
        var hasher = SHA256()
        hasher.update(data: (try? handle.read(upToCount: chunk)) ?? Data())
        if let end = try? handle.seekToEnd(), end > UInt64(chunk) {
            try? handle.seek(toOffset: end - UInt64(chunk))
            hasher.update(data: (try? handle.read(upToCount: chunk)) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
