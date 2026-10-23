import Foundation

/// Une zone du disque à relever, avec le terrain qu'on lui attribue.
/// Les zones s'emboîtent (`~/Library/Caches` est dans `~/Library`, lui-même dans `~`) :
/// le relevé ne compte chaque octet qu'une fois, dans la zone la plus précise.
public struct Zone: Sendable, Hashable {
    public let root: URL
    public let terrain: Terrain
    public let label: String
    /// Vrai : chaque sous-dossier devient un lieu à part sur la carte.
    /// Faux : la zone entière forme un seul lieu.
    public let splitsIntoPlaces: Bool

    public init(_ root: URL, _ terrain: Terrain, _ label: String, split: Bool = true) {
        self.root = root.standardizedFileURL
        self.terrain = terrain
        self.label = label
        self.splitsIntoPlaces = split
    }

    /// Le découpage standard d'un Mac, pour l'utilisateur `home`.
    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Zone] {
        let h = { (path: String) in home.appendingPathComponent(path) }
        var zones: [Zone] = [
            Zone(h("Library/Caches"), .marsh, "Caches"),
            Zone(h("Library/Logs"), .marsh, "Journaux", split: false),
            Zone(h("Library/Developer"), .quarry, "Outils Apple"),
            Zone(h("Library/Android"), .quarry, "Android"),
            Zone(h(".gradle"), .quarry, "Gradle", split: false),
            Zone(h(".npm"), .quarry, "npm", split: false),
            Zone(h(".cache"), .quarry, "Caches d’outils"),
            Zone(h(".m2"), .quarry, "Maven", split: false),
            Zone(h(".cocoapods"), .quarry, "CocoaPods", split: false),
            Zone(h(".android"), .quarry, "Émulateurs Android"),
            Zone(h(".nvm"), .quarry, "Versions de Node", split: false),
            Zone(h("Downloads"), .delta, "Téléchargements"),
            Zone(h("Desktop"), .fields, "Bureau"),
            Zone(h("Documents"), .fields, "Documents"),
            Zone(h("Pictures"), .forest, "Images"),
            Zone(h("Movies"), .forest, "Vidéos"),
            Zone(h("Music"), .forest, "Musique"),
            Zone(h(".Trash"), .shore, "Corbeille", split: false),
            // Ces trois dossiers pèsent souvent des dizaines de Go : on les découpe appli par appli.
            Zone(h("Library/Containers"), .city, "Conteneurs d’applis"),
            Zone(h("Library/Group Containers"), .city, "Conteneurs partagés"),
            Zone(h("Library/Application Support"), .city, "Données des applications"),
            Zone(h("Library"), .city, "Bibliothèque"),
            Zone(home, .fields, "Dossier personnel"),
            Zone(URL(fileURLWithPath: "/Applications"), .city, "Applications"),
            Zone(URL(fileURLWithPath: "/Library"), .city, "Bibliothèque système"),
            Zone(URL(fileURLWithPath: "/opt/homebrew"), .quarry, "Homebrew", split: false),
            Zone(URL(fileURLWithPath: "/usr/local"), .quarry, "Outils /usr/local", split: false),
        ]
        // Caches et fichiers temporaires « cachés » de macOS, propres à l'utilisateur
        // (sous /private/var/folders) : souvent plusieurs Go que le Finder ne montre jamais.
        if let cache = darwinDirectory(_CS_DARWIN_USER_CACHE_DIR) {
            zones.insert(Zone(cache, .marsh, "Caches système de l’utilisateur", split: false), at: 0)
        }
        if let temp = darwinDirectory(_CS_DARWIN_USER_TEMP_DIR) {
            zones.insert(Zone(temp, .marsh, "Fichiers temporaires", split: false), at: 0)
        }
        return zones.filter { FileManager.default.fileExists(atPath: $0.root.path) }
    }

    /// Lit un dossier système de l'utilisateur via `confstr` (API C de macOS).
    private static func darwinDirectory(_ name: Int32) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(name, &buffer, buffer.count) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// Enclave : un dossier reconnu où qu'il soit, qui change de terrain par rapport à sa zone.
/// Ex. un `node_modules` dans Documents compte en Carrières, pas en Champs ;
/// le `Library/Caches` d'une appli dans Containers compte en Marais, pas en Cités.
public enum Enclave {
    /// Dossiers de déblais de développement.
    public static let quarryNames: Set<String> = [
        "node_modules", "DerivedData", ".gradle", "Pods", ".venv", "venv",
        "__pycache__", ".next", ".nuxt", ".turbo", ".parcel-cache", ".build", ".dart_tool",
    ]

    /// Un dossier « build » n'est un déblai que s'il est le résultat de compilation d'un projet :
    /// l'un de ces fichiers doit se trouver juste à côté. Sinon, ce peut être de vrais fichiers.
    public static let buildProjectMarkers = ["pubspec.yaml", "build.gradle", "build.gradle.kts", "settings.gradle",
                                             "settings.gradle.kts", "CMakeLists.txt", "Package.swift"]

    /// Terrain d'enclave pour ce dossier, ou `nil` s'il suit sa zone.
    public static func terrain(for directory: URL) -> Terrain? {
        let name = directory.lastPathComponent
        if quarryNames.contains(name) { return .quarry }
        if name == "build" {
            let project = directory.deletingLastPathComponent()
            if buildProjectMarkers.contains(where: { FileManager.default.fileExists(atPath: project.appendingPathComponent($0).path) }) {
                return .quarry
            }
        }
        let parent = directory.deletingLastPathComponent().lastPathComponent
        if parent == "Library", name == "Caches" || name == "Logs" { return .marsh }
        return nil
    }
}
