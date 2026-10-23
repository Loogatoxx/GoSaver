import SwiftUI
import AppKit
import GoSaverCore

/// Fenêtre des Réglages (⌘,). Chaque réglage est réellement branché : rien de décoratif.
struct SettingsView: View {
    let model: AtlasModel

    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("Général", systemImage: "gearshape") }
            SurveyPane().tabItem { Label("Relevé", systemImage: "scope") }
            CleaningPane().tabItem { Label("Nettoyage", systemImage: "drop") }
            HarborPane(model: model).tabItem { Label("Disque externe", systemImage: "externaldrive") }
            AccessPane(model: model).tabItem { Label("Accès", systemImage: "lock.open") }
            AboutPane().tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 560)
        .background(Ink.paper)
        .preferredColorScheme(Preferences.shared.appearance.colorScheme)
    }
}

// MARK: - Mise en page commune

/// Une page de réglages : feuille de papier, rubriques séparées par des règles graduées.
private struct Pane<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) { content }
            .padding(Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.paper)
    }
}

/// Un réglage : intitulé, explication en une phrase, et sa commande.
private struct Setting<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.bodyStrong).foregroundStyle(Ink.ink)
                Text(detail).font(Typo.label).foregroundStyle(Ink.inkFaded)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s4)
            control
        }
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title).regionStyle().foregroundStyle(Ink.inkFaded)
            content
        }
    }
}

// MARK: - Général

private struct GeneralPane: View {
    @Bindable var prefs = Preferences.shared

