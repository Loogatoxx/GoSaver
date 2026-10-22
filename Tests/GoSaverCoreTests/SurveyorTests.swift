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

@Suite("Géographie")
struct AtlasLayoutTests {
    private func input(used: Int64 = 200, regions: [(Terrain, [Int64])]) -> AtlasInput {
        AtlasInput(capacity: 250, used: used, regions: regions.map { terrain, sizes in
            AtlasInput.RegionInput(
                terrain: terrain, bytes: sizes.reduce(0, +),
                places: sizes.enumerated().map { .init(id: "\(terrain)\($0.offset)", name: "\($0.offset)", bytes: $0.element) })
        })
    }

    @Test("La terre émergée suit la part occupée du disque")
    func landFollowsUsage() {
        let full = AtlasLayout.build(input(used: 200, regions: [(.city, [200])]), size: 96)
        let light = AtlasLayout.build(input(used: 100, regions: [(.city, [100])]), size: 96)
        #expect(abs(full.landFraction - 0.8 * AtlasLayout.diskShare) < 0.02)
        #expect(light.landFraction < full.landFraction * 0.6)
    }

    @Test("Chaque terrain occupe une surface proportionnelle à ses octets")
    func regionAreasAreProportional() {
        let layout = AtlasLayout.build(input(regions: [(.city, [120]), (.fields, [60]), (.marsh, [20])]), size: 128)
        let cells = Dictionary(uniqueKeysWithValues: layout.regions.map { ($0.terrain, Double($0.cellCount)) })
        let total = cells.values.reduce(0, +)
        #expect(abs(cells[.city]! / total - 0.6) < 0.05)
        #expect(abs(cells[.fields]! / total - 0.3) < 0.05)
    }

    @Test("La mer reste plate, le plus haut sommet vaut 1")
    func heightsAreNormalized() {
        let layout = AtlasLayout.build(input(regions: [(.massif, [80]), (.city, [120])]), size: 96)
        for i in layout.height.values.indices where !layout.land.values[i] {
            #expect(layout.height.values[i] == 0)
        }
        #expect(abs((layout.height.values.max() ?? 0) - 1) < 0.0001)
    }

    @Test("La même entrée donne toujours la même île")
    func deterministic() {
        let a = AtlasLayout.build(input(regions: [(.city, [150]), (.quarry, [50])]), size: 64)
        let b = AtlasLayout.build(input(regions: [(.city, [150]), (.quarry, [50])]), size: 64)
        #expect(a.height.values == b.height.values)
        #expect(a.place.values == b.place.values)
    }
}

@Suite("Visée")
struct PickingTests {
    let layout = AtlasLayout.build(AtlasInput(capacity: 250, used: 200, regions: [
        .init(terrain: .city, bytes: 150, places: [.init(id: "a", name: "A", bytes: 100), .init(id: "b", name: "B", bytes: 50)]),
        .init(terrain: .fields, bytes: 50, places: []),
    ]), size: 96)
    let board = BoardGeometry(boardSize: 1, reliefHeight: 0.11)

    @Test("Un rayon vertical au-dessus du repère d'un lieu touche ce lieu")
    func verticalRayHitsPlace() throws {
        let target = try #require(layout.places.first { $0.id == "a" })
        let ground = board.world(normalized: target.label, on: layout)
        let cell = try #require(board.hit(origin: ground + [0, 1, 0], direction: [0, -1, 0], layout: layout))
        #expect(layout.place(at: cell)?.id == "a")
    }

    @Test("Un rayon oblique retrouve le point visé")
    func obliqueRay() throws {
        let target = try #require(layout.places.first { $0.id == "b" })
        let ground = board.world(normalized: target.label, on: layout)
        let eye = SIMD3<Float>(0.2, 1.3, 1.1)
        let cell = try #require(board.hit(origin: eye, direction: ground - eye, layout: layout))
        #expect(layout.place(at: cell)?.id == "b")
    }

    @Test("Un rayon qui passe à côté de la planche ne touche rien")
    func missesBoard() {
        #expect(board.hit(origin: [3, 1, 0], direction: [1, -0.1, 0], layout: layout) == nil)
    }
}
