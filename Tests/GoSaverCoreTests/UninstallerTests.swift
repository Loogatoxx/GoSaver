import Foundation
import Testing
@testable import GoSaverCore

/// Désinstalleur : fausse appli et faux dossier personnel. Rien n'est supprimé (le module ne fait que lister).
@Suite("Désinstalleur")
struct UninstallerTests {
    final class Bench {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("gosaver-uninst-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        func app(_ path: String, id: String) throws -> URL {
            let app = root.appendingPathComponent(path)
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": app.deletingPathExtension().lastPathComponent]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            return app
        }
        func touch(_ path: String) throws {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 5000).write(to: url)
        }
    }

    @Test("Les restes portant exactement l'identifiant ou le nom sont listés, pas les voisins")
    func exactLeftovers() throws {
        let bench = try Bench()
        let app = try bench.app("Applications/Lecteur.app", id: "fr.exemple.lecteur")
        try bench.touch("Library/Application Support/fr.exemple.lecteur/db")
        try bench.touch("Library/Caches/fr.exemple.lecteur/c")
        try bench.touch("Library/Preferences/fr.exemple.lecteur.plist")
        try bench.touch("Library/Application Support/Lecteur/x")
        try bench.touch("Library/Application Support/fr.exemple.lecteur-pro/y")   // voisin : jamais
        try bench.touch("Library/Application Support/Lecteurs/z")                  // voisin : jamais

        let plan = try Uninstaller(home: bench.home).plan(for: app)
        let names = Set(plan.leftovers.map { $0.url.lastPathComponent })
        #expect(names == ["fr.exemple.lecteur", "fr.exemple.lecteur.plist", "Lecteur"])
        #expect(plan.leftovers.count == 4)
    }

    @Test("Dossier d'appli avec désinstalleur de l'éditeur : il est signalé, et pas compté comme appli")
    func vendorUninstaller() throws {
        let bench = try Bench()
        _ = try bench.app("Applications/Montage/Montage.app", id: "com.editeur.montage")
        _ = try bench.app("Applications/Montage/Uninstall Montage.app", id: "com.editeur.uninstall")
        let plan = try Uninstaller(home: bench.home).plan(for: bench.root.appendingPathComponent("Applications/Montage"))
        #expect(plan.apps.map(\.lastPathComponent) == ["Montage.app"])
        #expect(plan.vendorUninstaller?.lastPathComponent == "Uninstall Montage.app")
    }

    @Test("Refus : appli ouverte, appli d'Apple, pas une appli")
    func refusals() throws {
        let bench = try Bench()
        let open = try bench.app("Applications/Ouverte.app", id: "fr.exemple.ouverte")
        let apple = try bench.app("Applications/Notes.app", id: "com.apple.Notes")
        let u = Uninstaller(home: bench.home)
        #expect(throws: Uninstaller.Refusal.running("Ouverte")) { try u.plan(for: open, running: ["fr.exemple.ouverte"]) }
        #expect(throws: Uninstaller.Refusal.appleApp("Notes")) { try u.plan(for: apple) }
        try FileManager.default.createDirectory(at: bench.root.appendingPathComponent("Applications/Vide"), withIntermediateDirectories: true)
        #expect(throws: Uninstaller.Refusal.notAnApp) { try u.plan(for: bench.root.appendingPathComponent("Applications/Vide")) }
    }
}

@Suite("Désinstalleur — conteneurs partagés")
struct UninstallerGroupTests {
    @Test("Le conteneur partagé « ÉQUIPE.identifiant » est un reste ; un autre de la même équipe non")
    func groupContainer() throws {
        let bench = try UninstallerTests.Bench()
        let app = try bench.app("Applications/Telegram.app", id: "ru.keepcoder.Telegram")
        try bench.touch("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/db")
        try bench.touch("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Autre/db")
        let plan = try Uninstaller(home: bench.home).plan(for: app)
        #expect(plan.leftovers.map(\.url.lastPathComponent) == ["6N38VWS5BX.ru.keepcoder.Telegram"])
    }
}
