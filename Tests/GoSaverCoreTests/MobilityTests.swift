import Foundation
import Testing
@testable import GoSaverCore

/// Déplaçabilité : faux dossier personnel, faux disques cibles. Rien n'est déplacé.
@Suite("Déplaçabilité")
struct MobilityTests {
    final class FakeHome {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("gosaver-mobility-\(UUID().uuidString)").resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        @discardableResult
        func file(_ path: String, kilobytes: Int = 8, executable: Bool = false) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: kilobytes * 1024).write(to: url)
            if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
            return url
        }
        func dir(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func url(_ path: String) -> URL { root.appendingPathComponent(path) }
    }

    static func lexar(free: Int64 = 600_000_000_000) -> TargetVolume {
        TargetVolume(url: URL(fileURLWithPath: "/Volumes/Lexar"), name: "Lexar", format: .exfat, freeBytes: free)
    }
    static let apfs = TargetVolume(url: URL(fileURLWithPath: "/Volumes/Coffre"), name: "Coffre", format: .apfs, freeBytes: 600_000_000_000)

    @Test("Des vidéos dans les documents partent librement sur exFAT")
    func plainFilesAreFree() throws {
        let home = try FakeHome()
        try home.file("Documents/Vidéos/vacances.mov", kilobytes: 64)
        let v = MobilityJudge(home: home.root, target: Self.lexar()).judge(home.url("Documents/Vidéos"))
        #expect(v.mobility == .free)
        #expect(v.contents?.files == 1)
    }

    @Test("Un projet de code : déconseillé sur exFAT, libre sur APFS")
    func codeProjectDependsOnFormat() throws {
        let home = try FakeHome()
        try home.file("Projets/site/build.sh", executable: true)
        _ = try home.dir("Projets/site/.git")
        let onExfat = MobilityJudge(home: home.root, target: Self.lexar()).judge(home.url("Projets/site"))
        let onApfs = MobilityJudge(home: home.root, target: Self.apfs).judge(home.url("Projets/site"))
        #expect(onExfat.mobility == .discouraged)
        #expect(onExfat.advice != nil)
        #expect(onApfs.mobility == .free)
    }

    @Test("Des liens symboliques à l'intérieur : interdit sur exFAT")
    func symlinksForbiddenOnExfat() throws {
        let home = try FakeHome()
        let target = try home.file("Documents/a.txt")
        _ = try home.dir("Documents/Dossier")
        try FileManager.default.createSymbolicLink(at: home.url("Documents/Dossier/lien"), withDestinationURL: target)
        #expect(MobilityJudge(home: home.root, target: Self.lexar()).judge(home.url("Documents/Dossier")).mobility == .forbidden)
        #expect(MobilityJudge(home: home.root, target: Self.apfs).judge(home.url("Documents/Dossier")).mobility == .free)
    }

    @Test("Pas assez de place : interdit, avec les deux tailles dans la raison")
    func notEnoughSpace() throws {
        let home = try FakeHome()
        try home.file("Downloads/gros.iso", kilobytes: 512)
        let v = MobilityJudge(home: home.root, target: Self.lexar(free: 1024)).judge(home.url("Downloads/gros.iso"))
        #expect(v.mobility == .forbidden)
        #expect(v.reason.contains("Pas assez de place sur Lexar"))
    }

    @Test("Les données d'une appli isolée sont interdites, sans même parcourir le contenu")
    func containersForbidden() throws {
        let home = try FakeHome()
        try home.file("Library/Containers/com.utmapp.UTM/Data/vm.img")
        let v = MobilityJudge(home: home.root, target: Self.lexar()).judge(home.url("Library/Containers/com.utmapp.UTM"))
        #expect(v.mobility == .forbidden)
        #expect(v.contents == nil)
    }

    @Test("Une appli : interdite sur exFAT, déconseillée sur APFS")
    func appBundles() throws {
        let home = try FakeHome()
        try home.file("Applications/Jeu.app/Contents/MacOS/Jeu", executable: true)
        let app = home.url("Applications/Jeu.app")
        #expect(MobilityJudge(home: home.root, target: Self.lexar()).judge(app).mobility == .forbidden)
        #expect(MobilityJudge(home: home.root, target: Self.apfs).judge(app).mobility == .discouraged)
    }

    @Test("node_modules : déconseillé, avec le conseil de le supprimer")
    func quarryIsDiscouraged() throws {
        let home = try FakeHome()
        try home.file("Projets/site/node_modules/lib/index.js")
        let v = MobilityJudge(home: home.root, target: Self.lexar()).judge(home.url("Projets/site/node_modules"))
        #expect(v.mobility == .discouraged)
        #expect(v.advice?.contains("Supprime") == true)
    }

    @Test("Sauvegardes d'iPhone : déplaçables avec un lien")
    func iphoneBackupsWithLink() throws {
        let home = try FakeHome()
        try home.file("Library/Application Support/MobileSync/Backup/abc/Manifest.db")
        let v = MobilityJudge(home: home.root, target: Self.lexar())
            .judge(home.url("Library/Application Support/MobileSync/Backup"))
        #expect(v.mobility == .withLink)
    }

    @Test("Fichier creux : la place nécessaire sur exFAT est sa taille annoncée")
    func sparseFileGrows() throws {
        let home = try FakeHome()
        let url = home.url("VM/disque.img")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: 300_000_000)
        try handle.write(contentsOf: Data([1]))
        try handle.close()

        let onExfat = MobilityJudge(home: home.root, target: Self.lexar()).judge(home.url("VM"))
        let onApfs = MobilityJudge(home: home.root, target: Self.apfs).judge(home.url("VM"))
        #expect((onExfat.bytesOnTarget ?? 0) >= 300_000_000)
        #expect((onApfs.bytesOnTarget ?? .max) < 10_000_000)
        #expect(onExfat.notes.contains { $0.hasPrefix("Fichiers creux") })
    }

    @Test("Sans disque branché : verdict prudent et invitation à le brancher")
    func noTarget() throws {
        let home = try FakeHome()
        try home.file("Documents/Cours/a.pdf")
        let v = MobilityJudge(home: home.root, target: nil).judge(home.url("Documents/Cours"))
        #expect(v.mobility == .free)
        #expect(v.notes.contains { $0.hasPrefix("Branche") })
    }

    @Test(arguments: ["Documents", "Desktop", "Library", ".Trash", "Library/Mail"])
    func specialPlacesNeverFree(path: String) throws {
        let home = try FakeHome()
        _ = try home.dir(path)
        let v = MobilityJudge(home: home.root, target: Self.lexar()).judge(home.url(path))
        #expect(v.mobility >= .discouraged)
    }

    @Test("Les dossiers système sont interdits")
    func systemForbidden() {
        let judge = MobilityJudge(target: Self.lexar())
        for path in ["/System/Library", "/usr/local", "/opt/homebrew", "/Library/Fonts"] {
            #expect(judge.judge(URL(fileURLWithPath: path)).mobility == .forbidden)
        }
    }
}

