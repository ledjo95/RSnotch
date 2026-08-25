import AppKit
import Observation
import OSLog
import SwiftUI

private let islandStateLog = Logger(subsystem: "com.varicube.RSnotch", category: "island")

// MARK: - NotchViewModel
//
// Pilote l'etat de la fenetre du notch. Une seule instance par ecran gere.
// Le modele ne connait ni NSPanel ni SwiftUI : il expose un etat et un rect
// actif que la couche AppKit lit pour son hit-testing.

@MainActor
@Observable
final class NotchViewModel {

    // MARK: Etat publie

    private(set) var state: NotchState = .collapsed
    var selectedTab: NotchTab = .home

    /// Geometrie de l'ecran hote, remesuree a chaque changement d'ecran.
    private(set) var geometry: NotchGeometry

    /// Vrai tant qu'un glisser-deposer survole le panneau. Pendant une session
    /// de drag, le pointeur n'emet plus d'evenements de survol : sans ce
    /// verrou, le filet de securite replierait le panneau au moment precis ou
    /// l'utilisateur vise une cible dedans.
    private(set) var isReceivingDrag = false

    /// Rect occupe par la forme visible, en coordonnees de la fenetre hote
    /// (origine bas-gauche). La fenetre couvre toute la bande superieure ;
    /// seul ce rect doit intercepter la souris, le reste laisse passer les clics.
    /// `@ObservationIgnored` : ce rect est ECRIT par la vue pendant sa passe de
    /// layout, et LU uniquement par le hit-testing AppKit — jamais par une vue.
    /// Observe, chaque ecriture notifiait les observateurs en pleine mise en
    /// page, d'ou l'avertissement AppKit « layoutSubtreeIfNeeded on a view which
    /// is already being laid out ».
    @ObservationIgnored var activeRectInWindow: CGRect = .zero

    // MARK: Reglages (Phase 0 : valeurs par defaut, exposees en Phase 10)

    /// Delai avant ouverture au survol. Evite les ouvertures accidentelles
    /// quand le pointeur ne fait que traverser la zone.
    var hoverOpenDelay: Duration = .milliseconds(180)
    /// Delai de tolerance avant repli quand le pointeur sort.
    var hoverCloseDelay: Duration = .milliseconds(120)
    /// Grace accordee pendant un glisser. Bien plus longue que le repli au
    /// survol : le pointeur doit traverser le panneau, fichier en main, sans
    /// que la cible se derobe. Le geste au survol, lui, est reversible d'un
    /// simple mouvement — pas celui-la.
    var dragCloseDelay: Duration = .seconds(2.5)

    // MARK: Taches en vol

    /// Onglet a restaurer une fois le glisser termine.
    private var tabBeforeDrag: NotchTab?

    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var islandTask: Task<Void, Never>?

    // MARK: Cycle de vie

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func updateGeometry(_ geometry: NotchGeometry) {
        self.geometry = geometry
    }

    // MARK: Survol

    /// Ouverture au survol (§3.9). Desactivee, l'encoche ne s'ouvre qu'au clic :
    /// le survol continue d'annuler un repli en cours, sinon le panneau se
    /// refermerait sous la souris de celui qui vient de cliquer dessus.
    var opensOnHover = true

    func pointerEntered() {
        closeTask?.cancel()
        closeTask = nil
        guard !state.isExpanded, opensOnHover else { return }

        openTask?.cancel()
        openTask = Task { [hoverOpenDelay] in
            try? await Task.sleep(for: hoverOpenDelay)
            guard !Task.isCancelled else { return }
            self.expand()
        }
    }

    /// Nombre de raisons de garder le panneau ouvert independamment du
    /// pointeur : sous-panneau de dossier, feuille de saisie… Un compteur et
    /// non un booleen, pour que deux elements ouverts en meme temps ne se
    /// deverrouillent pas l'un l'autre.
    private var openLocks = 0

    /// Fourni par le controleur, qui seul connait la fenetre : le pointeur
    /// est-il actuellement sur une zone active du panneau ?
    @ObservationIgnored var isPointerInsidePanel: (() -> Bool)?

    /// Prend un verrou. A appeler quand une vue s'ouvre EN DEHORS de la forme
    /// du panneau : le pointeur qui l'atteint quitte forcement la coquille, et
    /// le repli au survol emporterait la vue qu'on essaie d'utiliser.
    func retainOpen() {
        openLocks += 1
        closeTask?.cancel()
        closeTask = nil
    }

    func releaseOpen() {
        openLocks = max(0, openLocks - 1)
        guard openLocks == 0 else { return }
        // Refermer aveuglement replierait le panneau sous une souris qui s'y
        // trouve encore — par exemple quand on ferme le sous-panneau d'un
        // dossier avec Echap. C'est exactement la gene qu'on vient de corriger.
        guard isPointerInsidePanel?() != true else { return }
        pointerExited()
    }

    func pointerExited() {
        guard !isReceivingDrag, openLocks == 0 else { return }
        openTask?.cancel()
        openTask = nil

        closeTask?.cancel()
        closeTask = Task { [hoverCloseDelay] in
            try? await Task.sleep(for: hoverCloseDelay)
            guard !Task.isCancelled else { return }
            self.collapseIfExpanded()
        }
    }

