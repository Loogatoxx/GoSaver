import Foundation
import Synchronization

/// Le géomètre : parcourt le disque et produit le relevé.
///
/// Stratégie :
/// 1. On découpe chaque zone en « lieux » (ses sous-dossiers).
/// 2. On mesure les lieux en parallèle, quelques-uns à la fois.
/// 3. Chaque lieu terminé est annoncé tout de suite : l'interface lève le brouillard au fil de l'eau.
///
/// Le relevé est en lecture seule : il ne modifie jamais rien.
public struct Surveyor: Sendable {
    public let zones: [Zone]
    public let volume: URL
    /// Nombre de lieux mesurés en même temps. Au-delà, le SSD sature et on ne gagne rien.
    public let parallelism: Int

    public init(zones: [Zone] = Zone.standard(), volume: URL = URL(fileURLWithPath: "/"), parallelism: Int = 8) {
        self.zones = zones
        self.volume = volume
        self.parallelism = parallelism
    }

    public func survey() -> AsyncStream<SurveyEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await run(continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Variante sans flux : attend la fin et rend le relevé.
    public func surveyAll() async -> Survey {
        for await event in survey() {
            if case .finished(let survey) = event { return survey }
        }
        fatalError("Le relevé s'est terminé sans résultat")
    }

    // MARK: - Déroulement

    private func run(_ continuation: AsyncStream<SurveyEvent>.Continuation) async {
        let clock = ContinuousClock()
        let start = clock.now
        let jobs = plan()
        let tally = Tally()
        continuation.yield(.planned(places: jobs.count))

        // Un petit veilleur envoie le cumul 10 fois par seconde.
        let reporter = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let (files, bytes) = tally.snapshot
                continuation.yield(.progress(files: files, bytes: bytes))
            }
        }

        var places: [Place] = []
        await withTaskGroup(of: [Place].self) { group in
            var pending = jobs[...]
            // On lance `parallelism` mesures, puis une nouvelle à chaque fin.
            for _ in 0..<parallelism {
                guard let job = pending.popFirst() else { break }
                group.addTask { measure(job, tally: tally) }
            }
            for await found in group {
                for place in found where place.bytes > 0 {
                    places.append(place)
                    continuation.yield(.surveyed(place))
                }
                if let job = pending.popFirst(), !Task.isCancelled {
                    group.addTask { measure(job, tally: tally) }
                }
            }
        }
        reporter.cancel()

