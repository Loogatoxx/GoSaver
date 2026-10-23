import Foundation

/// Peut-on envoyer ce dossier sur le disque externe sans rien casser ?
/// Du plus permissif au plus strict.
public enum Mobility: Int, Sendable, Comparable, CaseIterable {
    /// Se déplace tel quel : rien ne le cherche à cet endroit.
    case free
    /// Une appli l'attend ici : on le déplace et on laisse un lien symbolique à sa place.
    case withLink
    /// Possible, mais avec un effet de bord, ou il existe une meilleure manière.
    case discouraged
    /// Ne doit jamais partir.
    case forbidden

    public static func < (a: Mobility, b: Mobility) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .free: "Libre"
        case .withLink: "Avec lien"
        case .discouraged: "Déconseillé"
        case .forbidden: "Interdit"
        }
    }
}

/// Le verdict, toujours accompagné de sa raison : c'est elle que l'IA reformulera,
/// sans jamais pouvoir changer le verdict.
public struct MobilityVerdict: Sendable {
    public let mobility: Mobility
    /// Raison principale (celle du constat le plus sévère).
    public let reason: String
    /// Ce qu'il vaut mieux faire à la place, s'il y a mieux.
    public let advice: String?
    /// Autres constats, moins sévères mais utiles.
    public let notes: [String]
    public let contents: ContentReport?
    /// Place nécessaire sur la destination (un fichier creux peut y prendre plus de place).
    public let bytesOnTarget: Int64?
}

/// Ce que contient un dossier, du point de vue d'un déplacement.
public struct ContentReport: Sendable, Equatable {
    public var files = 0
    /// Taille annoncée des fichiers.
    public var logicalBytes: Int64 = 0
    /// Taille réellement occupée (plus petite pour les fichiers creux).
    public var allocatedBytes: Int64 = 0
    public var symlinks = 0
    public var executables = 0
    public var largestFile: Int64 = 0
    public var inICloud = 0
    public var isGitRepository = false
    /// Quelques programmes trouvés (noms), pour montrer lesquels posent problème.
    public var executableSamples: [String] = []
}

