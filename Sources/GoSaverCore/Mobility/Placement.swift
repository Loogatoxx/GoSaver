import Foundation

/// Grandes familles de fichiers, reconnues à leur extension.
public enum FileKind: String, CaseIterable, Sendable, Codable {
    case images, videos, audio, documents, code, archives, games, apps, other

    public var label: String {
        switch self {
        case .images: "images"
        case .videos: "vidéos"
        case .audio: "morceaux de musique"
        case .documents: "documents"
        case .code: "fichiers de code"
        case .archives: "archives et images disque"
        case .games: "jeux"
        case .apps: "applis"
        case .other: "fichiers divers"
        }
    }

    static let byExtension: [String: FileKind] = {
        var map: [String: FileKind] = [:]
        let table: [(FileKind, [String])] = [
            (.images, ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "raw", "cr2", "cr3", "nef", "arw", "dng", "webp", "bmp", "psd", "svg"]),
            (.videos, ["mov", "mp4", "m4v", "avi", "mkv", "webm", "mts", "m2ts", "braw", "prproj", "drp"]),
            (.audio, ["mp3", "m4a", "flac", "wav", "aac", "ogg", "aiff", "aif", "alac", "opus", "wma"]),
            (.documents, ["pdf", "doc", "docx", "odt", "rtf", "txt", "md", "pages", "key", "ppt", "pptx", "xls", "xlsx", "numbers", "csv", "epub", "odp", "ods"]),
            (.code, ["swift", "kt", "kts", "java", "py", "js", "ts", "tsx", "jsx", "c", "cpp", "h", "hpp", "cs", "go", "rs", "dart", "gradle", "json", "yml", "yaml", "xml", "html", "css", "sh", "ipynb", "sql", "php", "rb", "lock"]),
            (.archives, ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso", "pkg", "img", "vhd", "vhdx", "qcow2", "utm"]),
            (.games, ["jar", "mcpack", "mcworld", "mcaddon", "gba", "gbc", "nds", "smc", "sfc", "nes", "n64", "z64", "sav", "ips", "bps", "3ds", "cia", "xci", "nsp"]),
            (.apps, ["app", "exe", "msi", "apk", "ipa", "aab"]),
        ]
        for (kind, extensions) in table { for ext in extensions { map[ext] = kind } }
        return map
    }()

    public static func of(_ url: URL) -> FileKind {
        byExtension[url.pathExtension.lowercased()] ?? .other
    }

    /// Mots de dossier qui annoncent une famille (« Pictures », « Musique », « Jeux »…).
    static let lexicon: [FileKind: Set<String>] = [
        .images: ["pictures", "picture", "photos", "photo", "images", "image", "jpeg", "jpg", "png", "wallpapers", "fonds", "captures", "screenshots", "dcim", "camera"],
        .videos: ["movies", "movie", "videos", "video", "films", "film", "clips", "montage", "rushes", "capcut", "davinci"],
        .audio: ["music", "musique", "musiques", "audio", "sons", "son", "albums", "podcasts", "samples"],
        .documents: ["documents", "document", "docs", "cours", "ipt", "ecole", "school", "fac", "pdf", "papiers", "factures", "notes", "devoirs"],
        .code: ["projet", "projets", "projects", "project", "dev", "code", "development", "sources", "repos", "github", "studio", "androidstudioproject", "clionprojects", "vscode"],
        .archives: ["archives", "archive", "backup", "backups", "sauvegardes", "iso", "images-disque", "vm", "utm"],
        .games: ["gaming", "games", "game", "jeux", "jeu", "retro", "roms", "minecraft", "steam", "pokemon"],
        .apps: ["applications", "apps", "installeurs", "installers"],
    ]
}

/// Répartition des fichiers d'un dossier par famille.
public struct KindProfile: Sendable, Equatable {
    public var counts: [FileKind: Int] = [:]
    public var total: Int { counts.values.reduce(0, +) }

    public mutating func add(_ kind: FileKind, _ n: Int = 1) { counts[kind, default: 0] += n }

    /// Famille dominante, si elle pèse au moins 40 % des fichiers.
    public var dominant: FileKind? {
        guard total > 0, let top = counts.filter({ $0.key != .other }).max(by: { $0.value < $1.value }),
              Double(top.value) / Double(total) >= 0.4 else { return nil }
        return top.key
    }