@Suite("Déplaçabilité — cas réels")
struct MobilityRealCasesTests {
    @Test("Une photo marquée exécutable n'est pas un programme")
    func executablePhotoIsNotAProgram() throws {
        let home = try MobilityTests.FakeHome()
        try home.file("Documents/Photos/a.jpg", executable: true)
        let v = MobilityJudge(home: home.root, target: MobilityTests.lexar()).judge(home.url("Documents/Photos"))
        #expect(v.mobility == .free)
        #expect(v.contents?.executables == 0)
    }

    @Test("Les caches gardent le conseil d'assécher, même avec des liens à l'intérieur")
    func cachesKeepTheirAdvice() throws {
        let home = try MobilityTests.FakeHome()
        let a = try home.file("Library/Caches/app/a")
        try FileManager.default.createSymbolicLink(at: home.url("Library/Caches/app/lien"), withDestinationURL: a)
        let v = MobilityJudge(home: home.root, target: MobilityTests.lexar()).judge(home.url("Library/Caches/app"))
        #expect(v.mobility == .discouraged)
        #expect(v.advice?.contains("Assèche") == true)
    }

    @Test("Un dossier d'appli dans /Applications est traité comme une appli")
    func applicationsFolder() {
        let v = MobilityJudge(target: MobilityTests.lexar()).judge(URL(fileURLWithPath: "/Applications/Un Logiciel"))
        #expect(v.mobility == .forbidden)
        #expect(v.reason.contains("signature"))
    }
}