    /// Repli declenche par le pointeur. Il ne ferme QUE le panneau deplie.
    ///
    /// Une notification compacte agrandit la coquille alors que le pointeur est
    /// ailleurs : `onContinuousHover` emet aussitot un `.ended`, et un repli
    /// aveugle escamotait l'island au bout de 120 ms — donc avant que quiconque
    /// puisse la lire. Sa duree de vie n'appartient qu'a `present(_:)`.
    private func collapseIfExpanded() {
        guard state == .expanded else { return }
        collapse()
    }

    // MARK: Glisser-deposer
    //
    // Un glisser qui s'attarde sur l'encoche ouvre le panneau — c'est la seule
    // facon d'atteindre la grappe d'applications avec un fichier en main,
    // puisque le survol classique ne produit aucun evenement pendant un drag.

    func dragEntered() {
        isReceivingDrag = true
        closeTask?.cancel()
        closeTask = nil

        // Le panneau s'ouvrirait sinon sur l'onglet consulte en dernier, et il
        // faudrait en changer un fichier a la main — ce qu'aucun geste de
        // glisser ne permet.
        //
        // Mais la bascule ne vaut QUE pour un onglet incapable de recevoir. La
        // page principale porte deja la grappe d'applications : y basculer vers
        // les zones de depot escamotait la cible que l'utilisateur visait,
        // rendant impossible le depot d'une app ou d'un dossier sur la grappe.
        if tabBeforeDrag == nil, !selectedTab.acceptsFileDrop {
            tabBeforeDrag = selectedTab
            withAnimation(Theme.Motion.morph) { selectedTab = .tray }
        }
        expand()
    }

    /// Fin du survol de la bande d'encoche. Ce n'est PAS la fin du glisser :
    /// le fichier descend simplement vers les zones de depot, qui sont plus bas
    /// dans le panneau. D'ou un delai de grace long, et surtout un report du
    /// changement d'onglet.
    ///
    /// Avant, `dragExited` rendait la main a l'onglet precedent sur-le-champ et
    /// repliait 120 ms plus tard : les zones AirDrop / Pocket disparaissaient
    /// sous le fichier des qu'il quittait l'encoche. Impossible a viser.
    func dragExited() {
        isReceivingDrag = false
        closeTask?.cancel()
        closeTask = Task { [dragCloseDelay] in
            try? await Task.sleep(for: dragCloseDelay)
            guard !Task.isCancelled else { return }
            self.restoreTabAfterDrag()
            self.collapseIfExpanded()
        }
    }

    /// Signale qu'un glisser est toujours en cours quelque part dans le panneau.
    /// Chaque zone de depot l'appelle en s'illuminant : tant que le fichier
    /// survole une cible, rien ne se referme.
    func dragActivity() {
        closeTask?.cancel()
        closeTask = nil
    }

    /// Maintient le panneau ouvert un instant apres un depot. Sans ce delai,
    /// la fin du glisser replie aussitot le panneau : le message de confirmation
    /// — ou d'echec — disparait avant d'avoir pu etre lu.
    func holdOpen(for duration: Duration = .seconds(3)) {
        closeTask?.cancel()
        closeTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self.collapseIfExpanded()
        }
    }

    /// Rend la main a l'onglet consulte avant le glisser. Appele aussi apres un
    /// depot reussi, sauf si l'action a elle-meme choisi une destination.
    func restoreTabAfterDrag(to override: NotchTab? = nil) {
        let previous = tabBeforeDrag
        tabBeforeDrag = nil

        // `override` gagne toujours : un depot reussi doit montrer ou le fichier
        // a atterri, y compris quand le panneau etait deja ouvert sur les zones
        // de depot et qu'aucun onglet n'avait ete memorise.
        guard let destination = override ?? previous else { return }
        withAnimation(Theme.Motion.morph) { selectedTab = destination }
    }

    // MARK: Transitions

    func expand() {
        islandTask?.cancel()
        islandTask = nil
        guard state != .expanded else { return }
        withAnimation(Theme.Motion.morph) { state = .expanded }
    }

    func collapse() {
        guard state != .collapsed else { return }
        withAnimation(Theme.Motion.collapse) { state = .collapsed }
    }

    func toggle() {
        state.isExpanded ? collapse() : expand()
    }

    // MARK: Notification compacte

    /// Affiche une island puis se retracte seule. Ignoree si le panneau est
    /// deja ouvert : l'utilisateur regarde deja le contenu, on ne le perturbe pas.
    func present(_ payload: CompactIslandPayload) {
        guard !state.isExpanded else {
            islandStateLog.notice("annonce abandonnée : panneau ouvert")
            return
        }

        islandTask?.cancel()
        withAnimation(Theme.Motion.island) { state = .island(payload) }

        islandTask = Task { [duration = payload.duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            guard self.state.islandPayload?.id == payload.id else { return }
            withAnimation(Theme.Motion.collapse) { self.state = .collapsed }
        }
    }

    // MARK: Hit-testing

    /// Interroge par la vue AppKit racine : le point (coordonnees fenetre)
    /// tombe-t-il sur une zone interactive ?
    func acceptsPoint(_ point: CGPoint) -> Bool {
        // Marge de securite : la souris doit pouvoir « rentrer » dans la forme
        // sans que le repli se declenche au pixel pres pendant l'animation.
        activeRectInWindow.insetBy(dx: -2, dy: -2).contains(point)
    }
}