    /// Ressemblance de deux répartitions (cosinus, entre 0 et 1), sans la famille « divers ».
    public func similarity(to other: KindProfile) -> Double {
        let kinds = FileKind.allCases.filter { $0 != .other }
        let a = kinds.map { Double(counts[$0] ?? 0) }, b = kinds.map { Double(other.counts[$0] ?? 0) }
        let dot = zip(a, b).map(*).reduce(0, +)
        let na = sqrt(a.map { $0 * $0 }.reduce(0, +)), nb = sqrt(b.map { $0 * $0 }.reduce(0, +))
        return na == 0 || nb == 0 ? 0 : dot / (na * nb)
    }

    /// Profil d'un dossier, en n'examinant pas plus de `limit` fichiers (échantillon).
    public static func of(_ url: URL, limit: Int = 600) -> KindProfile {
        var profile = KindProfile()
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if values?.isDirectory != true || values?.isPackage == true {
            profile.add(FileKind.of(url))
            return profile
        }
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true })
        var seen = 0
        while let item = enumerator?.nextObject() as? URL, seen < limit {
            let v = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            guard v?.isDirectory != true || v?.isPackage == true else { continue }
            profile.add(FileKind.of(item))
            seen += 1
        }
        return profile
    }
}

/// Un dossier du disque externe, candidat pour accueillir un envoi.
public struct HarborFolder: Sendable, Equatable {
    public let url: URL
    /// Chemin depuis la racine du disque (« Archives/Downloads-images-2026-09 »).
    public let relativePath: String
    public let depth: Int
    public let profile: KindProfile
    /// Le dossier est lui-même un projet (contient .git, pubspec.yaml…) : jamais proposé comme étagère.
    public var isProject = false
}

/// Une proposition de destination, avec ses raisons en clair.
public struct PlacementSuggestion: Sendable, Equatable, Identifiable {
    public var id: String { folder.url.path }
    public let folder: HarborFolder
    public let score: Double
    public let reasons: [String]
    /// Le dossier porte le même nom que l'envoi : on y verse le contenu au lieu de créer un sous-dossier.
    public var merges = false
}

/// Range les envois au bon endroit : indexe les dossiers du disque externe, puis classe
/// les candidats pour un dossier donné. Règles explicables ; l'IA pourra ensuite reformuler.
public struct Placement: Sendable {
    public let folders: [HarborFolder]

    /// Dossiers jamais proposés : système, corbeilles Windows, bundles, résultats de compilation.
    static let excludedNames: Set<String> = ["System Volume Information", "$RECYCLE.BIN", ".Trashes", ".Spotlight-V100",
                                             ".fseventsd", "build", "node_modules", ".git", "Pods", "DerivedData"]
    /// Sous-dossiers techniques (plateformes d'un projet Flutter, sources…) : jamais des étagères,
    /// sauf à la racine du disque (un dossier « Android » à la racine est un vrai rayonnage).
    static let technicalNames: Set<String> = ["android", "ios", "macos", "windows", "linux", "web", "lib", "test", "tests",
                                              "src", "app", "gradle", "res", "assets", "bin", "obj", "runner", "include"]
    /// Un dossier qui contient l'un de ces fichiers est un projet : on ne propose pas d'entrer dedans.
    static let projectMarkers: Set<String> = [".git", "pubspec.yaml", "build.gradle", "build.gradle.kts", "package.json",
                                              "Package.swift", "CMakeLists.txt", "pom.xml", "Cargo.toml", "settings.gradle"]

    public init(folders: [HarborFolder]) { self.folders = folders }

