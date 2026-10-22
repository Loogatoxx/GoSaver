import Foundation
import Testing
@testable import GoSaverCore

/// Convois entre un faux dossier personnel et un faux « disque externe » (dossiers temporaires).
/// Le Lexar et le vrai dossier personnel ne sont jamais touchés.
@Suite("Convoi", .serialized)
struct ConvoyTests {
    final class Bench {
        let home: URL
        let harborDisk: URL
        init() throws {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("gosaver-convoy-\(UUID().uuidString)").resolvingSymlinksInPath()
            home = base.appendingPathComponent("home")
            harborDisk = base.appendingPathComponent("disque")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: harborDisk, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: home.deletingLastPathComponent()) }

        @discardableResult
        func file(_ path: String, bytes: Int = 4096, fill: UInt8 = 3) throws -> URL {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: fill, count: bytes).write(to: url)
            return url
        }
        var convoy: Convoy {
            Convoy(home: home, target: TargetVolume(url: harborDisk, name: "Test", format: .apfs, freeBytes: 10_000_000_000))
        }
    }

    @Test("Envoi simple : la copie arrive, l'original part, le registre note le convoi")
    func sendFree() throws {
        let bench = try Bench()
        try bench.file("Downloads/JPEG/a.jpg", bytes: 3_000_000)
        try bench.file("Downloads/JPEG/b.jpg")
        let source = bench.home.appendingPathComponent("Downloads/JPEG")

        let record = try bench.convoy.send(source)

        let arrived = bench.convoy.harbor.appendingPathComponent("Downloads/JPEG")
        #expect(FileManager.default.fileExists(atPath: arrived.appendingPathComponent("a.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(!record.linked)
        #expect(bench.convoy.records() == [record])
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path)
        #expect(leftovers.isEmpty, "ni copie partielle ni original mis de côté ne doivent rester")
    }

    @Test("Envoi avec lien : l'appli retrouve le dossier à son ancien emplacement")
    func sendWithLink() throws {
        let bench = try Bench()
        try bench.file("Library/Application Support/MobileSync/Backup/abc/Manifest.db")
        let source = bench.home.appendingPathComponent("Library/Application Support/MobileSync/Backup")

        let record = try bench.convoy.send(source)

        #expect(record.linked)
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: source.path)
        #expect(link == record.destination)
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("abc/Manifest.db").path))
    }

    @Test("Un élément interdit est refusé et rien ne bouge")
    func refused() throws {
        let bench = try Bench()
        try bench.file("Library/Containers/com.utmapp.UTM/Data/vm.img")
        let source = bench.home.appendingPathComponent("Library/Containers/com.utmapp.UTM")

        #expect(throws: Convoy.Failure.self) { try bench.convoy.send(source) }
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("Data/vm.img").path))
        #expect(bench.convoy.records().isEmpty)
    }

    @Test("Un original impossible à déplacer : la copie est effacée, l'original reste")
    func cannotSetAsideRollsBack() throws {
        let bench = try Bench()
        try bench.file("Documents/Verrou/a.txt")
        let parent = bench.home.appendingPathComponent("Documents")
        let source = parent.appendingPathComponent("Verrou")
        // Dossier parent en lecture seule : renommer l'original y est impossible.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }

        #expect(throws: Convoy.Failure.self) { try bench.convoy.send(source) }
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("a.txt").path))
        #expect(!FileManager.default.fileExists(atPath: bench.convoy.harbor.appendingPathComponent("Documents/Verrou").path))
    }

    @Test("La vérification repère une copie corrompue ou tronquée")
    func verificationCatchesCorruption() throws {
        let bench = try Bench()
        let a = try bench.file("A/f.bin", bytes: 3_000_000)
        let b = try bench.file("B/f.bin", bytes: 3_000_000)
        #expect(Convoy.difference(between: a.deletingLastPathComponent(), and: b.deletingLastPathComponent()) == nil)

        // Dernier octet modifié.
        let handle = try FileHandle(forWritingTo: b)
        try handle.seek(toOffset: 2_999_999)
        try handle.write(contentsOf: Data([9]))
        try handle.close()
        #expect(Convoy.difference(between: a.deletingLastPathComponent(), and: b.deletingLastPathComponent()) != nil)

        // Fichier tronqué.
        try Data(repeating: 3, count: 10).write(to: b)
        #expect(Convoy.difference(between: a.deletingLastPathComponent(), and: b.deletingLastPathComponent())?.contains("taille") == true)
    }

    @Test("Rapatriement : tout revient à sa place, le lien disparaît, le registre se vide")
    func bringBack() throws {
        let bench = try Bench()
        try bench.file("Library/Application Support/MobileSync/Backup/abc/Manifest.db", bytes: 2_000_000)
        let source = bench.home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        let record = try bench.convoy.send(source)

        try bench.convoy.bringBack(record)

        let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        #expect(values.isSymbolicLink == false && values.isDirectory == true)
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("abc/Manifest.db").path))
        #expect(!FileManager.default.fileExists(atPath: record.destination))
        #expect(bench.convoy.records().isEmpty)
    }

    @Test("Deux convois du même nom ne s'écrasent pas")
    func uniqueNames() throws {
        let bench = try Bench()
        try bench.file("Downloads/Lot/a")
        _ = try bench.convoy.send(bench.home.appendingPathComponent("Downloads/Lot"))
        try bench.file("Downloads/Lot/b")
        let second = try bench.convoy.send(bench.home.appendingPathComponent("Downloads/Lot"))
        #expect(second.destination.hasSuffix("Downloads/Lot (2)"))
    }

    @Test("Vrai disque exFAT (image de 64 Mo créée puis détruite)")
    func realExfatVolume() throws {
        let bench = try Bench()
        let image = bench.harborDisk.appendingPathComponent("test.dmg")
        let mount = bench.harborDisk.appendingPathComponent("monte")
        guard run("/usr/bin/hdiutil", ["create", "-size", "64m", "-fs", "ExFAT", "-volname", "GOSAVERTEST", image.path]) == 0,
              run("/usr/bin/hdiutil", ["attach", image.path, "-mountpoint", mount.path, "-nobrowse"]) == 0
        else { Issue.record("hdiutil indisponible"); return }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

        let target = try #require(TargetVolume.detect(mount))
        #expect(target.format == .exfat)
        try bench.file("Downloads/Photos/p1.jpg", bytes: 1_500_000)
        try bench.file("Downloads/Photos/p2.jpg", bytes: 700_000)
        let record = try Convoy(home: bench.home, target: target).send(bench.home.appendingPathComponent("Downloads/Photos"))

        #expect(FileManager.default.fileExists(atPath: record.destination + "/p1.jpg"))
        #expect(!FileManager.default.fileExists(atPath: bench.home.appendingPathComponent("Downloads/Photos").path))
    }

    private func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

