import Foundation
import Testing
@testable import GoSaverCore

/// Crée un faux disque dans un dossier temporaire, le supprime à la fin.
private final class Fixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gosaver-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// Écrit un fichier de `kilobytes` Ko (contenu non nul : APFS ne compresse pas les zéros, mais restons prudents).
    @discardableResult
    func file(_ path: String, kilobytes: Int) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((0..<(kilobytes * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: url)
        return url
    }

    func url(_ path: String) -> URL { root.appendingPathComponent(path) }
}

@Suite("Relevé")
struct SurveyorTests {
    @Test("Chaque octet n'est compté qu'une fois, dans la zone la plus précise")
    func nestedZonesAreNotDoubleCounted() async throws {
        let disk = try Fixture()
        try disk.file("home/Documents/cours.pdf", kilobytes: 64)
        try disk.file("home/Library/Caches/app/blob", kilobytes: 128)
        try disk.file("home/notes.txt", kilobytes: 16)

        let zones = [
            Zone(disk.url("home/Library/Caches"), .marsh, "Caches"),
            Zone(disk.url("home/Documents"), .fields, "Documents"),
            Zone(disk.url("home"), .fields, "Dossier personnel"),
        ]
        let survey = await Surveyor(zones: zones, volume: disk.root).surveyAll()

        let marsh = survey.bytes(of: .marsh)
        let fields = survey.bytes(of: .fields)
        #expect(marsh >= 128 * 1024 && marsh < 160 * 1024)
        #expect(fields >= 80 * 1024 && fields < 112 * 1024)
        #expect(survey.places.filter { $0.terrain == .marsh }.count == 1)
    }

    @Test("Un node_modules dans les documents compte en Carrières")
    func quarryEnclave() async throws {
        let disk = try Fixture()
        try disk.file("Documents/site/index.js", kilobytes: 4)
        try disk.file("Documents/site/node_modules/lib/big.js", kilobytes: 256)

        let zones = [Zone(disk.url("Documents"), .fields, "Documents")]
        let survey = await Surveyor(zones: zones, volume: disk.root).surveyAll()

        let quarry = try #require(survey.places.first { $0.terrain == .quarry })
        #expect(quarry.isEnclave)
        #expect(quarry.name == "node_modules — site")
        #expect(quarry.bytes >= 256 * 1024)
        #expect(survey.bytes(of: .fields) < 64 * 1024)
    }

    @Test("Le Library/Caches d'une appli conteneurisée compte en Marais")
    func containerCachesAreMarsh() async throws {
        let disk = try Fixture()
        try disk.file("Containers/com.example.app/Data/Library/Caches/x", kilobytes: 64)
        try disk.file("Containers/com.example.app/Data/Documents/y", kilobytes: 8)

        let zones = [Zone(disk.url("Containers"), .city, "Conteneurs")]
        let survey = await Surveyor(zones: zones, volume: disk.root).surveyAll()

        let marsh = try #require(survey.places.first { $0.terrain == .marsh })
        #expect(marsh.name == "Caches — com.example.app")
        #expect(survey.bytes(of: .city) < 32 * 1024)
    }

    @Test("Les fichiers à la racine d'une zone forment un lieu « en vrac »")
    func looseFiles() async throws {
        let disk = try Fixture()
        try disk.file("Downloads/a.zip", kilobytes: 32)
        try disk.file("Downloads/b.dmg", kilobytes: 32)
        try disk.file("Downloads/dossier/c.txt", kilobytes: 4)

        let zones = [Zone(disk.url("Downloads"), .delta, "Téléchargements")]
        let survey = await Surveyor(zones: zones, volume: disk.root).surveyAll()

        let loose = try #require(survey.places.first { $0.name.hasSuffix("en vrac") })
        #expect(loose.fileCount == 2)
        #expect(loose.largestFiles.count == 2)
        #expect(survey.places.count == 2)
    }

    @Test("Les plus gros fichiers sont gardés dans l'ordre")
    func largestFilesOrdering() {
        var measure = Surveyor.Measure()
        let tally = Tally()
        for (index, size) in [5, 50, 1, 30, 200, 7].enumerated() {
            measure.add(fake: URL(fileURLWithPath: "/f\(index)"), bytes: Int64(size), tally: tally)
        }
        #expect(measure.largest.map(\.bytes) == [200, 50, 30, 7, 5, 1])
        #expect(measure.bytes == 293)
    }
}

@Suite("Enclaves")
struct EnclaveTests {
    @Test(arguments: [
        ("/x/node_modules", Terrain.quarry),
        ("/x/DerivedData", .quarry),
        ("/x/Data/Library/Caches", .marsh),
        ("/x/Data/Library/Logs", .marsh),
        ("/x/Caches", nil),
        ("/x/Documents", nil),
    ])
    func terrain(path: String, expected: Terrain?) {
        #expect(Enclave.terrain(for: URL(fileURLWithPath: path)) == expected)
    }
}
