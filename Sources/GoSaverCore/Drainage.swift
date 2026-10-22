import Foundation

/// Assèchement : suppression des données qui se reforment seules (caches, journaux)
/// et vidage de la corbeille.
///
/// Règles de sécurité, vérifiées à chaque élément :
/// 1. Liste blanche : on ne supprime que le *contenu* de racines connues, jamais les racines.
/// 2. Juste avant la suppression, le chemin réel (liens résolus) doit être strictement
///    à l'intérieur d'une racine autorisée.
/// 3. Les caches d'une appli ouverte sont laissés : la vider en marche peut la faire planter.
/// 4. Un lien symbolique est supprimé en tant que lien : sa cible n'est jamais touchée.
public struct Drainer: Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case cache, log, trash

        public var label: String {
            switch self {
            case .cache: "Caches d’applis"
            case .log: "Journaux"
            case .trash: "Corbeille"
            }
        }

        /// La corbeille ne se reforme pas : sa suppression est définitive.
        public var isPermanent: Bool { self == .trash }
    }

    /// Une racine dont le contenu peut être asséché.
    public struct Root: Sendable {
        public let url: URL
        public let kind: Kind
        public init(_ url: URL, _ kind: Kind) { self.url = url; self.kind = kind }
    }

    public struct Item: Sendable, Identifiable, Hashable {
        public var id: String { url.path }
        public let url: URL
        public let kind: Kind
        public let bytes: Int64
        /// Propriétaire présumé (identifiant ou nom d'appli), pour l'affichage et les applis ouvertes.
        public let owner: String
    }

    public struct Plan: Sendable {
        public let items: [Item]
        /// Éléments laissés parce que leur appli est ouverte.
        public let inUse: [Item]
        /// Racines illisibles (accès complet au disque manquant, en général pour la corbeille).
        public let unreadable: [Kind]

        public func bytes(of kind: Kind) -> Int64 {
            items.lazy.filter { $0.kind == kind }.reduce(0) { $0 + $1.bytes }
        }
        public func count(of kind: Kind) -> Int { items.lazy.filter { $0.kind == kind }.count }

        /// Le même plan restreint à certains genres (ex. sans la corbeille).
        public func keeping(_ kinds: Set<Kind>) -> Plan {
            Plan(items: items.filter { kinds.contains($0.kind) }, inUse: inUse, unreadable: unreadable)
        }
    }

    public struct Result: Sendable {
        public let removedBytes: Int64
        public let removedCount: Int
        public let failures: [(path: String, reason: String)]
    }

    public let roots: [Root]

    public init(roots: [Root]) { self.roots = roots }

    /// Racines standard d'un Mac : caches et journaux de l'utilisateur, caches internes
    /// des applis conteneurisées, corbeille.
    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Drainer {
        var roots = [
            Root(home.appendingPathComponent("Library/Caches"), .cache),
            Root(home.appendingPathComponent("Library/Logs"), .log),
            Root(home.appendingPathComponent(".Trash"), .trash),
        ]
        let containers = home.appendingPathComponent("Library/Containers")
        let apps = (try? FileManager.default.contentsOfDirectory(at: containers, includingPropertiesForKeys: nil)) ?? []
        for app in apps {
            let caches = app.appendingPathComponent("Data/Library/Caches")
            if FileManager.default.fileExists(atPath: caches.path) { roots.append(Root(caches, .cache)) }
        }
        return Drainer(roots: roots)
    }

    // MARK: - Plan

    /// Prépare la liste de ce qui partirait. Ne supprime rien.
    /// - Parameter running: identifiants et noms des applis ouvertes.
    public func plan(kinds: Set<Kind> = Set(Kind.allCases), running: [RunningApp] = []) -> Plan {
        var items: [Item] = [], inUse: [Item] = [], unreadable: [Kind] = []
        for root in roots where kinds.contains(root.kind) {
            let children: [URL]
            do {
                children = try FileManager.default.contentsOfDirectory(
                    at: root.url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])
            } catch {
                if FileManager.default.fileExists(atPath: root.url.path) { unreadable.append(root.kind) }
                continue
            }
            for child in children where child.lastPathComponent != ".DS_Store" {
                let owner = Self.owner(of: child, in: root)
                let item = Item(url: child, kind: root.kind, bytes: Self.allocatedSize(of: child), owner: owner)
                guard item.bytes > 0 else { continue }
                if root.kind != .trash, running.contains(where: { $0.owns(owner) }) {
                    inUse.append(item)
                } else {
                    items.append(item)
                }
            }
        }
        return Plan(items: items.sorted { $0.bytes > $1.bytes }, inUse: inUse,
                    unreadable: Array(Set(unreadable)))
    }

    // MARK: - Exécution

    /// Supprime les éléments du plan, un par un, en revérifiant chaque chemin.
    public func execute(_ plan: Plan, progress: @Sendable (Int64) -> Void = { _ in }) -> Result {
        var removed: Int64 = 0, count = 0
        var failures: [(String, String)] = []
        for item in plan.items {
            guard isSafe(item.url) else {
                failures.append((item.url.path, "hors des zones autorisées"))
                continue
            }
            do {
                try FileManager.default.removeItem(at: item.url)
                removed += item.bytes
                count += 1
                progress(removed)
            } catch {
                failures.append((item.url.path, (error as NSError).localizedDescription))
            }
        }
        return Result(removedBytes: removed, removedCount: count, failures: failures)
    }

    /// Vrai si l'élément est un enfant (direct ou non) d'une racine autorisée, et n'est pas une racine.
    /// Le dossier parent est résolu (liens compris) ; l'élément lui-même ne l'est pas, pour qu'un
    /// lien symbolique soit supprimé en tant que lien sans jamais toucher sa cible.
    public func isSafe(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        let path = parent + "/" + url.lastPathComponent
        return roots.contains { root in
            let base = root.url.resolvingSymlinksInPath().path
            return path.hasPrefix(base + "/") && path != base
        }
    }

    // MARK: - Outils

    /// Propriétaire : le nom du dossier sous la racine, ou celui de l'appli conteneurisée.
    static func owner(of child: URL, in root: Root) -> String {
        let components = root.url.pathComponents
        if let index = components.firstIndex(of: "Containers"), components.count > index + 1 {
            return components[index + 1]
        }
        return child.lastPathComponent
    }

    /// Taille réellement occupée sur le disque, sans suivre les liens symboliques.
    public static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let values = try? url.resourceValues(forKeys: keys)
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [],
                                                        errorHandler: { _, _ in true })
        while let file = enumerator?.nextObject() as? URL {
            let v = try? file.resourceValues(forKeys: keys)
            if v?.isDirectory != true { total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0) }
        }
        return total
    }
}

/// Une appli ouverte, vue par le moteur (sans AppKit, pour rester testable).
public struct RunningApp: Sendable {
    public let bundleID: String
    public let name: String
    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }

    /// Vrai si un dossier nommé `owner` appartient probablement à cette appli.
    /// On préfère se tromper dans le sens prudent : un faux positif laisse juste un cache en place.
    func owns(_ owner: String) -> Bool {
        let o = owner.lowercased()
        if !bundleID.isEmpty, o.contains(bundleID.lowercased()) { return true }
        // Premier mot du nom (« Brave » pour « Brave Browser » → « BraveSoftware »).
        if let word = name.split(separator: " ").first, word.count >= 4, o.contains(word.lowercased()) { return true }
        return false
    }
}
