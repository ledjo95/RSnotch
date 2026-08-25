import AppKit
import SwiftUI

// MARK: - ImageWidgetView
//
// Image choisie par l'utilisateur, cadrée plein widget. Les seuls elements
// poses dessus sont en verre, pour rester lisibles quelle que soit la photo.
//
// Sandbox : le fichier est atteint via un security-scoped bookmark (voir
// BookmarkStore). Rien n'est copie dans le conteneur — l'app lit l'original la
// ou l'utilisateur l'a laisse.

struct ImageWidgetView: View {

    /// Cle de bookmark propre a cette instance de widget : deux widgets Image
    /// peuvent pointer vers deux fichiers differents.
    let bookmarkKey: String

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: chooseImage)
        .task { load() }
        .accessibilityLabel(image == nil ? "Choisir une image" : "Image personnalisée")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Etat vide

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: failed ? "photo.badge.exclamationmark" : "photo.badge.plus")
                .font(.system(size: 20, weight: .medium))
            Text(failed ? "Image introuvable" : "Choisir une image")
                .font(Theme.Typography.body(11))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.Palette.mist)
        .padding(10)
    }

    // MARK: Chargement

    private func load() {
        guard let url = BookmarkStore.shared.resolve(bookmarkKey) else { return }
        guard let loaded = NSImage(contentsOf: url) else {
            failed = true
            return
        }
        image = loaded
        failed = false
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choisir"
        panel.message = "Sélectionnez l’image à afficher dans le widget."

        // Le panneau du notch n'est pas activable : sans activation explicite,
        // l'NSOpenPanel s'ouvrirait derriere l'app de premier plan.
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? BookmarkStore.shared.save(url, for: bookmarkKey)
        BookmarkStore.shared.release(bookmarkKey)
        load()
    }
}