        let survey = Survey(
            volume: .of(volume),
            places: places.sorted { $0.bytes > $1.bytes },
            deniedPaths: tally.denied.sorted(),
            duration: clock.now - start
        )
        continuation.yield(.finished(survey))
        continuation.finish()
    }

    /// Un travail de mesure : un dossier (ou un fichier isolé) et son étiquetage.
    struct Job: Sendable {
        let url: URL
        let name: String
        let zone: Zone
        /// Fichiers posés directement à la racine d'une zone découpée : on les regroupe.
        let looseFiles: [URL]
    }

    /// Découpe les zones en lieux, sans jamais compter deux fois le même dossier.
    func plan() -> [Job] {
        let roots = Set(zones.map(\.root.path))
        var jobs: [Job] = []
        for zone in zones {
            guard zone.splitsIntoPlaces else {
                jobs.append(Job(url: zone.root, name: zone.label, zone: zone, looseFiles: []))
                continue
            }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: zone.root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []
            )) ?? []
            var loose: [URL] = []
            for child in children where !roots.contains(child.standardizedFileURL.path) {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true, values?.isSymbolicLink != true {
                    jobs.append(Job(url: child, name: child.lastPathComponent, zone: zone, looseFiles: []))
                } else {
                    loose.append(child)
                }
            }
            if !loose.isEmpty {
                jobs.append(Job(url: zone.root, name: "\(zone.label) — en vrac", zone: zone, looseFiles: loose))
            }
        }
        return jobs
    }

    // MARK: - Mesure d'un lieu

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]
    private static let keySet = Set(keys)

    /// Mesure un lieu. Renvoie le lieu lui-même, plus un lieu par enclave trouvée
    /// dedans (node_modules → Carrières, Library/Caches d'une appli → Marais…).
    func measure(_ job: Job, tally: Tally) -> [Place] {
        let roots = Set(zones.map(\.root.path))
        var measure = Measure()
        var enclaves: [Place] = []

        if !job.looseFiles.isEmpty {
            for file in job.looseFiles { measure.add(file, tally: tally) }
        } else {
            walk(job.url, zoneRoots: roots, terrain: job.zone.terrain,
                 measure: &measure, enclaves: &enclaves, zone: job.zone, tally: tally)
        }

        let place = Place(url: job.url, name: job.name, zone: job.zone.label, terrain: job.zone.terrain,
                          bytes: measure.bytes, fileCount: measure.files, largestFiles: measure.largest)
        return [place] + enclaves
    }

    private func walk(_ url: URL, zoneRoots: Set<String>, terrain: Terrain,
                      measure: inout Measure, enclaves: inout [Place], zone: Zone, tally: Tally) {
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Self.keys, options: [],
            errorHandler: { failed, _ in
                tally.deny(failed.path)
                return true // on continue malgré le refus
            }
        )
        while let item = enumerator?.nextObject() as? URL {
            if Task.isCancelled { return }
            let values = try? item.resourceValues(forKeys: Self.keySet)
            guard values?.isDirectory == true, values?.isSymbolicLink != true else {
                measure.add(item, values: values, tally: tally)
                continue
            }
            // Une autre zone plus précise s'en occupe.
            if zoneRoots.contains(item.standardizedFileURL.path) {
                enumerator?.skipDescendants()
                continue
            }
            // Enclave d'un autre terrain : mesurée à part. Une enclave du même terrain
            // (un node_modules dans une Carrière) reste comptée dans son lieu.
            if let enclave = Enclave.terrain(for: item), enclave != terrain {
                enumerator?.skipDescendants()
                var sub = Measure()
                walk(item, zoneRoots: zoneRoots, terrain: enclave,
                     measure: &sub, enclaves: &enclaves, zone: zone, tally: tally)
                enclaves.append(Place(
                    url: item, name: Self.enclaveName(item, in: zone),
                    zone: zone.label, terrain: enclave,
                    bytes: sub.bytes, fileCount: sub.files, largestFiles: sub.largest, isEnclave: true
                ))
            }
        }
    }

    /// « node_modules — Lysto », ou pour un cache d'appli « Caches — com.utmapp.UTM ».
    static func enclaveName(_ url: URL, in zone: Zone) -> String {
        // Le premier dossier sous la zone identifie le propriétaire (projet ou appli).
        // On compare des chemins résolus : `/var` est un lien vers `/private/var`, et
        // `standardizedFileURL` retire ce `/private`, ce qui décalerait le découpage.
        let base = zone.root.resolvingSymlinksInPath().path + "/"
        let path = url.resolvingSymlinksInPath().path
        let owner = path.hasPrefix(base)
            ? String(path.dropFirst(base.count).prefix { $0 != "/" })
            : url.deletingLastPathComponent().lastPathComponent
        return "\(url.lastPathComponent) — \(owner)"
    }

    /// Cumul d'un lieu, avec ses plus gros fichiers.
    struct Measure {
        static let keep = 12
        var bytes: Int64 = 0
        var files = 0
        var largest: [FileItem] = []

        mutating func add(_ url: URL, values: URLResourceValues? = nil, tally: Tally) {
            let values = values ?? (try? url.resourceValues(forKeys: Surveyor.keySet))
            // Taille allouée totale = ce que le fichier coûte vraiment sur le disque.
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            add(fake: url, bytes: size, tally: tally)
        }

        /// Ajoute un fichier dont on connaît déjà la taille (sert aussi aux tests).
        mutating func add(fake url: URL, bytes size: Int64, tally: Tally) {
            bytes += size
            files += 1
            tally.add(bytes: size)
            if largest.count < Self.keep || size > (largest.last?.bytes ?? 0) {
                let index = largest.firstIndex { $0.bytes < size } ?? largest.endIndex
                largest.insert(FileItem(url: url, bytes: size), at: index)
                if largest.count > Self.keep { largest.removeLast() }
            }
        }
    }
}

/// Compteur partagé entre toutes les mesures parallèles.
/// `Mutex` garantit qu'un seul fil d'exécution le modifie à la fois.
final class Tally: Sendable {
    private let state = Mutex<(files: Int, bytes: Int64, denied: Set<String>)>((0, 0, []))

    func add(bytes: Int64) {
        state.withLock { $0.files += 1; $0.bytes += bytes }
    }

    func deny(_ path: String) {
        state.withLock { _ = $0.denied.insert(path) }
    }

    var snapshot: (Int, Int64) { state.withLock { ($0.files, $0.bytes) } }
    var denied: [String] { state.withLock { Array($0.denied) } }
}
