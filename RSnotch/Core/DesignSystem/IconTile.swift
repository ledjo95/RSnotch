import SwiftUI

// MARK: - IconTile
//
// Tuile carree d'une grappe d'icones : soit une application, soit un dossier
// resume par ses quatre premieres icones. Reutilisee en Phase 3 (apps epinglees)
// et en Phase 6 (Pocket).

struct IconTile: View {

    enum Content: Equatable {
        /// Une application : son icone plein cadre.
        case app(NSImage)
        /// Un dossier : jusqu'a quatre icones en grille 2×2.
        case folder([NSImage])
        /// Emplacement vide (cible de depot).
        case empty(symbolName: String)
    }

    let content: Content
    var side: CGFloat = 34
    var label: String = ""
    var action: (() -> Void)?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { tile }.buttonStyle(.plain)
            } else {
                tile
            }
        }
        .accessibilityLabel(label)
    }

    private var tile: some View {
        ZStack {
            switch content {
            case .app(let image):
                // Fond de tuile systematique : les icones d'app ont des
                // silhouettes tres variables, l'aplat leur donne une assise
                // commune et evite que la grappe paraisse trouee.
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(side * 0.14)
                    .background(shape.fill(Theme.Palette.ink.opacity(0.45)))
                    .background(shape.fill(Theme.Palette.wellFill))
                    .overlay(shape.strokeBorder(Theme.Palette.innerRim, lineWidth: 0.75))

            case .folder(let images) where images.isEmpty:
                // Un dossier vide doit rester visible : sans marqueur, sa tuile
                // se confond avec le fond et donne l'impression d'un trou.
                shape
                    .fill(Theme.Palette.ink.opacity(0.45))
                    .overlay(shape.fill(Theme.Palette.wellFill))
                    .overlay(shape.strokeBorder(Theme.Palette.innerRim, lineWidth: 0.75))
                    .overlay {
                        Image(systemName: "folder")
                            .font(.system(size: side * 0.34, weight: .medium))
                            .foregroundStyle(Theme.Palette.mist)
                    }

            case .folder(let images):
                // Grille 2×2 : quatre emplacements fixes, pour que deux dossiers
                // de contenus differents gardent la meme silhouette.
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 2),
                    spacing: 2
                ) {
                    ForEach(0..<4, id: \.self) { index in
                        if index < images.count {
                            Image(nsImage: images[index])
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Color.clear
                        }
                    }
                }
                .padding(side * 0.14)
                .background(shape.fill(Theme.Palette.ink.opacity(0.45)))
                .background(shape.fill(Theme.Palette.wellFill))
                .overlay(shape.strokeBorder(Theme.Palette.innerRim, lineWidth: 0.75))

            case .empty(let symbolName):
                shape
                    .strokeBorder(
                        Theme.Palette.filament,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                    .overlay {
                        Image(systemName: symbolName)
                            .font(.system(size: side * 0.32, weight: .medium))
                            .foregroundStyle(Theme.Palette.mist)
                    }
            }
        }
        .frame(width: side, height: side)
        .contentShape(shape)
    }
}

// MARK: - IconCluster
//
// Grappe d'icones en colonnes. `GlassEffectContainer` regroupe les tuiles assez
// proches pour que leurs formes fusionnent — c'est ce qui donne, dans le
// panneau, l'impression d'un bloc solidaire plutot que d'icones eparpillees.

struct IconCluster<Item: Identifiable>: View {

    let items: [Item]
    /// Nombre de lignes ; les colonnes se remplissent ensuite.
    var rows: Int = 3
    var spacing: CGFloat = 4
    @ViewBuilder let tile: (Item) -> IconTile

    private var columns: [[Item]] {
        stride(from: 0, to: items.count, by: rows).map {
            Array(items[$0..<min($0 + rows, items.count)])
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing * 2) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: spacing) {
                        ForEach(column) { item in
                            tile(item)
                        }
                    }
                }
            }
        }
    }
}