    /// Indexe les dossiers du disque jusqu'à `maxDepth` niveaux (lecture seule).
    public static func index(_ root: URL, maxDepth: Int = 3, sampleLimit: Int = 400) -> Placement {
        var folders: [HarborFolder] = []
        func visit(_ url: URL, depth: Int, relative: String) {
            guard depth <= maxDepth else { return }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles])) ?? []
            let names = Set(children.map(\.lastPathComponent))
            let isProject = !names.isDisjoint(with: projectMarkers)
            for child in children {
                let v = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                guard v?.isDirectory == true, v?.isPackage != true,
                      !excludedNames.contains(child.lastPathComponent)
                else { continue }
                let path = relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent
                let inside = Set((try? FileManager.default.contentsOfDirectory(atPath: child.path)) ?? [])
                folders.append(HarborFolder(url: child, relativePath: path, depth: depth,
                                            profile: KindProfile.of(child, limit: sampleLimit),
                                            isProject: !inside.isDisjoint(with: projectMarkers)))
                // On n'entre pas dans un projet de code : ses sous-dossiers ne sont pas des rayonnages.
                if !isProject { visit(child, depth: depth + 1, relative: path) }
            }
        }
        visit(root, depth: 1, relative: "")
        return Placement(folders: folders)
    }

    /// Les meilleures destinations pour `source`, de la plus adaptée à la moins adaptée.
    public func suggestions(for source: URL, sourceProfile: KindProfile? = nil, limit: Int = 3) -> [PlacementSuggestion] {
        let profile = sourceProfile ?? KindProfile.of(source)
        let sourceTokens = Self.tokens(source.lastPathComponent)
            .union(Self.tokens(source.deletingLastPathComponent().lastPathComponent))
        let dominant = profile.dominant

        let sourceName = Self.tokens(source.lastPathComponent)
        let backupWords: Set<String> = ["backup", "backups", "sauvegarde", "sauvegardes", "pad"]
        let sourceIsBackup = !sourceTokens.isDisjoint(with: backupWords)

        var ranked: [PlacementSuggestion] = []
        for folder in folders where !folder.isProject
            && !(folder.depth > 1 && Self.technicalNames.contains(folder.url.lastPathComponent.lowercased()))
            && folder.relativePath != "GoSaver Outre-mer" && !folder.relativePath.hasPrefix("GoSaver Outre-mer/") {
            var reasons: [String] = []
            let folderTokens = Self.tokens(folder.relativePath)
            let ownName = Self.tokens(folder.url.lastPathComponent)

            // 0. Même nom que l'envoi, près de la racine : c'est son rayonnage naturel, on y verse
            // le contenu. (Plus profond, un même nom est souvent une coïncidence : un album « MUSIC ».)
            let sameName = !sourceName.isEmpty && ownName == sourceName && folder.depth <= 2
            if sameName { reasons.append("Porte le même nom : le contenu y sera ajouté, sans créer de doublon de dossier.") }

            // 1. Contenu semblable.
            let similarity = profile.similarity(to: folder.profile)
            if similarity > 0.6, let kind = dominant, let count = folder.profile.counts[kind], count > 0 {
                reasons.append("Contient déjà surtout des \(kind.label)\(folder.profile.total >= 400 ? " (plus de 400 fichiers)" : " (\(count) fichiers)").")
            }
            // 2. Le nom du dossier annonce la bonne famille.
            var lexicon = 0.0
            if let kind = dominant, let words = FileKind.lexicon[kind], let word = folderTokens.first(where: words.contains) {
                lexicon = 1
                reasons.append("Son nom (« \(word) ») annonce des \(kind.label).")
            }
            // 3. Mots en commun avec le dossier envoyé ou son dossier d'origine.
            let shared = sourceTokens.intersection(folderTokens).filter { $0.count >= 3 }
            if !sameName, let word = shared.sorted().first { reasons.append("Même mot dans le nom : « \(word) ».") }
            let overlap = shared.isEmpty ? 0.0 : min(1, Double(shared.count) / 2)

            // 4. Un vrai rayonnage : assez rempli, ni la racine, ni un recoin.
            let depthFit: Double = folder.depth == 1 ? 0.6 : folder.depth == 2 ? 1 : 0.6
            let fullness = min(1, log10(Double(folder.profile.total) + 1) / 2.3)

            var score = 0.40 * similarity + 0.28 * lexicon + 0.20 * overlap + 0.06 * depthFit + 0.12 * fullness
            if sameName { score += folder.depth == 1 ? 0.6 : 0.35 }
            // 5. Une sauvegarde d'appareil n'est pas une étagère, sauf pour ranger une sauvegarde.
            if !sourceIsBackup, !folderTokens.isDisjoint(with: backupWords) { score *= 0.6 }
            guard !reasons.isEmpty, score > 0.3 else { continue }
            ranked.append(PlacementSuggestion(folder: folder, score: score, reasons: reasons, merges: sameName))
        }
        return Array(ranked.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Mots d'un nom : minuscules, sans accents, découpés sur tout ce qui n'est pas une lettre.
    static func tokens(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr"))
        let words = folded.split { !$0.isLetter }.map(String.init).filter { $0.count >= 2 }
        // Singulier ajouté pour que « Projets » retrouve « Projet » (et « images », « image »).
        return Set(words + words.filter { $0.count > 4 && $0.hasSuffix("s") }.map { String($0.dropLast()) })
    }
}
