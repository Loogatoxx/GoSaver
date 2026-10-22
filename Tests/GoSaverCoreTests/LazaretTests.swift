import Foundation
import Testing
@testable import GoSaverCore

/// Lazaret sur un faux dossier personnel et un faux disque. Rien de réel n'est touché.
@Suite("Lazaret", .serialized)
struct LazaretTests {
    typealias Bench = ConvoyTests.Bench

    func lazaret(_ bench: Bench, format: TargetVolume.Format = .apfs) -> Lazaret {
        Lazaret(home: bench.home, target: TargetVolume(url: bench.harborDisk, name: "Test", format: format, freeBytes: 10_000_000_000))
    }

    @Test("Mise au Lazaret : le Mac est libéré, l'élément est rangé par jour, avec 30 jours de délai")
    func quarantine() throws {
        let bench = try Bench()
        try bench.file("Downloads/vieux/a.zip", bytes: 2_000_000)
        let now = Date(timeIntervalSince1970: 1_792_000_000)

        let entry = try lazaret(bench).quarantine(bench.home.appendingPathComponent("Downloads/vieux"), now: now)

        #expect(!FileManager.default.fileExists(atPath: bench.home.appendingPathComponent("Downloads/vieux").path))
        #expect(entry.stored.contains("/GoSaver Lazaret/\(Lazaret.dayFormatter.string(from: now))/vieux"))
        #expect(FileManager.default.fileExists(atPath: entry.stored + "/a.zip"))
        #expect(entry.daysLeft(now: now) == 30)
        #expect(lazaret(bench).entries() == [entry])
    }

    @Test("Restauration : tout revient à sa place et le Lazaret se vide")
    func restore() throws {
        let bench = try Bench()
        try bench.file("Documents/brouillon/texte.md", bytes: 3000)
        let source = bench.home.appendingPathComponent("Documents/brouillon")
        let entry = try lazaret(bench).quarantine(source)

        try lazaret(bench).restore(entry)

        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("texte.md").path))
        #expect(!FileManager.default.fileExists(atPath: entry.stored))
        #expect(lazaret(bench).entries().isEmpty)
    }

    @Test("Au bout du délai, seul ce qui a expiré est supprimé")
    func purge() throws {
        let bench = try Bench()
        try bench.file("Downloads/ancien/a", bytes: 1000)
        try bench.file("Downloads/recent/b", bytes: 1000)
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        let old = try lazaret(bench).quarantine(bench.home.appendingPathComponent("Downloads/ancien"), now: start)
        let fresh = try lazaret(bench).quarantine(bench.home.appendingPathComponent("Downloads/recent"),
                                                  now: start.addingTimeInterval(20 * 86_400))

        let purged = lazaret(bench).purgeExpired(now: start.addingTimeInterval(31 * 86_400))

        #expect(purged.map(\.id) == [old.id])
        #expect(!FileManager.default.fileExists(atPath: old.stored))
        #expect(FileManager.default.fileExists(atPath: fresh.stored))
        #expect(lazaret(bench).entries().map(\.id) == [fresh.id])
    }

    @Test("Le système et les applis isolées ne vont jamais au Lazaret")
    func forbiddenStaysForbidden() throws {
        let bench = try Bench()
        try bench.file("Library/Containers/com.example/Data/x")
        #expect(throws: Convoy.Failure.self) {
            try lazaret(bench).quarantine(bench.home.appendingPathComponent("Library/Containers/com.example"))
        }
        #expect(FileManager.default.fileExists(atPath: bench.home.appendingPathComponent("Library/Containers/com.example/Data/x").path))
    }

    @Test("Un projet de code (déconseillé à l'Outre-mer) peut quand même partir au Lazaret")
    func discouragedIsAccepted() throws {
        let bench = try Bench()
        let script = try bench.file("Projets/vieux-site/build.sh")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let entry = try lazaret(bench, format: .exfat).quarantine(bench.home.appendingPathComponent("Projets/vieux-site"))
        #expect(FileManager.default.fileExists(atPath: entry.stored + "/build.sh"))
    }

    @Test("La suppression immédiate ne touche que le Lazaret")
    func discardNow() throws {
        let bench = try Bench()
        try bench.file("Downloads/x/a")
        let entry = try lazaret(bench).quarantine(bench.home.appendingPathComponent("Downloads/x"))
        try lazaret(bench).discardNow(entry)
        #expect(!FileManager.default.fileExists(atPath: entry.stored))
        let forged = Lazaret.Entry(original: "/x", stored: bench.home.appendingPathComponent("Documents").path,
                                   bytes: 0, files: 0, date: Date(), expires: Date())
        #expect(throws: Convoy.Failure.self) { try lazaret(bench).discardNow(forged) }
    }
}

@Suite("Lazaret — règles")
struct LazaretRuleTests {
    private func verdict(contents: ContentReport?) -> MobilityVerdict {
        MobilityVerdict(mobility: .forbidden, reason: "x", advice: nil, notes: [], contents: contents, bytesOnTarget: nil)
    }

    @Test("Un fichier synchronisé avec iCloud reste bloqué (il disparaîtrait de tous les appareils)")
    func iCloudBlocks() {
        var c = ContentReport(); c.inICloud = 1
        #expect(!Lazaret.onlyBlockedByMobilityConcerns(verdict(contents: c)))
    }

    @Test("Un refus d'emplacement reste bloquant, un refus de place ou de liens est revérifié")
    func placeVersContent() {
        #expect(!Lazaret.onlyBlockedByMobilityConcerns(verdict(contents: nil)))
        var c = ContentReport(); c.symlinks = 3
        #expect(Lazaret.onlyBlockedByMobilityConcerns(verdict(contents: c)))
    }
}

@Suite("Droits au retour d'un disque exFAT", .serialized)
struct PermissionTests {
    @Test("Les fichiers restaurés retrouvent des droits de document ordinaire")
    func normalized() throws {
        let bench = try ConvoyTests.Bench()
        let file = try bench.file("Retour/doc.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        let convoy = Convoy(home: bench.home, target: TargetVolume(url: bench.harborDisk, name: "T", format: .exfat, freeBytes: 1 << 30))
        convoy.normalizePermissions(file.deletingLastPathComponent())
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o644)
    }
}