/// Le juge : règles vérifiables, aucune devinette.
public struct MobilityJudge: Sendable {
    public let home: URL
    /// Destination prévue, ou `nil` si aucun disque n'est branché.
    public let target: TargetVolume?

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, target: TargetVolume?) {
        self.home = home.standardizedFileURL
        self.target = target
    }

    struct Finding {
        let mobility: Mobility
        let text: String
        var advice: String? = nil
    }

    public func judge(_ url: URL) -> MobilityVerdict {
        let url = url.standardizedFileURL
        var findings = pathRules(url)

        // Interdit par son emplacement, ou mieux vaut faire autre chose (assécher, supprimer,
        // passer par l'appli) : inutile de parcourir le contenu, la réponse est déjà claire.
        if findings.contains(where: { $0.mobility == .forbidden || ($0.mobility == .discouraged && $0.advice != nil) }) {
            return verdict(findings, contents: nil, bytesOnTarget: nil)
        }

        let contents = Self.scan(url)
        findings += contentRules(contents)
        var onTarget: Int64?
        if let target {
            let needed = target.format.keepsSparseFiles ? contents.allocatedBytes : max(contents.logicalBytes, contents.allocatedBytes)
            onTarget = needed
            findings += targetRules(contents, target: target, needed: needed)
        } else {
            findings.append(Finding(mobility: .free,
                                    text: "Branche le disque de destination pour vérifier sa place et son format."))
        }
        return verdict(findings, contents: contents, bytesOnTarget: onTarget)
    }

    /// Un constat « Libre » n'est qu'une précision ; la raison principale vient du constat
    /// le plus sévère (à sévérité égale, le premier trouvé).
    private func verdict(_ findings: [Finding], contents: ContentReport?, bytesOnTarget: Int64?) -> MobilityVerdict {
        let blocking = findings.filter { $0.mobility != .free }
        let main = blocking.enumerated().max {
            $0.element.mobility != $1.element.mobility ? $0.element.mobility < $1.element.mobility : $0.offset > $1.offset
        }?.element
        let notes = findings.filter { $0.mobility == .free }.map(\.text)
            + blocking.filter { $0.text != main?.text }.map(\.text)
        return MobilityVerdict(mobility: main?.mobility ?? .free,
                               reason: main?.text ?? "Rien ne le retient ici : il peut partir tel quel.",
                               advice: main?.advice, notes: notes,
                               contents: contents, bytesOnTarget: bytesOnTarget)
    }

    // MARK: - Règles d'emplacement

    func pathRules(_ url: URL) -> [Finding] {
        let path = url.path
        let homePath = home.path
        let library = homePath + "/Library"
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        func under(_ base: String) -> Bool { path == base || path.hasPrefix(base + "/") }
        func strictlyUnder(_ base: String) -> Bool { path.hasPrefix(base + "/") }

        // Système et outils installés.
        for base in ["/System", "/usr", "/bin", "/sbin", "/private", "/Library", "/opt", "/cores"] where under(base) {
            return [Finding(mobility: .forbidden, text: "Fait partie du système ou d’outils installés : macOS en a besoin à cet endroit.")]
        }
        if path == "/" || path == homePath || path == library || path == "/Applications" || path == "/Users" {
            return [Finding(mobility: .forbidden, text: "C’est une racine du système : on ne déplace que ce qu’elle contient, au cas par cas.")]
        }

        // Zones protégées de l'utilisateur.
        if strictlyUnder(library + "/Containers") || strictlyUnder(library + "/Group Containers") {
            return [Finding(mobility: .forbidden,
                            text: "Données d’une appli isolée par macOS (bac à sable) : déplacées, l’appli ne les retrouverait plus.",
                            advice: "Si l’appli le permet, change son dossier de stockage depuis ses réglages.")]
        }
        if under(library + "/Mobile Documents") {
            return [Finding(mobility: .forbidden, text: "C’est iCloud Drive : le déplacer le retirerait d’iCloud.")]
        }
        for protected in ["Mail", "Messages", "Keychains", "Preferences", "Accounts", "Safari", "Cookies",
                          "Calendars", "HomeKit", "Photos", "Application Scripts"] where under(library + "/" + protected) {
            return [Finding(mobility: .forbidden, text: "Données personnelles gérées par macOS (\(protected)) : elles doivent rester sur le disque interne.")]
        }
        if under(homePath + "/.Trash") {
            return [Finding(mobility: .forbidden, text: "C’est la corbeille.", advice: "Vide-la plutôt : la place est rendue tout de suite.")]
        }

        // Bibliothèques gérées par une appli.
        if ["photoslibrary", "musiclibrary", "tvlibrary", "photolibrary", "aplibrary"].contains(ext) {
            if target?.format.keepsPermissions == false {
                return [Finding(mobility: .forbidden,
                                text: "Une bibliothèque Photos ou Musique ne fonctionne pas sur un disque \(target!.format.label).",
                                advice: "Formate une partie du disque en APFS pour l’y installer.")]
            }
            return [Finding(mobility: .discouraged, text: "Bibliothèque gérée par son appli.",
                            advice: "Déplace-la depuis l’appli elle-même (Photos › Réglages › Utiliser comme photothèque système).")]
        }
        if ext == "app" || (strictlyUnder("/Applications") && !path.dropFirst("/Applications/".count).contains("/")) {
            if target?.format.keepsPermissions == false {
                return [Finding(mobility: .forbidden,
                                text: "Une appli copiée sur \(target!.format.label) perd sa signature et ses droits : elle ne se lancerait plus.")]
            }
            return [Finding(mobility: .discouraged, text: "Une appli hors de son dossier Applications ne se met plus à jour correctement.",
                            advice: "Désinstalle-la si tu ne t’en sers plus.")]
        }

        // Ce qui se reforme : mieux vaut supprimer que déplacer.
        if Enclave.terrain(for: url) == .quarry {
            return [Finding(mobility: .discouraged, text: "Déblais de développement : ils se recréent tout seuls.",
                            advice: "Supprime-les plutôt que de les déplacer (npm install, la compilation… les recréent).")]
        }
        if under(library + "/Caches") || under(library + "/Logs") {
            return [Finding(mobility: .discouraged, text: "Caches et journaux se reforment seuls.",
                            advice: "Assèche-les plutôt : la place est rendue sans rien déplacer.")]
        }

        // Dossiers qu'une appli attend à un endroit précis : déplacement + lien symbolique.
        let linked: [(String, String)] = [
            (library + "/Application Support/MobileSync/Backup", "les sauvegardes d’iPhone et d’iPad"),
            (library + "/Android/sdk", "le SDK Android"),
            (homePath + "/.android/avd", "les émulateurs Android"),
            (homePath + "/.gradle", "les caches Gradle"),
            (library + "/Developer/CoreSimulator", "les simulateurs Xcode"),
            (library + "/Developer/Xcode/iOS DeviceSupport", "les symboles d’appareils Xcode"),
        ]
        for (base, label) in linked where under(base) {
            return [Finding(mobility: .withLink,
                            text: "Ce sont \(label) : l’outil les cherche à cet endroit. On les déplace et on laisse un lien à leur place.")]
        }
        if path.contains("/steamapps") {
            return [Finding(mobility: .discouraged, text: "Jeux gérés par Steam.",
                            advice: "Déplace-les depuis Steam › Réglages › Stockage : Steam garde ainsi le suivi des mises à jour.")]
        }
        if strictlyUnder(library + "/Application Support") {
            return [Finding(mobility: .withLink,
                            text: "Données d’une appli : elle les attend ici. On les déplace et on laisse un lien ; l’appli doit être fermée pendant l’opération.")]
        }
        if strictlyUnder(library) {
            return [Finding(mobility: .discouraged, text: "Réglages ou données internes d’une appli : le gain est rarement utile et le risque réel.")]
        }

        // Dossiers spéciaux eux-mêmes : on déplace leur contenu, pas le dossier.
        let special = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public"].map { homePath + "/" + $0 }
        if special.contains(path) {
            return [Finding(mobility: .discouraged, text: "Dossier spécial de macOS : le déplacer en entier dérouterait le Finder et les applis.",
                            advice: "Déplace plutôt ses sous-dossiers, un par un.")]
        }
        return []
    }

    // MARK: - Règles de contenu

    func contentRules(_ c: ContentReport) -> [Finding] {
        var findings: [Finding] = []
        if c.inICloud > 0 {
            findings.append(Finding(mobility: .forbidden,
                                    text: "\(c.inICloud) fichier\(c.inICloud > 1 ? "s sont synchronisés" : " est synchronisé") avec iCloud : le déplacer le retirerait d’iCloud."))
        }
        if c.files == 0 {
            findings.append(Finding(mobility: .free, text: "Dossier vide : rien à gagner à le déplacer."))
        }
        return findings
    }

    func targetRules(_ c: ContentReport, target: TargetVolume, needed: Int64) -> [Finding] {
        var findings: [Finding] = []
        let size = { (b: Int64) in ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
        if needed > target.freeBytes {
            findings.append(Finding(mobility: .forbidden,
                                    text: "Pas assez de place sur \(target.name) : il faut \(size(needed)), il reste \(size(target.freeBytes))."))
        }
        if let limit = target.format.maxFileSize, c.largestFile > limit {
            findings.append(Finding(mobility: .forbidden,
                                    text: "Un fichier dépasse 4 Go, la limite du format \(target.format.label)."))
        }
        if c.symlinks > 0, !target.format.keepsSymlinks {
            findings.append(Finding(mobility: .forbidden,
                                    text: "Contient \(c.symlinks) lien\(c.symlinks > 1 ? "s" : "") symbolique\(c.symlinks > 1 ? "s" : "") que le format \(target.format.label) ne sait pas garder."))
        }
        if c.isGitRepository, !target.format.keepsPermissions {
            findings.append(Finding(mobility: .discouraged,
                                    text: "Contient un dépôt git : sur \(target.format.label), les droits d’exécution des fichiers du projet seraient perdus.",
                                    advice: "Pousse-le sur GitHub puis supprime la copie locale, ou garde-le sur le disque interne."))
        } else if c.executables > 0, !target.format.keepsPermissions {
            findings.append(Finding(mobility: .discouraged,
                                    text: "Contient \(c.executables) programme\(c.executables > 1 ? "s" : "") ou script\(c.executables > 1 ? "s" : "") (\(c.executableSamples.joined(separator: ", "))\(c.executables > c.executableSamples.count ? "…" : "")) : sur \(target.format.label), \(c.executables > 1 ? "ils ne pourraient" : "il ne pourrait") plus s’exécuter."))
        }
        if !target.format.keepsSparseFiles, c.logicalBytes > c.allocatedBytes + c.allocatedBytes / 4, c.logicalBytes - c.allocatedBytes > 100_000_000 {
            findings.append(Finding(mobility: .free,
                                    text: "Fichiers creux : \(size(c.allocatedBytes)) ici, mais \(size(c.logicalBytes)) une fois sur \(target.format.label)."))
        }
        return findings
    }

    // MARK: - Parcours

    /// Beaucoup de fichiers téléchargés ou copiés portent le droit d'exécution sans raison
    /// (photos, PDF…). Ne compte comme programme que ce qui peut vraiment s'exécuter :
    /// pas d'extension (binaire, script), ou une extension de script ou de bibliothèque.
    static func looksRunnable(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty || ["sh", "command", "zsh", "bash", "py", "rb", "pl", "dylib", "so", "jnilib", "bin", "run"].contains(ext)
    }

    /// Parcourt le contenu une fois et relève tout ce qui compte pour un déplacement.
    public static func scan(_ url: URL) -> ContentReport {
        var report = ContentReport()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isExecutableKey, .fileSizeKey,
                                      .totalFileAllocatedSizeKey, .isUbiquitousItemKey]
        let keySet = Set(keys)
        func visit(_ item: URL, _ v: URLResourceValues?) {
            if v?.isSymbolicLink == true { report.symlinks += 1; return }
            if v?.isUbiquitousItem == true { report.inICloud += 1 }
            guard v?.isDirectory != true else {
                if item.lastPathComponent == ".git" { report.isGitRepository = true }
                return
            }
            report.files += 1
            let logical = Int64(v?.fileSize ?? 0)
            report.logicalBytes += logical
            report.allocatedBytes += Int64(v?.totalFileAllocatedSize ?? 0)
            report.largestFile = max(report.largestFile, logical)
            if v?.isExecutable == true, Self.looksRunnable(item) {
                report.executables += 1
                if report.executableSamples.count < 3 { report.executableSamples.append(item.lastPathComponent) }
            }
        }
        let rootValues = try? url.resourceValues(forKeys: keySet)
        guard rootValues?.isDirectory == true, rootValues?.isSymbolicLink != true else {
            visit(url, rootValues)
            return report
        }
        if rootValues?.isUbiquitousItem == true { report.inICloud += 1 }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                                        errorHandler: { _, _ in true })
        while let item = enumerator?.nextObject() as? URL {
            visit(item, try? item.resourceValues(forKeys: keySet))
        }
        return report
    }
}
