import RealityKit
import Metal
import AppKit

/// Rendu hors écran d'une scène RealityKit dans une image (mode instantané).
/// Permet de vérifier la 3D sans fenêtre ni capture d'écran.
@MainActor
enum SceneRenderer {
    static func render(_ root: Entity, camera: Entity, width: Int, height: Int) throws -> CGImage? {
        let renderer = try RealityRenderer()
        renderer.entities.append(root)
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        renderer.cameraSettings.colorBackground = .color(NSColor(Ink.paper).cgColor)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let device = MTLCreateSystemDefaultDevice(),
              let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        nonisolated(unsafe) var finished = false
        // Quelques images pour laisser les ombres et l'éclairage se stabiliser.
        for frame in 0..<4 {
            let last = frame == 3
            try renderer.updateAndRender(deltaTime: 1.0 / 60, cameraOutput: output, onComplete: { _ in
                if last { finished = true }
            })
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
