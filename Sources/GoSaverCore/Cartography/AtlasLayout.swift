import Foundation

/// Ce que la carte doit représenter : la capacité du disque et ce qui l'occupe.
public struct AtlasInput: Sendable {
    public struct PlaceInput: Sendable {
        public let id: String
        public let name: String
        public let bytes: Int64
        public init(id: String, name: String, bytes: Int64) {
            self.id = id; self.name = name; self.bytes = bytes
        }
    }

    public struct RegionInput: Sendable {
        public let terrain: Terrain
        public let bytes: Int64
        public let places: [PlaceInput]
        public init(terrain: Terrain, bytes: Int64, places: [PlaceInput]) {
            self.terrain = terrain; self.bytes = bytes; self.places = places
        }
    }

    public let capacity: Int64
    public let used: Int64
    public let regions: [RegionInput]

    public init(capacity: Int64, used: Int64, regions: [RegionInput]) {
        self.capacity = capacity; self.used = used; self.regions = regions
    }
}

/// La géographie calculée de l'île : à qui appartient chaque parcelle, et son altitude.
///
/// Règles de représentation (toutes proportionnelles, rien n'est décoratif) :
/// - le cadre carré = la capacité du disque ; la terre émergée = l'espace occupé ; la mer = le libre ;
/// - chaque terrain occupe une surface proportionnelle à ses octets ;
/// - chaque lieu important a un sommet dont la hauteur suit sa taille.
public struct AtlasLayout: Sendable {
    public struct Region: Sendable {
        public let terrain: Terrain
        public let bytes: Int64
        public let cellCount: Int
        /// Point le plus éloigné des frontières : là où l'on écrit le nom.
        public let label: SIMD2<Double>
    }

    public struct LaidPlace: Sendable {
        public let id: String
        public let name: String
        public let terrain: Terrain
        public let bytes: Int64
        public let cellCount: Int
        public let label: SIMD2<Double>
        /// Vrai pour la parcelle qui regroupe les petits lieux sans nom.
        public let isOthers: Bool
    }

    public let size: Int
    public let land: Raster<Bool>
    /// Index dans `Terrain.allCases`, ou -1 pour la mer.
    public let terrain: Raster<Int8>
    /// Index dans `places`, ou -1 pour la mer.
    public let place: Raster<Int32>
    /// Altitude normalisée : 0 au niveau de la mer, 1 au plus haut sommet.
    public let height: Raster<Float>
    /// Distance à la côte en cellules, côté mer (sert aux lignes d'eau).
    public let seaDistance: Raster<Float>
    /// Distance à la côte (en cellules) de la limite du disque : la mer en deçà = l'espace libre.
    public let diskLimit: Float
    public let regions: [Region]
    public let places: [LaidPlace]
    public let landFraction: Double

    public func terrain(atX x: Int, y: Int) -> Terrain? {
        let index = terrain[x, y]
        return index < 0 ? nil : Terrain.allCases[Int(index)]
    }
}

extension AtlasLayout {
    /// Nombre maximal de lieux nommés par terrain ; les autres forment une parcelle commune.
    static let namedPlacesPerRegion = 9
    /// En dessous de cette part du terrain, un lieu rejoint la parcelle commune.
    static let minimumPlaceShare = 0.03
    /// Part du cadre occupée par le disque entier (terre + mer libre).
    static let diskShare = 0.72

