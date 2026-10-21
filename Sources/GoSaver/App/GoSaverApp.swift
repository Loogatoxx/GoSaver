import SwiftUI
import AppKit

@main
struct GoSaverApp: App {
    init() {
        Snapshot.runIfRequested()
        Typo.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("GoSaver") {
            RootView()
                .frame(minWidth: 1000, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

/// Écran provisoire : valide la charte (polices, encres, cartouche, échelle)
/// sur les vraies valeurs du disque, en attendant la carte 3D.
struct RootView: View {
    @State private var volume = VolumeSnapshot.current()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Ink.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: Space.s5) {
                Spacer()
                Text("Atlas du disque").regionStyle().foregroundStyle(Ink.inkFaded)
                Text(Bytes.format(volume.capacity - volume.used))
                    .font(Typo.display)
                    .foregroundStyle(Ink.ink)
                Text("de mer libre autour de l’île. Le relevé n’a pas encore commencé.")
                    .font(Typo.water)
                    .foregroundStyle(Ink.sea)
                Cartouche(
                    title: volume.name,
                    subtitle: "Relevé topographique du disque interne",
                    survey: "Échelle 1 : 10 Go · \(Date.now.formatted(date: .abbreviated, time: .omitted))"
                )
                .frame(maxWidth: 360)
                ScaleBar(capacity: volume.capacity, used: volume.used)
            }
            .padding(Space.s7)
        }
    }
}

/// Capacité et occupation réelles du volume de démarrage.
struct VolumeSnapshot {
    let name: String
    let capacity: Int64
    let used: Int64

    static func current() -> VolumeSnapshot {
        let root = URL(fileURLWithPath: "/")
        let values = try? root.resourceValues(forKeys: [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ])
        let capacity = Int64(values?.volumeTotalCapacity ?? 0)
        // « Important usage » compte l'espace purgeable que macOS peut libérer : c'est le chiffre du Finder.
        let available = values?.volumeAvailableCapacityForImportantUsage ?? 0
        return VolumeSnapshot(
            name: values?.volumeLocalizedName ?? "Macintosh HD",
            capacity: capacity,
            used: max(0, capacity - available)
        )
    }
}
