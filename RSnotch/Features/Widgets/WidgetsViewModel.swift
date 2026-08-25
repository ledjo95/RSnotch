import Foundation
import Observation
import SwiftUI

// MARK: - WidgetsViewModel
//
// Disposition de la rangee de widgets : ordre, tailles, ajout, retrait.
//
// Persistance : JSON dans UserDefaults (conteneur sandbox), PAS SwiftData.
// La disposition est une liste courte et ordonnee, relue en bloc au lancement
// et jamais interrogee — un magasin d'objets avec requetes et migrations
// n'apporterait rien ici. SwiftData entre en jeu en Phase 3 et 4, ou le volume
// (historique du presse-papiers) et les relations le justifient.

@MainActor
@Observable
final class WidgetsViewModel {

    private static let storageKey = "panel.widgets.layout"

    private(set) var widgets: [PanelWidget]

    private let defaults: UserDefaults

    // MARK: Cycle de vie

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([PanelWidget].self, from: data),
           !stored.isEmpty {
            self.widgets = stored
        } else {
            self.widgets = PanelWidget.defaultLayout
        }
    }

    // MARK: Edition

    func add(_ kind: WidgetKind) {
        widgets.append(PanelWidget(kind: kind))
        persist()
    }

    func remove(_ widget: PanelWidget) {
        widgets.removeAll { $0.id == widget.id }
        persist()
    }

    func resize(_ widget: PanelWidget, to size: WidgetSize) {
        guard let index = widgets.firstIndex(where: { $0.id == widget.id }) else { return }
        widgets[index].size = size
        persist()
    }

    /// Deplace `id` juste avant `target`. Renvoie `false` si le deplacement n'a
    /// pas de sens (identifiant inconnu, ou widget depose sur lui-meme) — la vue
    /// s'en sert pour ignorer un depot venu de l'exterieur de l'app.
    @discardableResult
    func move(id: UUID, before target: PanelWidget) -> Bool {
        guard id != target.id,
              let from = widgets.firstIndex(where: { $0.id == id }),
              let to = widgets.firstIndex(where: { $0.id == target.id })
        else { return false }

        let moved = widgets.remove(at: from)
        widgets.insert(moved, at: to)
        persist()
        return true
    }

    func resetToDefaults() {
        widgets = PanelWidget.defaultLayout
        persist()
    }

    /// Largeur exacte de la rangee, marges comprises. Le panneau s'y ajuste :
    /// une bande large avec du vide a droite trahirait un gabarit fixe.
    /// Echelle reellement applicable a la rangee.
    ///
    /// La largeur du panneau est plafonnee (ecran, `expandedMaxWidth`), pas
    /// celle de la rangee : au-dela de quatre ou cinq cartes, la derniere
    /// passait sous le bord de la coquille et se retrouvait tronquee. On
    /// rabaisse donc l'echelle jusqu'a ce que la rangee tienne, plutot que de
    /// laisser deborder.
    ///
    /// La grappe d'applications est exclue du calcul : sa largeur se mesure en
    /// colonnes de tuiles fixes et ne suit pas l'echelle.
    func rowScale(requested: CGFloat, spacing: CGFloat, appItemCount: Int, screenWidth: CGFloat) -> CGFloat {
        guard !widgets.isEmpty else { return requested }

        let available = min(
            Theme.Metrics.expandedMaxWidth,
            screenWidth * Theme.Metrics.maxScreenFraction
        ) - Theme.Metrics.panelHorizontalPadding * 2
        let gaps = spacing * CGFloat(widgets.count - 1)

        var fixed: CGFloat = 0
        var scalable: CGFloat = 0
        for widget in widgets {
            let width = widget.displayWidth(appItemCount: appItemCount)
            if widget.scalesWithPanelWidth { scalable += width } else { fixed += width }
        }

        guard scalable > 0 else { return requested }
        let room = available - gaps - fixed
        guard room > 0 else { return Self.minimumRowScale }
        return min(requested, max(room / scalable, Self.minimumRowScale))
    }

    /// Plancher d'echelle : en deca, les cartes deviennent illisibles et mieux
    /// vaut assumer un debordement qu'un contenu reduit a rien.
    private static let minimumRowScale: CGFloat = 0.7

    func rowWidth(spacing: CGFloat, appItemCount: Int, scale: CGFloat = 1) -> CGFloat {
        guard !widgets.isEmpty else { return 0 }
        let cards = widgets.reduce(0) {
            $0 + $1.displayWidth(appItemCount: appItemCount, scale: scale)
        }
        return cards + spacing * CGFloat(widgets.count - 1)
    }

    /// Types absents de la rangee : alimente le menu d'ajout.
    var availableKinds: [WidgetKind] {
        let present = Set(widgets.map(\.kind))
        return WidgetKind.allCases.filter { !present.contains($0) }
    }

    // MARK: Persistance

    private func persist() {
        guard let data = try? JSONEncoder().encode(widgets) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
