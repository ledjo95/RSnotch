import SwiftUI

// MARK: - SettingsView
//
// Fenetre de reglages complete (Phase 10).
//
// Organisee par onglets plutot qu'en une longue liste : les reglages couvrent
// desormais six domaines sans rapport entre eux, et un formulaire unique
// obligerait a faire defiler pour trouver l'interrupteur cherche.
//
// Elle porte aussi les limitations connues. Ce n'est pas de la place perdue :
// une fonction absente sans explication passe pour un bug, et certaines de ces
// absences sont des choix imposes par le bac a sable — autant les assumer la
// ou l'utilisateur va chercher.

struct SettingsView: View {

    var body: some View {
        TabView {
            Tab("Général", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("Panneau", systemImage: "rectangle.topthird.inset.filled") { PanelSettingsView() }
            Tab("Apparence", systemImage: "paintpalette") { AppearanceSettingsView() }
            Tab("Contenu", systemImage: "square.grid.2x2") { ContentSettingsView() }
            Tab("Limites", systemImage: "info.circle") { LimitationsView() }
        }
        .frame(width: 520, height: 460)
    }
}

// MARK: - Général

private struct GeneralSettingsView: View {

    @State private var settings = AppSettings.shared
    @State private var loginItem = LoginItemService()

    var body: some View {
        Form {
            Section("Démarrage") {
                Toggle("Lancer RSnotch à l’ouverture de session", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))

                if loginItem.requiresApproval {
                    // Enregistre mais en attente : l'app ne peut rien de plus,
                    // seul l'utilisateur peut approuver depuis le systeme.
                    LabeledContent("En attente d’approbation") {
                        Button("Ouvrir les Réglages Système") {
                            loginItem.openSystemSettings()
                        }
                    }
                }

                if let error = loginItem.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle("Ouvrir le panneau au lancement", isOn: $settings.expandOnLaunch)
            }

            Section("Encoche active") {
                Toggle("Activer le panneau", isOn: $settings.panelEnabled)
                Text("Désactivé, la fenêtre est retirée et les services qui l’alimentent (presse-papiers, lecteur, batterie, Bluetooth) s’arrêtent. L’icône de la barre des menus reste, pour pouvoir le réactiver.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Confidentialité") {
                Text("Toutes les données restent dans le conteneur de l’app : presse-papiers, Pocket, applications épinglées, disposition. Rien n’est transmis à un serveur, aucune statistique d’usage n’est collectée. La météo est la seule requête réseau, adressée à WeatherKit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }
}

// MARK: - Panneau

private struct PanelSettingsView: View {

    @State private var settings = AppSettings.shared

    @State private var interceptor = MediaKeyInterceptor()

    /// Le texte suit l'etat reel plutot que l'intention : promettre le
    /// remplacement alors que l'autorisation manque laisserait l'utilisateur
    /// chercher une panne qui n'existe pas.
    private var hudHint: String {
        guard settings.replaceSystemHUD else {
            return "Les jauges de RSnotch s’ajoutent à celles de macOS."
        }
        return interceptor.isTrusted
            ? "RSnotch intercepte les touches son et luminosité avant macOS : seule sa jauge s’affiche. Si une sortie audio n’expose aucun réglage logiciel, la touche repart au système plutôt que de rester sans effet."
            : "Sans l’autorisation Accessibilité, l’interception reste inactive et les deux jauges cohabitent. Le reste de l’app fonctionne normalement."
    }

    var body: some View {
        Form {
            Section("Ouverture") {
                Toggle("Ouvrir au survol", isOn: $settings.openOnHover)

                Picker("Délai avant ouverture", selection: $settings.hoverDelayMilliseconds) {
                    ForEach(AppSettings.hoverDelayChoices, id: \.self) { value in
                        Text(value == 0 ? "Immédiat" : "\(value) ms").tag(value)
                    }
                }
                .disabled(!settings.openOnHover)

                Text(settings.openOnHover
                     ? "Un délai trop court ouvre le panneau en traversant la zone pour atteindre la barre des menus."
                     : "Le panneau ne s’ouvre plus qu’en cliquant sur l’encoche.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Jauges système") {
                Toggle("Volume dans l’encoche", isOn: $settings.volumeHUDEnabled)
                Toggle("Luminosité dans l’encoche", isOn: $settings.brightnessHUDEnabled)
                Toggle("Remplacer les jauges de macOS", isOn: $settings.replaceSystemHUD)

                if settings.replaceSystemHUD {
                    LabeledContent("Accessibilité") {
                        HStack(spacing: 8) {
                            Text(interceptor.isTrusted ? "Accordée" : "Requise")
                                .foregroundStyle(interceptor.isTrusted ? .green : .orange)
                            if !interceptor.isTrusted {
                                Button("Autoriser…") { interceptor.requestTrust() }
                            } else {
                                Button("Ouvrir les Réglages") {
                                    interceptor.openAccessibilitySettings()
                                }
                            }
                        }
                    }
                }

                Text(hudHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Écrans") {
                Picker("Afficher sur", selection: $settings.screenPreference) {
                    ForEach(ScreenPreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }

                Toggle("Barre simulée sur écran sans encoche", isOn: $settings.showWithoutNotch)

                LabeledContent("Largeur de la barre simulée") {
                    HStack {
                        Slider(
                            value: $settings.simulatedBarWidth,
                            in: NotchGeometry.simulatedWidthRange,
                            step: 10
                        )
                        Text("\(Int(settings.simulatedBarWidth)) pt")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                .disabled(!settings.showWithoutNotch)

                Text("Sur un écran à encoche, la forme repliée épouse l’encoche physique et ne se règle pas. Ailleurs, elle est simulée : c’est cette barre-là que le curseur ajuste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Largeur du panneau déployé") {
                Picker("Largeur", selection: $settings.panelWidth) {
                    ForEach(PanelWidth.allCases) { width in
                        Text(width.label).tag(width)
                    }
                }
                .pickerStyle(.segmented)
                Text("Le panneau se cale sur ses cartes. Si la rangée ne tient pas dans l’écran, l’échelle est abaissée automatiquement pour éviter qu’une carte soit rognée.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { interceptor.refreshTrust() }
    }
}

// MARK: - Apparence

private struct AppearanceSettingsView: View {

    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Verre") {
                Picker("Intensité du verre", selection: $settings.glassIntensity) {
                    ForEach(GlassIntensity.allCases) { intensity in
                        Text(intensity.label).tag(intensity)
                    }
                }
                .pickerStyle(.segmented)

                Text(intensityHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Bureaux") {
                Toggle("Teinter le verre selon le bureau actif", isOn: $settings.spaceTintEnabled)
                Text("Chaque bureau reçoit une teinte d’accent, appliquée au matériau plutôt qu’en fond opaque. La reconnaissance des bureaux est une heuristique (voir l’onglet Limites) : désactiver ce réglage garde une apparence stable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Le reglage agit sur la variante de materiau, pas sur un flou fait main :
    /// autant le dire a l'utilisateur, c'est ce qui explique la difference de
    /// rendu selon le fond d'ecran.
    private var intensityHint: String {
        switch settings.glassIntensity {
        case .light: "Verre transparent : le bureau reste visible à travers le panneau."
        case .regular: "Matériau Liquid Glass standard."
        case .dense: "Verre teinté sombre, proche du noir de l’encoche."
        }
    }
}

// MARK: - Contenu

private struct ContentSettingsView: View {

    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Presse-papiers") {
                Picker("Entrées conservées", selection: $settings.clipboardLimit) {
                    ForEach(AppSettings.clipboardLimitChoices, id: \.self) { limit in
                        Text("\(limit)").tag(limit)
                    }
                }
                Text("Les favoris sont conservés au-delà de cette limite. Les contenus marqués confidentiels par les gestionnaires de mots de passe ne sont jamais enregistrés.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pocket") {
                Toggle("Vider au démarrage", isOn: $settings.emptyPocketOnLaunch)
                Text("Les fichiers déposés sont copiés dans le conteneur de l’app. L’original n’est jamais modifié.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Widget Citation") {
                TextField("Texte", text: $settings.quoteText, axis: .vertical)
                    .lineLimit(2...4)
                Text("Affiché en capitales dans le panneau.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Widgets") {
                Text("La disposition se modifie dans le panneau : clic droit sur la rangée pour ajouter un widget ou réinitialiser, glisser-déposer pour réordonner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Limites connues
//
// Trois limitations sont imposees par le bac a sable ou par l'absence d'API
// publique. Elles sont listees ici parce qu'elles se remarquent a l'usage et
// qu'une absence inexpliquee passe pour un defaut.

private struct LimitationsView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                limitation(
                    symbol: "music.note",
                    title: "Musique",
                    body: """
                    Le contrôle passe par Apple Events (AppleScript), la seule méthode autorisée hors des API privées : Musique.app et Spotify uniquement, et l’autorisation vous est demandée au premier accès.

                    Les pochettes animées d’Apple Music ne sont pas accessibles hors du client Musique. RSnotch affiche la pochette fixe, avec une légère respiration du verre en compensation.
                    """
                )

                limitation(
                    symbol: "battery.50",
                    title: "Bluetooth",
                    body: """
                    Le niveau de batterie des accessoires (AirPods, souris, clavier) n’est exposé par aucune API publique. RSnotch signale les connexions et déconnexions, mais n’affiche pas de pourcentage : mieux vaut rien montrer qu’une valeur devinée.

                    La batterie du Mac, elle, vient d’IOPowerSources et est exacte.
                    """
                )

                limitation(
                    symbol: "squares.leading.rectangle",
                    title: "Bureaux",
                    body: """
                    macOS n’expose publiquement aucun identifiant de bureau. RSnotch les reconnaît à l’ensemble des fenêtres présentes, et leur attribue un numéro dans l’ordre où il les rencontre.

                    Deux conséquences : deux bureaux portant exactement les mêmes applications sont indiscernables, et déplacer une fenêtre d’un bureau à l’autre peut faire croire à un nouveau bureau. La teinte se désactive dans l’onglet Apparence.
                    """
                )

                limitation(
                    symbol: "sun.max",
                    title: "Jauges de volume et de luminosité",
                    body: """
                    Le volume est lu par CoreAudio, API publique : la jauge suit exactement la sortie active, casque compris.

                    La luminosité n’a aucune API publique sur Apple Silicon : le seul point d’entrée documenté, IODisplayGetFloatParameter, ne trouve aucun écran sur ces machines. RSnotch passe donc par DisplayServices, un framework privé — résolu à l’exécution et isolé dans un seul fichier. Si Apple retire ces symboles, la jauge de luminosité s’éteint et les touches repartent au système, sans rien casser d’autre.

                    Les touches son et luminosité sont interceptées avant macOS, ce qui masque son propre affichage. C’est la raison pour laquelle RSnotch n’est pas distribué sur le Mac App Store : l’interception exige de sortir du bac à sable.
                    """
                )

                limitation(
                    symbol: "cloud.sun",
                    title: "Météo",
                    body: """
                    Le widget affiche des relevés d’exemple tant que la capability WeatherKit n’est pas activée sur le compte développeur. Aucune requête réseau n’est émise dans cet état.
                    """
                )
            }
            .padding(20)
        }
    }

    private func limitation(symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
