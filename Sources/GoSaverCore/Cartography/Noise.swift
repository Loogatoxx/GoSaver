import Foundation

/// Bruit de gradient 2D déterministe (même graine → même île à chaque lancement).
/// Sert à donner aux côtes et aux frontières une allure naturelle plutôt que géométrique.
public struct Noise: Sendable {
    private let permutation: [Int]

    public init(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        var p = Array(0..<256)
        p.shuffle(using: &generator)
        permutation = p + p
    }

    /// Bruit de base, valeur dans [-1, 1] environ.
    public func value(_ x: Double, _ y: Double) -> Double {
        let xi = Int(floor(x)) & 255, yi = Int(floor(y)) & 255
        let xf = x - floor(x), yf = y - floor(y)
        let u = fade(xf), v = fade(yf)
        let aa = permutation[permutation[xi] + yi], ab = permutation[permutation[xi] + yi + 1]
        let ba = permutation[permutation[xi + 1] + yi], bb = permutation[permutation[xi + 1] + yi + 1]
        let x1 = lerp(gradient(aa, xf, yf), gradient(ba, xf - 1, yf), u)
        let x2 = lerp(gradient(ab, xf, yf - 1), gradient(bb, xf - 1, yf - 1), u)
        return lerp(x1, x2, v)
    }

    /// Bruit fractal : plusieurs octaves superposées, comme un vrai relief.
    public func fractal(_ x: Double, _ y: Double, octaves: Int = 4) -> Double {
        var sum = 0.0, amplitude = 1.0, frequency = 1.0, norm = 0.0
        for _ in 0..<octaves {
            sum += value(x * frequency, y * frequency) * amplitude
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return sum / norm
    }

    /// Bruit « en crêtes » pour les massifs montagneux.
    public func ridged(_ x: Double, _ y: Double, octaves: Int = 4) -> Double {
        var sum = 0.0, amplitude = 1.0, frequency = 1.0, norm = 0.0
        for _ in 0..<octaves {
            let n = 1 - abs(value(x * frequency, y * frequency))
            sum += n * n * amplitude
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return sum / norm
    }

    private func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + t * (b - a) }
    private func gradient(_ hash: Int, _ x: Double, _ y: Double) -> Double {
        switch hash & 7 {
        case 0: x + y
        case 1: -x + y
        case 2: x - y
        case 3: -x - y
        case 4: x
        case 5: -x
        case 6: y
        default: -y
        }
    }
}

/// Générateur pseudo-aléatoire à graine fixe (SplitMix64).
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