@Suite("Convoi — rangement", .serialized)
struct ConvoyPlacementTests {
    typealias Bench = ConvoyTests.Bench

    @Test("Envoi dans un dossier choisi : il y arrive comme sous-dossier")
    func sendIntoFolder() throws {
        let bench = try Bench()
        try bench.file("Downloads/JPEG/a.jpg")
        let shelf = bench.harborDisk.appendingPathComponent("Archives/Images")
        try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)

        let record = try bench.convoy.send(bench.home.appendingPathComponent("Downloads/JPEG"), into: shelf)

        #expect(record.destination == shelf.appendingPathComponent("JPEG").path)
        #expect(FileManager.default.fileExists(atPath: shelf.appendingPathComponent("JPEG/a.jpg").path))
    }

    @Test("Fusion dans un dossier du même nom : rien n'est écrasé, et le rapatriement ne reprend que l'envoi")
    func mergeAndBringBack() throws {
        let bench = try Bench()
        try bench.file("Documents/IPT/cours.pdf", fill: 1)
        try bench.file("Documents/IPT/notes.txt", fill: 2)
        let existing = bench.harborDisk.appendingPathComponent("IPT")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 100).write(to: existing.appendingPathComponent("cours.pdf"))   // conflit
        try Data(repeating: 8, count: 100).write(to: existing.appendingPathComponent("ancien.txt"))

        let record = try bench.convoy.send(bench.home.appendingPathComponent("Documents/IPT"), into: existing, merge: true)

        let names = Set(try FileManager.default.contentsOfDirectory(atPath: existing.path))
        #expect(names == ["cours.pdf", "cours (depuis le Mac).pdf", "notes.txt", "ancien.txt"])
        #expect(try Data(contentsOf: existing.appendingPathComponent("cours.pdf")).first == 9, "l'ancien fichier n'est pas écrasé")
        #expect(record.mergedItems?["cours.pdf"] == "cours (depuis le Mac).pdf")

        try bench.convoy.bringBack(record)

        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: existing.path)) == ["cours.pdf", "ancien.txt"])
        let back = bench.home.appendingPathComponent("Documents/IPT")
        #expect(try Data(contentsOf: back.appendingPathComponent("cours.pdf")).first == 1)
        #expect(FileManager.default.fileExists(atPath: back.appendingPathComponent("notes.txt").path))
    }

    @Test("Reclassement : un renommage sur le disque, le registre et le lien suivent")
    func relocate() throws {
        let bench = try Bench()
        try bench.file("Library/Application Support/MobileSync/Backup/abc/Manifest.db")
        let source = bench.home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        let record = try bench.convoy.send(source)
        let shelf = bench.harborDisk.appendingPathComponent("Sauvegardes")
        try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)

        let moved = try bench.convoy.relocate(record, to: shelf)

        #expect(moved.destination == shelf.appendingPathComponent("Backup").path)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: source.path) == moved.destination)
        #expect(bench.convoy.records() == [moved])
        #expect(!FileManager.default.fileExists(atPath: record.destination))
    }
}

