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
