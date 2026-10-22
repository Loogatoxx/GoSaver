import RealityKit
import SwiftUI
import GoSaverCore

/// La scène 3D : un plan-relief posé sur une table, éclairé par une lampe.
///
/// Principe (celui des plans-reliefs de Vauban) : la carte imprimée est drapée sur un
/// relief sculpté. Le relief vient de `AtlasLayout.height`, l'impression de `MapPrint`.
/// Toute la richesse graphique est dans l'impression ; la 3D apporte le volume et la lumière.
@MainActor
struct AtlasScene {
    let root: Entity
    /// La planche : cible de la caméra (on tourne autour d'elle).
    let board: Entity
    let relief: ModelEntity
    let fog: ModelEntity

    /// Largeur de la planche en mètres (unité RealityKit) et hauteur du plus haut sommet.
    static let boardSize: Float = 1
    static let reliefHeight: Float = 0.11
    static let boardThickness: Float = 0.035
    /// Densité du maillage : sommets par côté.
    static let meshResolution = 288

    static func make(layout: AtlasLayout, print: CGImage) async throws -> AtlasScene {
        let root = Entity()
        let board = Entity()
        root.addChild(board)

        // Relief drapé de la carte.
        let mesh = try MeshResource.generate(from: [reliefDescriptor(layout)])
        // Mipmaps : versions réduites précalculées de la texture, qui évitent le moiré de loin.
        let texture = try await TextureResource(image: print,
                                                options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        var paper = PhysicallyBasedMaterial()
        paper.baseColor = .init(texture: .init(texture))
        paper.roughness = .init(floatLiteral: 0.92)
        paper.metallic = .init(floatLiteral: 0)
        paper.specular = .init(floatLiteral: 0.15)
        let relief = ModelEntity(mesh: mesh, materials: [paper])
        relief.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
        board.addChild(relief)

        // Tranche de la planche : carton épais, couleur papier.
        let edge = ModelEntity(
            mesh: .generateBox(width: boardSize, height: boardThickness, depth: boardSize, cornerRadius: 0.002),
            materials: [SimpleMaterial(color: NSColor(Ink.paperSunken), roughness: 0.95, isMetallic: false)]
        )
        edge.position.y = -boardThickness / 2 - 0.0005
        edge.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
        board.addChild(edge)

        // Brouillard : un voile hachuré posé juste au-dessus du relief, dont on règle l'opacité.
        // Hachures croisées sur papier vierge : la convention des « terres inconnues ».
        let fogTexture = try await TextureResource(image: fogImage(),
                                                   options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        var veil = UnlitMaterial()
        veil.color = .init(texture: .init(fogTexture))
        veil.blending = .transparent(opacity: .init(floatLiteral: 1))
        let fog = ModelEntity(mesh: mesh, materials: [veil])
        fog.position.y = 0.002
        fog.scale.y = 1.02
        board.addChild(fog)

        // Lampe de bureau : lumière chaude, rasante, venant d'en haut à gauche (cf. ombres de la charte).
        let lamp = DirectionalLight()
        lamp.light.color = NSColor(red: 1, green: 0.93, blue: 0.82, alpha: 1)
        lamp.light.intensity = 2600
        lamp.shadow = DirectionalLightComponent.Shadow(maximumDistance: 2.5, depthBias: 1.5)
        lamp.look(at: .zero, from: [-0.9, 1.1, -0.5], relativeTo: nil)
        root.addChild(lamp)

        // Lumière d'ambiance : un « ciel » de papier chaud, pour que les ombres ne soient jamais noires.
        let environment = try await EnvironmentResource(equirectangular: ambientImage())
        root.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.35))

        // La table sous la planche : reçoit son ombre, et sert de fond.
        let table = ModelEntity(
            mesh: .generatePlane(width: 12, depth: 12),
            materials: [SimpleMaterial(color: NSColor(Ink.paper), roughness: 1, isMetallic: false)]
        )
        table.position.y = -boardThickness - 0.001
        table.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
        root.addChild(table)

        return AtlasScene(root: root, board: board, relief: relief, fog: fog)
    }

    /// Opacité du brouillard, de 0 (dissipé) à 1 (tout couvert).
    func setFog(_ opacity: Float) {
        guard var material = fog.model?.materials.first as? UnlitMaterial else { return }
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        fog.model?.materials = [material]
        fog.isEnabled = opacity > 0.001
    }

    // MARK: - Maillage

    /// Grille de triangles dont chaque sommet suit l'altitude de la géographie.
    static func reliefDescriptor(_ layout: AtlasLayout) -> MeshDescriptor {
        let r = meshResolution
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        positions.reserveCapacity(r * r)

        let toGrid = Double(layout.size - 1) / Double(r - 1)
        func height(_ i: Int, _ j: Int) -> Float {
            let gi = min(max(i, 0), r - 1), gj = min(max(j, 0), r - 1)
            return layout.height.sample(Double(gi) * toGrid, Double(gj) * toGrid) * reliefHeight
        }
        let step = boardSize / Float(r - 1)
        for j in 0..<r {
            for i in 0..<r {
                let u = Float(i) / Float(r - 1), v = Float(j) / Float(r - 1)
                positions.append([(u - 0.5) * boardSize, height(i, j), (v - 0.5) * boardSize])
                // Normale par différences centrées : donne l'ombrage du relief.
                let dx = height(i + 1, j) - height(i - 1, j)
                let dz = height(i, j + 1) - height(i, j - 1)
                normals.append(simd_normalize(SIMD3(-dx, 2 * step, -dz)))
                // Les textures RealityKit ont l'origine en bas : on retourne v.
                uvs.append([u, 1 - v])
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity((r - 1) * (r - 1) * 6)
        for j in 0..<(r - 1) {
            for i in 0..<(r - 1) {
                let a = UInt32(j * r + i), b = a + 1, c = a + UInt32(r), d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }
        var descriptor = MeshDescriptor(name: "relief")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return descriptor
    }

    /// Ciel d'ambiance : dégradé vertical papier chaud → ombre sépia (une seule teinte, pas d'arc-en-ciel).
    static func ambientImage() -> CGImage {
        let width = 128, height = 64
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let t = Double(y) / Double(height - 1)
            let r = 248 - 70 * t, g = 238 - 75 * t, b = 220 - 80 * t
            for x in 0..<width {
                let o = (y * width + x) * 4
                pixels[o] = UInt8(r); pixels[o + 1] = UInt8(g); pixels[o + 2] = UInt8(b)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// Texture du brouillard : papier vierge et hachures croisées fines.
    static func fogImage(side: Int = 1024) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor(Ink.paperRaised).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setStrokeColor(NSColor(Ink.contour).withAlphaComponent(0.45).cgColor)
        context.setLineWidth(2.5)
        let spacing: CGFloat = 26
        for offset in stride(from: -CGFloat(side), through: CGFloat(side), by: spacing) {
            context.move(to: CGPoint(x: offset, y: 0)); context.addLine(to: CGPoint(x: offset + CGFloat(side), y: CGFloat(side)))
            context.move(to: CGPoint(x: offset, y: CGFloat(side))); context.addLine(to: CGPoint(x: offset + CGFloat(side), y: 0))
        }
        context.strokePath()
        return context.makeImage()!
    }

    /// Caméra de départ : vue plongeante à 50°, comme quand on se penche sur une table.
    static func camera() -> PerspectiveCamera {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 32
        camera.look(at: [0, 0, 0.04], from: [0, 1.25, 1.05], relativeTo: nil)
        return camera
    }
}