@Suite("Placement")
struct PlacementTests {
    final class Disk {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("gosaver-place-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        func files(_ dir: String, _ names: [String]) throws {
            let url = root.appendingPathComponent(dir)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for name in names { try Data([1]).write(to: url.appendingPathComponent(name)) }
        }
        func url(_ path: String) -> URL { root.appendingPathComponent(path) }
    }

    @Test("Des photos vont vers le dossier de photos, pas vers la musique")
    func photosGoToPhotos() throws {
        let disk = try Disk()
        try disk.files("Lexar/Pictures", (1...30).map { "p\($0).jpg" })
        try disk.files("Lexar/Musique", (1...30).map { "m\($0).mp3" })
        try disk.files("Mac/Downloads/JPEG", (1...10).map { "DSC\($0).jpg" })

        let best = Placement.index(disk.url("Lexar")).suggestions(for: disk.url("Mac/Downloads/JPEG")).first
        #expect(best?.folder.relativePath == "Pictures")
        #expect(best?.merges == false)
    }

    @Test("Un dossier du même nom à la racine est proposé en premier, en fusion")
    func sameNameMerges() throws {
        let disk = try Disk()
        try disk.files("Lexar/IPT/GSI", ["tp.pdf"])
        try disk.files("Lexar/Perso", ["a.pdf"])
        try disk.files("Mac/Documents/IPT", ["cours.pdf", "td.pdf"])

        let best = Placement.index(disk.url("Lexar")).suggestions(for: disk.url("Mac/Documents/IPT")).first
        #expect(best?.folder.relativePath == "IPT")
        #expect(best?.merges == true)
    }

    @Test("Un projet de code et ses sous-dossiers techniques ne sont jamais proposés")
    func projectsAreNotShelves() throws {
        let disk = try Disk()
        try disk.files("Lexar/Perso/Projet/appli", ["pubspec.yaml", "main.dart"])
        try disk.files("Lexar/Perso/Projet/appli/lib", ["a.dart", "b.dart"])
        try disk.files("Mac/Projets/site", ["index.js", "app.js"])

        let paths = Placement.index(disk.url("Lexar")).suggestions(for: disk.url("Mac/Projets/site")).map(\.folder.relativePath)
        #expect(!paths.contains("Perso/Projet/appli"))
        #expect(!paths.contains("Perso/Projet/appli/lib"))
    }

    @Test("Le dossier d'accueil de GoSaver n'est jamais proposé")
    func harborExcluded() throws {
        let disk = try Disk()
        try disk.files("Lexar/GoSaver Outre-mer/Downloads", ["x.jpg"])
        try disk.files("Mac/JPEG", ["y.jpg"])
        let paths = Placement.index(disk.url("Lexar")).suggestions(for: disk.url("Mac/JPEG")).map(\.folder.relativePath)
        #expect(paths.allSatisfy { !$0.hasPrefix("GoSaver Outre-mer") })
    }
}
