import Foundation
import GoSaverCore

// Lance un relevé complet en lecture seule et affiche le résultat brut.
// Usage : swift run -c release gosaver-survey

// `--plan-assechement` : montre ce que l'assèchement supprimerait, SANS rien supprimer.
if CommandLine.arguments.contains("--plan-assechement") {
    let size = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    let plan = Drainer.standard().plan()
    for kind in Drainer.Kind.allCases {
        print("\(kind.label) : \(size(plan.bytes(of: kind))) en \(plan.count(of: kind)) éléments")
    }
    print("Laissés (appli ouverte) : \(plan.inUse.count), illisibles : \(plan.unreadable.map(\.label))")
    for item in plan.items.prefix(8) { print("  \(size(item.bytes))\t\(item.owner)") }
    exit(0)
}

// `--deplacabilite chemin…` : verdict de déplaçabilité vers le premier disque externe branché.
// Lecture seule : rien n'est déplacé.
if let flag = CommandLine.arguments.firstIndex(of: "--deplacabilite") {
    let size = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    let target = TargetVolume.externalVolumes().first
    print("Destination : \(target.map { "\($0.name) (\($0.format.label), \(size($0.freeBytes)) libres)" } ?? "aucun disque externe")\n")
    let judge = MobilityJudge(target: target)
    for path in CommandLine.arguments[(flag + 1)...] {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let v = judge.judge(url)
        print("\(v.mobility.label.uppercased())  \(path)")
        print("  \(v.reason)")
        if let advice = v.advice { print("  → \(advice)") }
        for note in v.notes { print("  · \(note)") }
        if let c = v.contents { print("  [\(c.files) fichiers, \(size(c.allocatedBytes)) ici, \(size(v.bytesOnTarget ?? 0)) sur la destination]") }
        print("")
    }
    exit(0)
}

// `--placement chemin…` : meilleures destinations sur le disque externe (lecture seule).
if let flag = CommandLine.arguments.firstIndex(of: "--placement") {
    guard let target = TargetVolume.externalVolumes().first else { print("Aucun disque externe."); exit(1) }
    let clock = ContinuousClock()
    let start = clock.now
    let placement = Placement.index(target.url)
    print("Index de \(target.name) : \(placement.folders.count) dossiers en \(clock.now - start)\n")
    for path in CommandLine.arguments[(flag + 1)...] {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let profile = KindProfile.of(url)
        print("\(url.lastPathComponent)  [dominante : \(profile.dominant?.label ?? "aucune")]")
        let suggestions = placement.suggestions(for: url, sourceProfile: profile)
        if suggestions.isEmpty { print("  (aucune proposition : dossier d'accueil)") }
        for s in suggestions {
            print("  \(String(format: "%.2f", s.score))  \(s.folder.relativePath)")
            for r in s.reasons { print("        · \(r)") }
        }
        print("")
    }
    exit(0)
}

// `--ruines` : expertise des ruines (lecture seule).
if CommandLine.arguments.contains("--ruines") {
    let size = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    let clock = ContinuousClock()
    let start = clock.now
    let ruins = Archaeologist().excavate()
    print("\(ruins.count) ruines en \(clock.now - start)\n")
    for ruin in ruins {
        print("\(ruin.verdict.stamp)  \(ruin.kind.label) · \(size(ruin.bytes))  \(ruin.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
        print("    « \(ruin.summary) »")
        for reason in ruin.reasons { print("    · \(reason)") }
    }
    exit(0)
}

// `--desinstaller chemin` : ce que le désinstalleur retirerait (lecture seule).
if let flag = CommandLine.arguments.firstIndex(of: "--desinstaller"), CommandLine.arguments.count > flag + 1 {
    let size = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    do {
        let plan = try Uninstaller().plan(for: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
        print("Applis : \(plan.names.joined(separator: ", "))  [\(plan.bundleIDs.joined(separator: ", "))]")
        print("Emplacement : \(plan.bundleLocation.path)  (administrateur requis : \(plan.needsAdmin))")
        for l in plan.leftovers { print("  \(l.label) : \(size(l.bytes))  \(l.url.path)") }
        print("Désinstalleur de l'éditeur : \(plan.vendorUninstaller?.lastPathComponent ?? "aucun")")
        print("Total : \(size(plan.bytes))")
    } catch { print(error.localizedDescription) }
    exit(0)
}

// `--lieux mot` : lieux dont le chemin contient « mot » (lecture seule).
if let flag = CommandLine.arguments.firstIndex(of: "--lieux"), CommandLine.arguments.count > flag + 1 {
    let word = CommandLine.arguments[flag + 1].lowercased()
    let size = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    let survey = await Surveyor().surveyAll()
    for place in survey.places where place.url.path.lowercased().contains(word) {
        print("\(size(place.bytes))\t\(place.terrain.name)\t\(place.name)\t\(place.url.path)")
    }
    exit(0)
}

let surveyor = Surveyor()
var planned = 0
var done = 0

for await event in surveyor.survey() {
    switch event {
    case .planned(let count):
        planned = count
        print("Relevé de \(count) lieux…")
    case .progress(let files, let bytes):
        let line = String(format: "\r  %d/%d lieux · %d fichiers · %@      ",
                          done, planned, files, ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        FileHandle.standardError.write(Data(line.utf8))
    case .surveyed:
        done += 1
    case .finished(let survey):
        let size = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let pad = { (s: String, n: Int) in s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count) }
        print("\n\nTerminé en \(survey.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))")
        print("Volume : \(size(survey.volume.used)) occupés sur \(size(survey.volume.capacity))")
        print("Relevé : \(size(survey.surveyedBytes)) · Massif (non relevé) : \(size(survey.massifBytes))\n")
        print("PAR TERRAIN")
        for terrain in Terrain.allCases {
            let bytes = survey.bytes(of: terrain)
            guard bytes > 0 else { continue }
            print("  \(pad(terrain.name, 10)) \(pad(terrain.meaning, 28)) \(size(bytes))")
        }
        print("\nLES 30 PLUS GROS LIEUX")
        for place in survey.places.prefix(30) {
            print("  \(pad(size(place.bytes), 10)) \(pad(place.terrain.name, 10)) \(pad(place.zone, 26)) \(place.name)")
        }
        print("\nAccès refusés : \(survey.deniedPaths.count)")
        for path in survey.deniedPaths.prefix(8) { print("  \(path)") }
    }
}
