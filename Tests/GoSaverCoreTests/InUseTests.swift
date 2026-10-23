import Foundation
import Testing
@testable import GoSaverCore

/// Détection des dossiers en cours d'utilisation, sur des sorties `lsof` fabriquées
/// et sur un vrai fichier tenu ouvert par ce test.
@Suite("Dossiers en cours d’utilisation")
struct InUseTests {
    let vm = URL(fileURLWithPath: "/Users/test/VMs/Ubuntu.utm")

    @Test func trouveLeProgrammeQuiTientLeDossier() {
        let listing = "p501\ncqemu-system-aarch64\nn/Users/test/VMs/Ubuntu.utm/Data/disk.qcow2\np502\ncSafari\nn/Users/test/Downloads/a.zip\n"
        #expect(InUse.match(listing, against: [vm]) == [vm: ["qemu-system-aarch64"]])
    }

    @Test func ignoreLesIndexeursEtLesVoisinsAuNomProche() {
        // Spotlight lit le dossier un instant ; « Ubuntu.utm-copie » n'est pas « Ubuntu.utm ».
        let listing = "p1\ncmdworker_shared\nn/Users/test/VMs/Ubuntu.utm/config.plist\np2\ncvim\nn/Users/test/VMs/Ubuntu.utm-copie/x\n"
        #expect(InUse.match(listing, against: [vm]).isEmpty)
    }

    @Test func reconnaitLeDossierLuiMeme() {
        let listing = "p1\nczsh\nn/Users/test/VMs/Ubuntu.utm\n"
        #expect(InUse.match(listing, against: [vm])[vm] == ["zsh"])
    }

    @Test func voitUnVraiFichierOuvert() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("inuse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("tenu.txt")
        try Data("x".utf8).write(to: file)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        // Ce processus de test garde le fichier ouvert : lsof doit le voir.
        #expect(InUse.holders(of: [dir])[dir]?.isEmpty == false)
    }
}