    var body: some View {
        Pane {
            Section(title: "Langage") {
                Picker("", selection: $prefs.explorationLanguage) {
                    Text("Atlas — Marais, Carrières, Lazaret, Outre-mer…").tag(true)
                    Text("Classique — Caches, Outils de dev, Corbeille, Disque externe…").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("Le langage d’exploration raconte ton disque comme une île à cartographier. Le langage classique dit les choses telles quelles. Les chiffres et les verdicts sont les mêmes.")
                    .font(Typo.label).foregroundStyle(Ink.inkFaded)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GraduatedRule()
            Section(title: "Affichage") {
                Setting(title: "Apparence", detail: "Papier : carte claire. Lampe : la même carte lue sous une lampe de bureau.") {
                    Picker("", selection: $prefs.appearance) {
                        ForEach(Preferences.Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(width: 180)
                }
                Setting(title: "Animations réduites",
                        detail: "Pas de vol de caméra ni de brouillard animé. Suit aussi le réglage d’accessibilité de macOS.") {
                    Toggle("", isOn: $prefs.reducedAnimations).labelsHidden().toggleStyle(SurveyCheckboxStyle())
                }
            }
            GraduatedRule()
            Section(title: "Démarrage") {
                Setting(title: "Relevé automatique à l’ouverture", detail: "GoSaver relève le disque dès qu’il s’ouvre (une dizaine de secondes).") {
                    Toggle("", isOn: $prefs.surveyOnLaunch).labelsHidden().toggleStyle(SurveyCheckboxStyle())
                }
            }
        }
    }
}

// MARK: - Relevé

private struct SurveyPane: View {
    @Bindable var prefs = Preferences.shared

    var body: some View {
        Pane {
            Section(title: "Dossiers exclus du relevé") {
                Text("GoSaver ne les parcourt jamais. Leur taille reste comptée dans le Massif (la part non relevée).")
                    .font(Typo.label).foregroundStyle(Ink.inkFaded)
                    .fixedSize(horizontal: false, vertical: true)
                if prefs.excludedFolders.isEmpty {
                    Text("Aucun dossier exclu.").font(Typo.water).foregroundStyle(Ink.inkFaded)
                }
                ForEach(prefs.excludedFolders, id: \.self) { path in
                    HStack {
                        Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(Typo.figure).foregroundStyle(Ink.ink).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Retirer") { prefs.excludedFolders.removeAll { $0 == path } }
                            .buttonStyle(NoteButtonStyle())
                    }
                    .padding(.vertical, 2)
                }
                Button("Ajouter un dossier…", action: addFolder)
                    .buttonStyle(TraceButtonStyle())
                Text("La modification s’applique au prochain relevé.")
                    .font(Typo.label).foregroundStyle(Ink.inkFaded)
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Exclure"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !prefs.excludedFolders.contains(url.path) { prefs.excludedFolders.append(url.path) }
    }
}

// MARK: - Nettoyage

private struct CleaningPane: View {
    @Bindable var prefs = Preferences.shared

    var body: some View {
        Pane {
            Section(title: "Assèchement") {
                Setting(title: "Vider aussi la corbeille par défaut",
                        detail: "La case « corbeille » est cochée d’office dans la feuille d’assèchement. Vider la corbeille est définitif.") {
                    Toggle("", isOn: $prefs.trashCheckedByDefault).labelsHidden().toggleStyle(SurveyCheckboxStyle())
                }
                Text("Toujours en vigueur, sans réglage : seuls les caches et journaux connus sont touchés, et ceux des applis ouvertes sont laissés en place.")
                    .font(Typo.label).foregroundStyle(Ink.inkFaded)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Disque externe

private struct HarborPane: View {
    let model: AtlasModel
    @Bindable var prefs = Preferences.shared
    @State private var volumes: [TargetVolume] = TargetVolume.externalVolumes()

    var body: some View {
        Pane {
            Section(title: "Destination") {
                Setting(title: "Disque de destination", detail: "Où partent les convois et le Lazaret.") {
                    Picker("", selection: $prefs.harborPath) {
                        Text("Le premier disque branché").tag("")
                        ForEach(volumes, id: \.url.path) { volume in
                            Text("\(volume.name) (\(volume.format.label))").tag(volume.url.path)
                        }
                    }
                    .labelsHidden().frame(width: 220)
                    .onChange(of: prefs.harborPath) { model.refreshHarbor() }
                }
            }
            GraduatedRule()
            Section(title: Words.lazaret) {
                Setting(title: "Durée de conservation",
                        detail: "Ensuite, l’élément est supprimé définitivement (quand GoSaver est ouvert avec le disque branché). S’applique aux prochains envois.") {
                    Picker("", selection: $prefs.lazaretDays) {
                        ForEach([7, 14, 30, 60, 90], id: \.self) { Text("\($0) jours").tag($0) }
                    }
                    .labelsHidden().frame(width: 120)
                }
            }
            GraduatedRule()
            Section(title: Words.terrain(.ruins)) {
                Setting(title: "Isoler automatiquement les ruines sûres",
                        detail: "Après chaque relevé, les trouvailles « à isoler » (doublons exacts, installeurs déjà utilisés, données d’applis disparues…) partent au \(Words.lazaret) sans demander. Les fichiers « à examiner » ne partent jamais seuls.") {
                    Toggle("", isOn: $prefs.autoIsolateRuins).labelsHidden().toggleStyle(SurveyCheckboxStyle())
                }
                Setting(title: "Appli disparue après",
                        detail: "Les données d’une appli désinstallée ne sont signalées qu’après ce délai sans modification.") {
                    Picker("", selection: $prefs.orphanDays) {
                        ForEach([30, 90, 180, 365], id: \.self) { Text("\($0) jours").tag($0) }
                    }
                    .labelsHidden().frame(width: 120)
                }
                Setting(title: "Ruines conservées",
                        detail: "\(model.keptRuins.count) élément\(model.keptRuins.count > 1 ? "s" : "") que tu as choisi de garder ne sont plus signalés.") {
                    Button("Les réafficher") { model.resetKeptRuins() }
                        .buttonStyle(TraceButtonStyle())
                        .disabled(model.keptRuins.isEmpty)
                }
            }
        }
        .onAppear { volumes = TargetVolume.externalVolumes() }
    }
}

// MARK: - Accès

private struct AccessPane: View {
    let model: AtlasModel

    var body: some View {
        Pane {
            Section(title: "Accès complet au disque") {
                HStack(spacing: Space.s2) {
                    Text(model.diskAccess == .granted ? "Accordé" : "Non accordé")
                        .font(Typo.bodyStrong)
                        .foregroundStyle(model.diskAccess == .granted ? Ink.forest : Ink.ochre)
                    Spacer()
                    Button("Ouvrir les Réglages Système") { NSWorkspace.shared.open(DiskAccess.settingsURL) }
                        .buttonStyle(TraceButtonStyle())
                }
                Text("Sans lui, la corbeille, Mail, Safari et les données de certaines applis restent dans le brouillard. GoSaver ne s’accorde jamais cette permission lui-même.")
                    .font(Typo.label).foregroundStyle(Ink.inkFaded)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GraduatedRule()
            Section(title: "Ce que GoSaver lit") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(["Les noms, tailles et dates des fichiers.",
                             "Les attributs que macOS ajoute aux téléchargements (site d’origine, appli).",
                             "Le début des fichiers mystères, pour reconnaître leur vrai contenu.",
                             "L’avis de l’IA est calculé par Apple Intelligence sur ce Mac, hors ligne.",
                             "Rien ne quitte ce Mac : aucune connexion, aucun envoi."], id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                            Text("—").foregroundStyle(Ink.inkFaded).accessibilityHidden(true)
                            Text(line).font(Typo.body).foregroundStyle(Ink.ink)
                        }
                    }
                }
            }
        }
        .onAppear { model.refreshDiskAccess() }
    }
}

// MARK: - À propos

private struct AboutPane: View {
    @Bindable var prefs = Preferences.shared
    @State private var confirmReset = false

    var body: some View {
        Pane {
            HStack(spacing: Space.s4) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("GoSaver").font(Typo.title).foregroundStyle(Ink.ink)
                    Text("Atlas de stockage pour macOS").font(Typo.water).foregroundStyle(Ink.inkFaded)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                        .font(Typo.figure).foregroundStyle(Ink.inkFaded)
                }
            }
            GraduatedRule()
            Setting(title: "Réinitialiser les réglages", detail: "Remet tous les réglages comme au premier lancement. Tes fichiers ne sont pas touchés.") {
                Button("Réinitialiser…") { confirmReset = true }
                    .buttonStyle(TraceButtonStyle())
            }
        }
        .confirmationDialog("Réinitialiser tous les réglages ?", isPresented: $confirmReset) {
            Button("Réinitialiser", role: .destructive) { prefs.reset() }
        }
    }
}
