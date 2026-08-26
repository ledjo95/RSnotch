import AppKit
import SwiftUI

// MARK: - AppsGridMetrics
/// Gabarit de la grappe. Trois lignes fixes : c'est ce que la hauteur du
/// panneau autorise sans reduire les icones au point de les rendre
/// indistinguables.
enum AppsGridMetrics {
    static let tileSide: CGFloat = 52
    static let spacing: CGFloat = 4
    static let rows = 3
    static let padding: CGFloat = 8

    static func maxColumns(for size: WidgetSize) -> Int {
        switch size {
        case .small: 2
        case .medium: 4
        case .large: 6
        }
    }

    /// Largeur pour un nombre de colonnes donne.
    static func width(columns: Int) -> CGFloat {
        let count = max(1, columns)
        return CGFloat(count) * tileSide
            + CGFloat(count - 1) * spacing
            + padding * 2
    }

    /// Colonnes reellement necessaires, bornees par la taille du widget.
    static func columns(itemCount: Int, size: WidgetSize) -> Int {
        let needed = max(1, Int(ceil(Double(itemCount) / Double(rows))))
        return min(needed, maxColumns(for: size))
    }
}

// MARK: - AppsWidgetView
//
// Grappe d'applications et de dossiers epingles.
//
// Deux sources de depot cohabitent sans se marcher dessus :
//   - le conteneur accepte des URL     → fichiers venus du Finder ;
//   - chaque tuile accepte du texte    → reorganisation interne (UUID).
// Une vue ne peut declarer qu'une destination de depot ; les separer par
// niveau evite d'inventer un type de transfert commun.

struct AppsWidgetView: View {

    @Bindable var model: LaunchItemsViewModel
    let size: WidgetSize

    @State private var targetedID: UUID?
    @State private var isTargetedByFinder = false
    @State private var openFolder: LaunchItem?
    @Bindable private var settings = AppSettings.shared
    /// Annule le repli du panneau tant qu'un fichier survole la grappe.
    @Environment(\.notchDragActivity) private var keepOpen
    /// Empeche le repli tant que le sous-panneau d'un dossier est ouvert.
    @Environment(\.notchOpenLock) private var lockOpen

    private var columns: Int {
        AppsGridMetrics.columns(itemCount: max(model.items.count, 1), size: size)
    }

    var body: some View {
        content
            .padding(AppsGridMetrics.padding)
            // Grappe CENTREE verticalement. Ancree en haut, une grappe de cinq
            // icones laissait un tiers de carte vide sous elle : la carte
            // paraissait tronquee plutot que remplie a sa mesure.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay { finderDropIndicator }
            .overlay(alignment: .bottom) { errorBanner }
            .fileDropDestination(
                isTargeted: Binding(
                    get: { isTargetedByFinder },
                    set: { active in
                        // Sans cela, le compte a rebours lance en quittant la
                        // bande de l'encoche replierait le panneau alors que le
                        // fichier survole deja la grappe.
                        if active { keepOpen() }
                        isTargetedByFinder = active
                    }
                )
            ) { urls in
                model.clearError()
                // `add` rend le nombre d'elements retenus ; ce que le depot a
                // ignore est deja rapporte par `model.lastError`, affiche par la
                // banniere. Rien a faire du compte ici.
                _ = withAnimation(Theme.Motion.morph) { model.add(urls) }
            }
            .contextMenu { rootMenu }
            // Un seul popover pour toute la grappe : un par tuile en
            // instancierait autant que d'elements.
            .popover(item: $openFolder, arrowEdge: .bottom) { folder in
                FolderPopoverView(folder: folder, model: model)
            }
            // Le sous-panneau s'affiche HORS de la coquille : y amener la
            // souris fait sortir le pointeur du panneau, qui se repliait
            // 120 ms plus tard en emportant le sous-panneau. Impossible de
            // cliquer une application a temps.
            .onChange(of: openFolder?.id) { previous, current in
                if previous == nil, current != nil { lockOpen(true) }
                if previous != nil, current == nil { lockOpen(false) }
            }
    }