    public static func build(_ input: AtlasInput, size: Int = 192, seed: UInt64 = 0x60_5A_7E_12) -> AtlasLayout {
        let noise = Noise(seed: seed)
        let n = size
        let cellCount = n * n

        // 1. La côte : une forme organique dont la surface = part occupée du disque.
        // Le disque entier n'occupe que `diskShare` du cadre : il reste de la marge pour
        // que la côte respire. La « limite du disque » (calculée plus bas) entoure l'île
        // d'une bande de mer dont la surface est exactement l'espace libre.
        let usedShare = min(max(Double(input.used) / Double(max(input.capacity, 1)), 0.05), 0.97)
        let landFraction = usedShare * diskShare
        let margin = max(3, n / 40)
        var shape = [Double](repeating: .infinity, count: cellCount)
        for y in margin..<(n - margin) {
            for x in margin..<(n - margin) {
                let px = (Double(x) + 0.5) / Double(n), py = (Double(y) + 0.5) / Double(n)
                // Déformation du domaine : les coordonnées sont « tordues » par le bruit,
                // ce qui creuse des baies et pousse des caps, comme une vraie côte.
                let wx = px - 0.5 + 0.13 * noise.fractal(px * 2.2 + 11, py * 2.2 + 3)
                let wy = py - 0.5 + 0.13 * noise.fractal(px * 2.2 + 57, py * 2.2 + 21)
                // Norme 2,4 : entre le cercle et le carré, l'île occupe le cadre sans en épouser les bords.
                let r = pow(pow(abs(wx), 2.4) + pow(abs(wy), 2.4), 1.0 / 2.4) / 0.5
                shape[y * n + x] = r + 0.16 * noise.fractal(px * 5 + 101, py * 5 + 7, octaves: 5)
            }
        }
        let landTarget = Int(landFraction * Double(cellCount))
        let threshold = shape.sorted()[min(landTarget, cellCount - 1)]
        var land = Raster<Bool>(size: n, repeating: false)
        for i in 0..<cellCount { land.values[i] = shape[i] < threshold }
        let landCells = (0..<cellCount).filter { land.values[$0] }
        // Distance à la côte, normalisée : sert à pousser les terres basses vers le rivage.
        let coast = distanceField(inside: land)
        let coastMax = max(coast.values.max() ?? 1, 1)
        let inland = landCells.map { Double(coast.values[$0] / coastMax) }

        // 2. Les terrains : partage de la terre proportionnel aux octets.
        let regionsInput = input.regions.filter { $0.bytes > 0 }
        let totalBytes = Double(regionsInput.reduce(Int64(0)) { $0 + $1.bytes })
        let minimumShare = 0.012
        var shares = regionsInput.map { max(Double($0.bytes) / max(totalBytes, 1), minimumShare) }
        let shareSum = shares.reduce(0, +)
        shares = shares.map { $0 / shareSum }
        let regionSeeds = regionsInput.enumerated().map { index, region in
            initialSeed(for: region.terrain, index: index, noise: noise)
        }
        let regionBias = regionsInput.map { inlandPreference($0.terrain) }
        let regionOf = partition(cells: landCells, size: n, targets: shares, seeds: regionSeeds, noise: noise,
                                 warp: 0.035, inland: inland, bias: regionBias)

        var terrainGrid = Raster<Int8>(size: n, repeating: -1)
        var cellsByRegion = [[Int]](repeating: [], count: regionsInput.count)
        for (k, cell) in landCells.enumerated() {
            let r = Int(regionOf[k])
            cellsByRegion[r].append(cell)
            terrainGrid.values[cell] = Int8(Terrain.allCases.firstIndex(of: regionsInput[r].terrain)!)
        }

        // 3. Les lieux : chaque terrain est partagé entre ses lieux principaux.
        var placeGrid = Raster<Int32>(size: n, repeating: -1)
        var laid: [(input: AtlasInput.PlaceInput?, terrain: Terrain, bytes: Int64)] = []
        var generator = SeededGenerator(seed: seed ^ 0xA71A5)
        for (r, region) in regionsInput.enumerated() {
            let cells = cellsByRegion[r]
            guard !cells.isEmpty else { continue }
            let sorted = region.places.sorted { $0.bytes > $1.bytes }
            let named = Array(sorted.prefix { Double($0.bytes) >= Double(region.bytes) * minimumPlaceShare }
                .prefix(namedPlacesPerRegion))
            let namedBytes = named.reduce(Int64(0)) { $0 + $1.bytes }
            let othersBytes = max(0, region.bytes - namedBytes)

            var members: [(AtlasInput.PlaceInput?, Int64)] = named.map { ($0, $0.bytes) }
            if othersBytes > 0 || members.isEmpty { members.append((nil, max(othersBytes, 1))) }
            let total = Double(members.reduce(Int64(0)) { $0 + $1.1 })
            let targets = members.map { Double($0.1) / total }
            let seeds = spreadSeeds(count: members.count, among: cells, size: n, generator: &generator)
            let assignment = members.count == 1
                ? [Int32](repeating: 0, count: cells.count)
                : partition(cells: cells, size: n, targets: targets, seeds: seeds, noise: noise, warp: 0.02)

            let offset = Int32(laid.count)
            for (k, cell) in cells.enumerated() { placeGrid.values[cell] = offset + assignment[k] }
            for member in members { laid.append((member.0, region.terrain, member.1)) }
        }

        // 4. Repères : là où l'on écrira les noms.
        let places: [LaidPlace] = laid.enumerated().map { index, entry in
            let mask = Raster(size: n, values: placeGrid.values.map { $0 == Int32(index) })
            let (label, count) = pole(of: mask)
            return LaidPlace(
                id: entry.input?.id ?? "autres:\(entry.terrain.rawValue)",
                name: entry.input?.name ?? "",
                terrain: entry.terrain, bytes: entry.bytes, cellCount: count,
                label: label, isOthers: entry.input == nil
            )
        }
        let regions: [Region] = regionsInput.enumerated().map { r, region in
            let terrainIndex = Int8(Terrain.allCases.firstIndex(of: region.terrain)!)
            let mask = Raster(size: n, values: terrainGrid.values.map { $0 == terrainIndex })
            let (label, count) = pole(of: mask)
            return Region(terrain: region.terrain, bytes: region.bytes, cellCount: count, label: label)
        }

        // 5. Le relief.
        let height = relief(size: n, land: land, terrain: terrainGrid, place: placeGrid,
                            places: places, coast: coast, noise: noise)
        let seaDistance = distanceField(inside: Raster(size: n, values: land.values.map { !$0 }))
        // Limite du disque : distance à la côte telle que terre + mer en deçà = capacité totale.
        let freeCells = Int(Double(landCells.count) / usedShare) - landCells.count
        let seaByDistance = seaDistance.values.enumerated().filter { !land.values[$0.offset] }.map(\.element).sorted()
        let diskLimit = seaByDistance.isEmpty ? 0 : seaByDistance[min(max(freeCells, 0), seaByDistance.count - 1)]

        return AtlasLayout(size: n, land: land, terrain: terrainGrid, place: placeGrid, height: height,
                           seaDistance: seaDistance, diskLimit: diskLimit, regions: regions, places: places,
                           landFraction: Double(landCells.count) / Double(cellCount))
    }

