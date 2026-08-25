import AppKit
import SwiftUI

// MARK: - FileDragHandle
//
// Poignee de glisser multi-fichiers.
//
// POURQUOI DE L'APPKIT ICI : `draggable(_:)` ne publie qu'UN element. Reprendre
// un depot de plusieurs fichiers en un seul geste demande autant d'elements de
// glisser que de fichiers, ce que seul `NSView.beginDraggingSession` expose.
// Un lot d'un seul fichier n'a pas besoin de ce detour et reste en SwiftUI.
//
// La vue est transparente et posee par-dessus la carte. Elle ne capte que le
// glisser : le clic droit est renvoye a la chaine de repondeurs pour que le
// menu contextuel SwiftUI continue de s'ouvrir.

struct FileDragHandle: NSViewRepresentable {

    let urls: [URL]

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.urls = urls
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.urls = urls
    }
}

// MARK: - DragSourceView

final class DragSourceView: NSView, NSDraggingSource {

    var urls: [URL] = []

    /// La fenetre du notch n'est jamais active. Sans cela, le premier clic
    /// servirait uniquement a l'activer et le glisser demanderait deux gestes.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Consomme volontairement l'evenement : c'est lui qui amorce la session
        // de glisser dans `mouseDragged`.
    }

    override func mouseDragged(with event: NSEvent) {
        guard !urls.isEmpty else { return }

        let side: CGFloat = 44
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            // Les vignettes se decalent en eventail : l'utilisateur doit voir
            // qu'il emporte plusieurs fichiers, pas un seul.
            let origin = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(
                NSRect(
                    x: origin.x - side / 2 + CGFloat(index) * 10,
                    y: origin.y - side / 2 - CGFloat(index) * 6,
                    width: side,
                    height: side
                ),
                contents: icon
            )
            return item
        }

        beginDraggingSession(with: items, event: event, source: self)
    }

    /// Le clic droit ne nous concerne pas : il doit atteindre le menu
    /// contextuel defini cote SwiftUI, plus haut dans la chaine.
    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Copie uniquement : la Pocket garde son exemplaire, le destinataire
        // recoit le sien. Autoriser `.move` laisserait une app tierce vider la
        // Pocket sans que l'utilisateur l'ait demande.
        .copy
    }
}
