import Foundation
import Testing
@testable import GoSaverCore

/// Tous ces tests travaillent dans un faux dossier personnel temporaire.
/// Le vrai disque n'est jamais touché.
@Suite("Assèchement")
struct DrainageTests {
    final class FakeHome {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("gosaver-drain-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        @discardableResult
        func file(_ path: String, kilobytes: Int = 16) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: kilobytes * 1024).write(to: url)
            return url
        }
        func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) }
    }

    @Test("Le contenu des caches part, les racines restent")
    func drainsContentNotRoots() throws {
        let home = try FakeHome()
        try home.file("Library/Caches/com.example.app/blob")
        try home.file("Library/Logs/app.log")
        let drainer = Drainer.standard(home: home.root)

        let plan = drainer.plan(kinds: [.cache, .log])
        #expect(plan.items.count == 2)
        let result = drainer.execute(plan)

        #expect(result.removedCount == 2)
        #expect(result.failures.isEmpty)
        #expect(!home.exists("Library/Caches/com.example.app"))
        #expect(home.exists("Library/Caches"))
        #expect(home.exists("Library/Logs"))
    }

    @Test("Un lien piégé vers les documents ne détruit jamais sa cible")
    func symlinkTargetIsNeverTouched() throws {
        let home = try FakeHome()
        let precious = try home.file("Documents/memoire.pdf")
        try FileManager.default.createDirectory(at: home.root.appendingPathComponent("Library/Caches"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: home.root.appendingPathComponent("Library/Caches/piege"),
            withDestinationURL: precious.deletingLastPathComponent())

        let drainer = Drainer.standard(home: home.root)
        _ = drainer.execute(drainer.plan())

        #expect(FileManager.default.fileExists(atPath: precious.path))
    }

    @Test("Un chemin hors des racines est refusé à l'exécution")
    func refusesOutsideRoots() throws {
        let home = try FakeHome()
        let precious = try home.file("Documents/notes.txt")
        let drainer = Drainer.standard(home: home.root)
        let forged = Drainer.Plan(
            items: [.init(url: precious, kind: .cache, bytes: 16_384, owner: "x")], inUse: [], unreadable: [])

        let result = drainer.execute(forged)

        #expect(result.removedCount == 0)
        #expect(result.failures.count == 1)
        #expect(FileManager.default.fileExists(atPath: precious.path))
        #expect(!drainer.isSafe(home.root.appendingPathComponent("Library/Caches")))
    }

    @Test("Les caches d'une appli ouverte sont laissés en place")
    func skipsRunningApps() throws {
        let home = try FakeHome()
        try home.file("Library/Caches/BraveSoftware/cache")
        try home.file("Library/Caches/com.other.app/cache")
        try home.file("Library/Containers/com.utmapp.UTM/Data/Library/Caches/x")
        let drainer = Drainer.standard(home: home.root)

        let plan = drainer.plan(running: [
            RunningApp(bundleID: "com.brave.Browser", name: "Brave Browser"),
            RunningApp(bundleID: "com.utmapp.UTM", name: "UTM"),
        ])

        #expect(plan.items.map(\.owner) == ["com.other.app"])
        #expect(Set(plan.inUse.map(\.owner)) == ["BraveSoftware", "com.utmapp.UTM"])
    }

    @Test("La corbeille n'est vidée que si on la demande")
    func trashOnlyWhenAsked() throws {
        let home = try FakeHome()
        try home.file(".Trash/vieux.zip")
        try home.file("Library/Caches/a/b")
        let drainer = Drainer.standard(home: home.root)

        let cachesOnly = drainer.plan(kinds: [.cache, .log])
        #expect(cachesOnly.count(of: .trash) == 0)
        _ = drainer.execute(cachesOnly)
        #expect(home.exists(".Trash/vieux.zip"))

        let withTrash = drainer.plan(kinds: [.trash])
        #expect(withTrash.count(of: .trash) == 1)
        #expect(Drainer.Kind.trash.isPermanent)
    }
}

@Suite("Relevé après assèchement")
struct SurveyRemovalTests {
    private func place(_ path: String, _ bytes: Int64, _ terrain: Terrain = .marsh) -> Place {
        Place(url: URL(fileURLWithPath: path), name: path, zone: "z", terrain: terrain,
              bytes: bytes, fileCount: 1, largestFiles: [])
    }

    @Test("Les lieux qui contenaient les éléments supprimés sont allégés, les vidés disparaissent")
    func removingUpdatesPlaces() {
        let survey = Survey(
            volume: VolumeInfo(name: "x", capacity: 1000, used: 600),
            places: [place("/c/brave", 300), place("/c/root", 100), place("/docs", 200, .fields)],
            deniedPaths: [], duration: .zero)
        let after = survey.removing(
            [(URL(fileURLWithPath: "/c/brave"), 300), (URL(fileURLWithPath: "/c/root/sub"), 40)],
            volume: VolumeInfo(name: "x", capacity: 1000, used: 260))

        #expect(after.places.map(\.url.path).sorted() == ["/c/root", "/docs"])
        #expect(after.places.first { $0.url.path == "/c/root" }?.bytes == 60)
        #expect(after.bytes(of: .fields) == 200)
    }
}

@Suite("Accès complet au disque")
struct DiskAccessTests {
    @Test("Un dossier témoin lisible veut dire accès accordé")
    func readableProbe() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gosaver-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(DiskAccess.status(probes: [dir]) == .granted)
    }

    @Test("Aucun témoin existant : on ne sait pas")
    func noProbe() {
        #expect(DiskAccess.status(probes: [URL(fileURLWithPath: "/nexiste/pas")]) == .unknown)
    }
}