    // MARK: - Étapes

    /// Position de départ d'un terrain : le Massif au cœur, les terres basses (marais, delta, grève)
    /// vers la côte, les autres en couronne. Cohérent avec une vraie géographie.
    static func initialSeed(for terrain: Terrain, index: Int, noise: Noise) -> SIMD2<Double> {
        let ring: [Terrain] = [.city, .fields, .forest, .quarry, .ruins, .delta, .marsh, .shore]
        if terrain == .massif { return SIMD2(0.52, 0.46) }
        let position = Double(ring.firstIndex(of: terrain) ?? index)
        let angle = position / Double(ring.count) * 2 * .pi + 0.7
        let radius = [.delta, .marsh, .shore].contains(terrain) ? 0.34 : 0.24
        return SIMD2(0.5 + radius * cos(angle), 0.5 + radius * sin(angle))
    }

    /// Partage des cellules entre des germes, chaque part visant une surface cible
    /// (diagramme de puissance ajusté par itérations). Les coordonnées sont légèrement
    /// « tordues » par le bruit pour que les frontières ressemblent à de vraies limites.
    static func partition(cells: [Int], size n: Int, targets: [Double], seeds initial: [SIMD2<Double>],
                          noise: Noise, warp: Double, inland: [Double]? = nil, bias: [Double]? = nil,
                          iterations: Int = 70) -> [Int32] {
        let k = targets.count
        guard k > 1 else { return [Int32](repeating: 0, count: cells.count) }
        let points: [SIMD2<Double>] = cells.map { cell in
            let px = (Double(cell % n) + 0.5) / Double(n), py = (Double(cell / n) + 0.5) / Double(n)
            return SIMD2(px + warp * noise.fractal(px * 7 + 3, py * 7 + 41),
                         py + warp * noise.fractal(px * 7 + 77, py * 7 + 13))
        }
        var seeds = initial
        var weights = [Double](repeating: 0, count: k)
        var owner = [Int32](repeating: 0, count: cells.count)
        let total = Double(cells.count)

        for iteration in 0..<iterations {
            var counts = [Int](repeating: 0, count: k)
            var sums = [SIMD2<Double>](repeating: .zero, count: k)
            for (i, p) in points.enumerated() {
                var best = 0, bestCost = Double.infinity
                for s in 0..<k {
                    let d = p - seeds[s]
                    var cost = (d.x * d.x + d.y * d.y) - weights[s]
                    // Biais côtier : positif = préfère le rivage, négatif = préfère l'intérieur.
                    if let inland, let bias { cost += bias[s] * inland[i] }
                    if cost < bestCost { bestCost = cost; best = s }
                }
                owner[i] = Int32(best)
                counts[best] += 1
                sums[best] += p
            }
            let step = 0.06 * (1 - Double(iteration) / Double(iterations)) + 0.01
            for s in 0..<k {
                let actual = Double(counts[s]) / total
                weights[s] += step * (targets[s] - actual)
                // Recentrage progressif : garde des parts compactes.
                if counts[s] > 0, iteration % 4 == 0, iteration < iterations - 10 {
                    seeds[s] = seeds[s] * 0.6 + (sums[s] / Double(counts[s])) * 0.4
                }
            }
        }
        return owner
    }