    // MARK: Grille

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty {
            emptyState
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                grid
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private var grid: some View {
        LazyHGrid(
            rows: Array(
                repeating: GridItem(.fixed(AppsGridMetrics.tileSide),
                                    spacing: AppsGridMetrics.spacing),
                count: AppsGridMetrics.rows
            ),
            spacing: AppsGridMetrics.spacing
        ) {
            ForEach(model.items) { item in
                tile(for: item)
            }
        }
        .animation(Theme.Motion.morph, value: model.items)
    }

    private func tile(for item: LaunchItem) -> some View {
        IconTile(
            content: tileContent(for: item),
            side: AppsGridMetrics.tileSide,
            label: item.name
        ) {
            activate(item)
        }
        .overlay {
            if targetedID == item.id {
                RoundedRectangle(
                    cornerRadius: AppsGridMetrics.tileSide * 0.28,
                    style: .continuous
                )
                .strokeBorder(Theme.Palette.ember, lineWidth: 2)
            }
        }
        .overlay(alignment: .bottom) { labelBadge(for: item) }
        .help(item.name)
        .draggable(item.id.uuidString) {
            IconTile(content: tileContent(for: item), side: AppsGridMetrics.tileSide)
        }
        .dropDestination(for: String.self) { payload, _ in
            defer { targetedID = nil }
            guard let raw = payload.first, let id = UUID(uuidString: raw) else { return false }
            return withAnimation(Theme.Motion.morph) {
                // Deposer sur un dossier y range l'application ; deposer sur une
                // application reordonne la grappe.
                item.isFolder
                    ? model.move(id: id, into: item)
                    : model.move(id: id, before: item)
            }
        } isTargeted: { targetedID = $0 ? item.id : nil }
        .contextMenu { itemMenu(for: item) }
    }

    /// Bandeau de nom, superpose au bas de la tuile plutot qu'ajoute sous elle :
    /// la grille est calee sur `tileSide` (grille de lignes fixes), lui ajouter
    /// une ligne de texte aurait force a la recalculer partout ou elle est
    /// utilisee (largeur du widget, echelle de la rangee). Un bandeau en
    /// surimpression tient dans le meme gabarit, quel que soit le reglage.
    @ViewBuilder
    private func labelBadge(for item: LaunchItem) -> some View {
        if settings.showLauncherLabels {
            Text(item.name)
                .font(Theme.Typography.body(8, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 3)
                .frame(width: AppsGridMetrics.tileSide - 2)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.Palette.ink.opacity(0.72))
                )
                .padding(.bottom, 2)
                .allowsHitTesting(false)
        }
    }

    private func tileContent(for item: LaunchItem) -> IconTile.Content {
        // Un GROUPE de raccourcis se reconnait a son apercu 2x2. Un dossier du
        // Finder, lui, porte son icone reelle — y compris les dossiers a icone
        // personnalisee, que l'utilisateur reconnait au premier coup d'oeil.
        if item.isFolder {
            return .folder(AppIconLoader.shared.previewIcons(for: item))
        }
        if let icon = AppIconLoader.shared.icon(for: item) {
            return .app(icon)
        }
        if item.isDirectory {
            return .empty(symbolName: "folder.badge.questionmark")
        }
        // Bundle introuvable (application desinstallee, volume ejecte).
        return .empty(symbolName: "questionmark.app.dashed")
    }

    private func activate(_ item: LaunchItem) {
        if item.isFolder {
            openFolder = item
        } else {
            model.launch(item)
        }
    }

