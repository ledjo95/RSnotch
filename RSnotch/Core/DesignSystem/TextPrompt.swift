import AppKit

// MARK: - TextPrompt
//
// Saisie d'une ligne de texte depuis le panneau du notch.
//
// La fenetre du notch est volontairement non activable : elle ne devient jamais
// « key » et ne recoit donc aucun evenement clavier. Une feuille SwiftUI
// presentee depuis cette fenetre s'afficherait sans jamais pouvoir etre
// remplie. NSAlert ouvre sa propre fenetre modale, qui prend le focus le temps
// de la saisie et le rend ensuite.

@MainActor
enum TextPrompt {

    /// Renvoie le texte saisi, ou `nil` si l'utilisateur annule.
    static func run(
        title: String,
        message: String,
        defaultValue: String,
        confirmTitle: String = "Renommer",
        placeholder: String = "Nom"
    ) -> String? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Annuler")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