    /// Germes bien répartis dans une zone (échantillonnage du point le plus éloigné).
    static func spreadSeeds(count: Int, among cells: [Int], size n: Int,
                            generator: inout SeededGenerator) -> [SIMD2<Double>] {
        let points = cells.map { SIMD2((Double($0 % n) + 0.5) / Double(n), (Double($0 / n) + 0.5) / Double(n)) }
        guard !points.isEmpty else { return [] }
        var chosen = [points[Int.random(in: 0..<points.count, using: &generator)]]
        var nearest = points.map { simd_length_squared($0 - chosen[0]) }
        while chosen.count < count {
            let index = nearest.indices.max { nearest[$0] < nearest[$1] }!
            chosen.append(points[index])
            for i in points.indices { nearest[i] = min(nearest[i], simd_length_squared(points[i] - points[index])) }
        }
        return chosen
    }

    /// Point le plus éloigné des bords d'une zone, en coordonnées normalisées [0, 1].
    static func pole(of mask: Raster<Bool>) -> (SIMD2<Double>, Int) {
        let distances = distanceField(inside: mask)
        var best = -1, bestValue: Float = -1, count = 0
        for i in mask.values.indices where mask.values[i] {
            count += 1
            if distances.values[i] > bestValue { bestValue = distances.values[i]; best = i }
        }
        guard best >= 0 else { return (SIMD2(0.5, 0.5), 0) }
        let n = mask.size
        return (SIMD2((Double(best % n) + 0.5) / Double(n), (Double(best / n) + 0.5) / Double(n)), count)
    }