    // MARK: Etats

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 18, weight: .medium))
            Text("Déposez apps ou dossiers")
                .font(Theme.Typography.body(11))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.Palette.mist)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Les echecs de la grappe — depot refuse, bundle introuvable, bookmark
    /// perdu — n'etaient affiches NULLE PART. Un depot qui ne produit rien et
    /// ne dit rien se lit comme une panne de l'app.
    @ViewBuilder
    private var errorBanner: some View {
        if let message = model.lastError {
            Text(message)
                .font(Theme.Typography.body(10, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.Palette.signal))
                .padding(6)
                .transition(.opacity)
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    withAnimation(Theme.Motion.collapse) { model.clearError() }
                }
        }
    }

    @ViewBuilder
    private var finderDropIndicator: some View {
        if isTargetedByFinder {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.Palette.ember, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        }
    }

    // MARK: Menus

    @ViewBuilder
    private var rootMenu: some View {
        Button("Ajouter une application…", systemImage: "plus.app") { chooseApps() }
        Button("Ajouter un dossier…", systemImage: "folder.badge.plus") { chooseDirectory() }
        Button("Nouveau groupe", systemImage: "square.grid.3x3.square") {
            withAnimation(Theme.Motion.morph) { model.addFolder() }
        }
    }

    @ViewBuilder
    private func itemMenu(for item: LaunchItem) -> some View {
        if item.isDirectory {
            Button("Ouvrir dans le Finder", systemImage: "folder") {
                model.launch(item)
            }
        } else if !item.isFolder {
            Button("Ouvrir \(item.name)", systemImage: "arrow.up.forward.app") {
                model.launch(item)
            }
        }
        Button("Renommer…", systemImage: "pencil") {
            guard let name = TextPrompt.run(
                title: "Renommer",
                message: "Nouveau nom pour \(item.name).",
                defaultValue: item.name
            ) else { return }
            model.rename(item, to: name)
        }
        Divider()
        rootMenu
        Divider()
        Button("Retirer \(item.name)", systemImage: "trash", role: .destructive) {
            withAnimation(Theme.Motion.morph) { model.remove(item) }
        }
    }

    // MARK: Selection de fichiers

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ajouter"
        panel.message = "Choisissez les applications à épingler."

        // Le panneau du notch n'est pas activable : sans activation explicite,
        // le NSOpenPanel s'ouvrirait derriere l'app de premier plan.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        withAnimation(Theme.Motion.morph) { model.addApps(at: panel.urls) }
    }

    /// Chemin sans glisser : tout le monde ne traine pas un dossier depuis le
    /// Finder, et le panneau se replie facilement en cours de route.
    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Épingler"
        panel.message = "Choisissez les dossiers à épingler."

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        withAnimation(Theme.Motion.morph) {
            for url in panel.urls { model.addDirectory(at: url) }
        }
    }
}

// MARK: - FolderPopoverView
//
// Contenu d'un dossier, en sous-panneau plutot qu'en depliage sur place : la
// rangee n'a pas la hauteur d'un second niveau. Le popover a de la place, donc
// chaque application y porte son nom — ce que la grappe ne peut pas offrir.

struct FolderPopoverView: View {
    let folder: LaunchItem
    @Bindable var model: LaunchItemsViewModel

    private var current: LaunchItem {
        model.items.first { $0.id == folder.id } ?? folder
    }

    private var columns: Int { min(max(current.children.count, 1), 4) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(current.name)
                .font(Theme.Typography.body(11, weight: .semibold))
                .foregroundStyle(Theme.Palette.mist)

            if current.children.isEmpty {
                Text("Glissez une application sur le dossier pour la ranger ici.")
                    .font(Theme.Typography.body(11))
                    .foregroundStyle(Theme.Palette.mist)
                    .frame(width: 190, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(56), spacing: 6),
                        count: columns
                    ),
                    spacing: 10
                ) {
                    ForEach(current.children) { child in
                        entry(child)
                    }
                }
            }
        }
        .padding(14)
        // Le popover systeme arrive avec son propre materiau gris : on le
        // neutralise pour rester dans la palette du panneau.
        .presentationBackground(Theme.Palette.ink.opacity(0.94))
    }

    private func entry(_ child: LaunchItem) -> some View {
        VStack(spacing: 4) {
            IconTile(
                content: AppIconLoader.shared.icon(for: child).map {
                    IconTile.Content.app($0)
                } ?? .empty(symbolName: "questionmark.app.dashed"),
                side: AppsGridMetrics.tileSide,
                label: child.name
            ) {
                model.launch(child)
            }
            Text(child.name)
                .font(Theme.Typography.body(9))
                .foregroundStyle(Theme.Palette.mist)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 56)
        }
        .contextMenu {
            Button("Sortir du dossier", systemImage: "arrow.up.left") {
                model.extract(child, from: current)
            }
            Button("Retirer \(child.name)", systemImage: "trash", role: .destructive) {
                model.remove(child)
            }
        }
    }
}
