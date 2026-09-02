import SwiftUI

// MARK: - QuickSettingsTabView
//
// Onglet Reglages du panneau (Phase 10).
//
// CE QUI EST ICI, ET CE QUI N'Y EST PAS. Le panneau du notch n'est PAS
// activable : il ne recoit jamais le clavier. Tout reglage qui demande une
// saisie — texte de la citation, largeur au point pres — reste donc dans la
// fenetre de reglages, atteignable par le bouton du bas.
//
// Ne sont retenus ici que les reglages dont l'effet se VOIT immediatement dans
// le panneau qu'on a sous les yeux : le verre, la largeur, les jauges, le
// survol, la teinte de bureau. Regler la matiere en la regardant changer, c'est
// tout l'interet d'un reglage pose dans l'objet lui-meme.
//
// « Activer le panneau » est volontairement ABSENT : couper le panneau depuis
// le panneau le ferait disparaitre sous le pointeur, et il faudrait connaitre
// l'icone de la barre des menus pour le retrouver. Un interrupteur qui escamote
// son propre acces n'a pas sa place ici — il reste dans la fenetre.

struct QuickSettingsTabView: View {

    @State private var settings = AppSettings.shared
    @State private var interceptor = MediaKeyInterceptor.shared

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Metrics.contentSpacing) {
            appearanceCard
            gaugesCard
            behaviourCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { interceptor.refreshTrust() }
    }

    // MARK: Apparence

    private var appearanceCard: some View {
        SettingsCard(title: "Apparence") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsField(label: "Verre") {
                    GlassSegmentedRow(
                        items: GlassIntensity.allCases,
                        selection: $settings.glassIntensity
                    ) { $0.label }
                }

                SettingsField(label: "Largeur") {
                    GlassSegmentedRow(
                        items: PanelWidth.allCases,
                        selection: $settings.panelWidth
                    ) { $0.label }
                }
            }
        }
    }

    // MARK: Jauges

    private var gaugesCard: some View {
        SettingsCard(title: "Jauges système") {
            VStack(alignment: .leading, spacing: 7) {
                SettingsToggle(label: "Volume", isOn: $settings.volumeHUDEnabled)
                SettingsToggle(label: "Luminosité", isOn: $settings.brightnessHUDEnabled)
                SettingsToggle(
                    label: "Remplacer macOS",
                    isOn: $settings.replaceSystemHUD
                )

                SettingsField(label: "Couleur") {
                    GaugeTintRow(selection: $settings.gaugeTint)
                }

                // L'etat de l'autorisation ne s'affiche QUE s'il fait
                // obstacle : rappeler « accordée » a chaque ouverture du
                // panneau serait du bruit permanent pour une bonne nouvelle.
                if settings.replaceSystemHUD, !interceptor.isTrusted {
                    Button {
                        interceptor.requestTrust()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Autoriser l’accessibilité")
                                .font(Theme.Typography.body(10, weight: .medium))
                        }
                        .foregroundStyle(Theme.Palette.ember)
                    }
                    .buttonStyle(.plain)
                    .help("L’interception des touches exige l’autorisation Accessibilité.")
                }
            }
        }
    }

    // MARK: Comportement

    private var behaviourCard: some View {
        SettingsCard(title: "Comportement") {
            VStack(alignment: .leading, spacing: 7) {
                SettingsToggle(label: "Ouvrir au survol", isOn: $settings.openOnHover)
                SettingsToggle(label: "Teinte par bureau", isOn: $settings.spaceTintEnabled)
                SettingsToggle(label: "Noms des apps et dossiers", isOn: $settings.showLauncherLabels)

                Spacer(minLength: 0)

                Button {
                    SettingsWindowController.shared.show()
                } label: {
                    HStack(spacing: 5) {
                        Text("Tous les réglages")
                            .font(Theme.Typography.body(10, weight: .semibold))
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Theme.Palette.frost)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.Palette.wellFill))
                    .overlay(Capsule().strokeBorder(Theme.Palette.innerRim, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .help("Démarrage, écrans, presse-papiers, Pocket, limites connues.")
            }
        }
    }
}

// MARK: - SettingsCard
/// Carte de la rangee de reglages : un libelle grave, puis son contenu.
private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 9) {
                Text(title).engraved()
                content
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
        }
    }
}

// MARK: - SettingsField
/// Libelle discret au-dessus d'un controle large.
private struct SettingsField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.body(10))
                .foregroundStyle(Theme.Palette.mist)
            content
        }
    }
}

// MARK: - GaugeTintRow
//
// Une pastille par teinte plutot qu'un `GlassSegmentedRow` : le choix se voit
// et se reconnait a la couleur elle-meme, un libelle texte n'ajouterait rien.

private struct GaugeTintRow: View {
    @Binding var selection: GaugeTint

    private let side: CGFloat = 20

    var body: some View {
        HStack(spacing: 10) {
            ForEach(GaugeTint.allCases) { tint in
                Button {
                    withAnimation(Theme.Motion.morph) { selection = tint }
                } label: {
                    Circle()
                        .fill(tint.color)
                        .frame(width: side, height: side)
                        .overlay {
                            Circle().strokeBorder(Theme.Palette.innerRim, lineWidth: 0.75)
                        }
                        .overlay {
                            if selection == tint {
                                Circle()
                                    .strokeBorder(Theme.Palette.frost, lineWidth: 1.5)
                                    .padding(-3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tint.label)
                .accessibilityAddTraits(selection == tint ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - SettingsToggle
//
// Interrupteur compact, dessine plutot que natif.
//
// `Toggle(.switch)` de SwiftUI impose une hauteur qui fait tenir trois lignes
// la ou il en faut cinq, et son gabarit ne suit pas les proportions du panneau.
// Celui-ci reprend le vocabulaire du design system — creux, arete interieure,
// ambre a l'etat actif — et reste un `Button` accessible, avec le trait
// `.isSelected` que VoiceOver attend.

private struct SettingsToggle: View {
    let label: String
    @Binding var isOn: Bool

    private let width: CGFloat = 26
    private let height: CGFloat = 15

    var body: some View {
        Button {
            withAnimation(Theme.Motion.morph) { isOn.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(Theme.Typography.body(11))
                    .foregroundStyle(isOn ? Theme.Palette.frost : Theme.Palette.mist)
                    .lineLimit(1)

                Spacer(minLength: 0)

                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Theme.Palette.ember.opacity(0.85) : Theme.Palette.ink.opacity(0.55))
                        .overlay(Capsule().strokeBorder(Theme.Palette.innerRim, lineWidth: 0.75))

                    Circle()
                        .fill(Theme.Palette.frost)
                        .padding(2)
                }
                .frame(width: width, height: height)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityValue(isOn ? "activé" : "désactivé")
    }
}
