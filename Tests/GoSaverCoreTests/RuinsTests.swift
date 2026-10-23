import Foundation
import Testing
@testable import GoSaverCore

/// Ruines : faux dossier personnel, fausses applis installées. Lecture seule.
@Suite("Ruines")
struct RuinsTests {
    final class Home {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("gosaver-ruins-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        @discardableResult
        func file(_ path: String, _ data: Data, age days: Double = 0) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            if days > 0 {
                // Le fichier et tous ses dossiers parents (jusqu'au faux dossier personnel) prennent cet âge.
                let date = Date().addingTimeInterval(-days * 86_400)
                var current = url
                while current.path.count > root.path.count {
                    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: current.path)
                    current = current.deletingLastPathComponent()
                }
            }
            return url
        }
    }

    static let apps = [InstalledApp(bundleID: "com.brave.Browser", name: "Brave Browser"),
                       InstalledApp(bundleID: "eu.pokemmo.client", name: "PokeMMO")]

    func dig(_ home: Home) -> [Ruin] { Archaeologist(home: home.root, apps: Self.apps).excavate() }

    @Test("Les données d'une appli désinstallée, intactes depuis longtemps, sont à isoler")
    func orphan() throws {
        let home = try Home()
        try home.file("Library/Application Support/com.isaacmarovitz.Whisky/Bottles/b.img", Data(count: 2_000_000), age: 200)
        let ruin = try #require(dig(home).first { $0.kind == .orphanAppData })
        #expect(ruin.verdict == .isolate)
        #expect(ruin.summary.contains("Whisky"))
    }

    @Test("Les données d'une appli installée ne sont jamais signalées (BraveSoftware ↔ Brave Browser)")
    func installedOwner() throws {
        let home = try Home()
        try home.file("Library/Application Support/BraveSoftware/x", Data(count: 2_000_000), age: 400)
        try home.file("Library/Application Support/com.apple.something/x", Data(count: 2_000_000), age: 400)
        #expect(dig(home).filter { $0.kind == .orphanAppData }.isEmpty)
    }

    @Test("Des données récentes d'une appli absente ne sont pas encore des ruines")
    func recentNotOrphan() throws {
        let home = try Home()
        try home.file("Library/Application Support/OutilRecent/x", Data(count: 2_000_000), age: 10)
        #expect(dig(home).filter { $0.kind == .orphanAppData }.isEmpty)
    }

    @Test("Doublon : seule la copie (« (1) ») est signalée, et seulement si le contenu est identique")
    func duplicates() throws {
        let home = try Home()
        let content = Data((0..<80_000).map { UInt8(truncatingIfNeeded: $0) })
        try home.file("Downloads/rapport.pdf", content)
        try home.file("Downloads/rapport (1).pdf", content)
        var other = content; other[100] = 0xFF
        try home.file("Downloads/version-2.pdf", other)   // même taille, contenu différent

        let found = dig(home).filter { $0.kind == .duplicate }
        #expect(found.map(\.url.lastPathComponent) == ["rapport (1).pdf"])
    }

    @Test("Installeur d'une appli installée, et téléchargement interrompu")
    func installersAndPartials() throws {
        let home = try Home()
        try home.file("Downloads/PokeMMO-v62.dmg", Data(repeating: 1, count: 60_000), age: 10)
        try home.file("Downloads/InconnuSetup.dmg", Data(repeating: 2, count: 60_000), age: 10)
        try home.file("Downloads/film.mp4.crdownload", Data(repeating: 3, count: 60_000), age: 5)
        let ruins = dig(home)
        #expect(ruins.contains { $0.kind == .usedInstaller && $0.url.lastPathComponent == "PokeMMO-v62.dmg" })
        #expect(!ruins.contains { $0.url.lastPathComponent == "InconnuSetup.dmg" })
        #expect(ruins.contains { $0.kind == .partialDownload })
    }

    @Test("Un « .ts » est reconnu à son contenu : vidéo MPEG-TS ou code TypeScript")
    func ambiguousTs() throws {
        let home = try Home()
        var video = Data(count: 1_200)
        for i in stride(from: 0, to: video.count, by: 188) { video[i] = 0x47 }
        try home.file("Downloads/flux.ts", video)
        try home.file("Downloads/script.ts", Data("import { x } from './y';\nconst a = 1;".utf8))

        let ruins = dig(home).filter { $0.kind == .stray }
        let flux = try #require(ruins.first { $0.url.lastPathComponent == "flux.ts" })
        let script = try #require(ruins.first { $0.url.lastPathComponent == "script.ts" })
        #expect(flux.clues.content == "vidéo (flux MPEG-TS)")
        #expect(script.clues.content == "code source (texte)")
        #expect(flux.verdict == .examine, "l'expertise enquête mais ne tranche pas seule")
    }

    @Test("La provenance et l'appli de téléchargement sont lues dans les attributs de macOS")
    func provenance() throws {
        let home = try Home()
        let url = try home.file("Downloads/hook.js", Data("const a = 1".utf8))
        let quarantine = "0083;6512abcd;Brave Browser;ABC"
        _ = quarantine.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["https://www.github.com/a/b"], format: .binary, options: 0)
        _ = plist.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, plist.count, 0, 0) }

        let clues = Clues.gather(url)
        #expect(clues.downloadedBy == "Brave Browser")
        #expect(clues.downloadedFrom == "github.com")
        #expect(Archaeologist.describe(clues).contains("téléchargé depuis github.com avec Brave Browser"))
    }
}

@Suite("Appartenance à une appli")
struct OwnershipTests {
    let a = Archaeologist(home: URL(fileURLWithPath: "/Users/x"), apps: [
        InstalledApp(bundleID: "com.anthropic.claudefordesktop", name: "Claude"),
        InstalledApp(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
        InstalledApp(bundleID: "com.brave.Browser", name: "Brave Browser"),
    ])
    func owner(_ path: String) -> String? { a.ownerApp(for: URL(fileURLWithPath: path))?.name }

    @Test("Paquet, données, conteneurs et extensions retrouvent leur appli")
    func owners() {
        #expect(owner("/Applications/Claude.app") == "Claude")
        #expect(owner("/Users/x/Library/Application Support/Claude") == "Claude")
        #expect(owner("/Users/x/Library/Application Support/BraveSoftware") == "Brave Browser")
        #expect(owner("/Users/x/Library/Containers/ru.keepcoder.Telegram.TelegramShare") == "Telegram")
        #expect(owner("/Users/x/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram") == "Telegram")
    }

    @Test("Rien n'est rattaché par ressemblance lointaine")
    func noFalseOwner() {
        #expect(owner("/Users/x/Library/Containers/ru.keepcoder.TelegramX") == nil)
        #expect(owner("/Users/x/Documents/Claude") == nil)
        #expect(owner("/Applications/Claudette.app") == nil)
    }
}