    /// Altitude de chaque parcelle.
    static func relief(size n: Int, land: Raster<Bool>, terrain: Raster<Int8>, place: Raster<Int32>,
                       places: [LaidPlace], coast: Raster<Float>, noise: Noise) -> Raster<Float> {
        let maxBytes = Double(places.filter { !$0.isOthers }.map(\.bytes).max() ?? 1)
        // Sommets : une colline par lieu nommé, hauteur ∝ racine de la taille.
        struct Peak { let x: Double, y: Double, amplitude: Double, sigma: Double }
        let peaks: [Peak] = places.compactMap { p in
            guard !p.isOthers, p.cellCount > 0 else { return nil }
            let radius = sqrt(Double(p.cellCount) / .pi)
            return Peak(x: p.label.x * Double(n), y: p.label.y * Double(n),
                        amplitude: 0.75 * sqrt(Double(p.bytes) / maxBytes),
                        sigma: max(2.5, radius * 0.5))
        }

        // Le relief se compose de quatre couches, additionnées puis adoucies vers la côte :
        // 1. un socle par terrain, très lissé pour que les terrains se fondent sans falaise ;
        var base = Raster<Float>(size: n, repeating: 0)
        var massifMask = Raster<Float>(size: n, repeating: 0)
        for i in base.values.indices where land.values[i] {
            let kind = Terrain.allCases[Int(terrain.values[i])]
            base.values[i] = Float(baseHeight(kind))
            if kind == .massif { massifMask.values[i] = 1 }
        }
        base = base.smoothed(passes: 16)
        massifMask = massifMask.smoothed(passes: 8)

        var height = Raster<Float>(size: n, repeating: 0)
        for y in 0..<n {
            for x in 0..<n where land[x, y] {
                let px = Double(x) / Double(n), py = Double(y) / Double(n)
                var h = Double(base[x, y])
                // 2. des crêtes dans le Massif, fondues sur ses bords ;
                h += 0.55 * Double(massifMask[x, y]) * noise.ridged(px * 3.5 + 31, py * 3.5 + 17, octaves: 5)
                // 3. un sommet par lieu nommé, hauteur ∝ racine de sa taille ;
                for peak in peaks {
                    let dx = Double(x) - peak.x, dy = Double(y) - peak.y
                    let d2 = dx * dx + dy * dy
                    let s2 = peak.sigma * peak.sigma
                    if d2 < 9 * s2 { h += peak.amplitude * exp(-d2 / (2 * s2)) }
                }
                // 4. un léger modelé naturel.
                h += 0.025 * noise.fractal(px * 11 + 5, py * 11 + 9, octaves: 4)
                // La terre descend en pente douce vers la côte (sur ~14 cellules).
                let shore = Double(min(coast[x, y] / 14, 1))
                height[x, y] = Float(max(h, 0) * (shore * shore * (3 - 2 * shore)) + 0.006)
            }
        }
        // Dernier adoucissement, sur la terre seulement : la mer reste parfaitement plate.
        var smooth = height.smoothed(passes: 1)
        var top: Float = 0.0001
        for i in smooth.values.indices {
            if !land.values[i] { smooth.values[i] = 0 }
            top = max(top, smooth.values[i])
        }
        for i in smooth.values.indices { smooth.values[i] /= top }
        return smooth
    }

    /// Préférence d'un terrain pour la côte (> 0) ou l'intérieur des terres (< 0).
    static func inlandPreference(_ terrain: Terrain) -> Double {
        switch terrain {
        case .delta, .marsh, .shore: 0.10
        case .massif: -0.08
        case .quarry, .ruins: -0.02
        default: 0
        }
    }

    static func baseHeight(_ terrain: Terrain) -> Double {
        switch terrain {
        case .massif: 0.16
        case .quarry: 0.11
        case .city: 0.09
        case .forest: 0.08
        case .ruins: 0.07
        case .fields: 0.05
        case .delta: 0.018
        case .marsh: 0.014
        case .shore: 0.01
        }
    }
}

extension Raster {
    init(size: Int, values: [Value]) {
        precondition(values.count == size * size)
        self.size = size
        self.values = values
    }
}

@inline(__always) private func simd_length_squared(_ v: SIMD2<Double>) -> Double { v.x * v.x + v.y * v.y }
