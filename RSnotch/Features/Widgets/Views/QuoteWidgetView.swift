import SwiftUI

// MARK: - QuoteWidgetView
//
// Texte court, centre, en capitales espacees. Le traitement typographique fait
// tout le travail : pas de guillemets decoratifs, pas de fond image.
//
// Un clic ouvre la saisie. Elle passe par un NSAlert et non par une feuille
// SwiftUI : la fenetre du notch n'est pas activable, elle ne recoit donc aucun
// evenement clavier.

struct QuoteWidgetView: View {

    let text: String
    var settings: AppSettings = .shared

    var body: some View {
        Button(action: edit) { label }
            .buttonStyle(.plain)
            .help("Modifier le texte")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(text)
            .accessibilityHint("Modifie le texte")
    }

    private var label: some View {
        Text(text.uppercased())
            .font(Theme.Typography.display(15, weight: .heavy))
            .tracking(0.8)
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.Palette.frost)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
            .contentShape(Rectangle())
    }

    private func edit() {
        guard let updated = TextPrompt.run(
            title: "Texte du widget",
            message: "Ce texte s’affiche dans la rangée de widgets.",
            defaultValue: settings.quoteText,
            confirmTitle: "Enregistrer",
            placeholder: "Texte"
        ) else { return }
        settings.quoteText = updated
    }
}
