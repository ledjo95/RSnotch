#if DEBUG
import SwiftUI

// MARK: - DesignSystemGallery
//
// Planche de controle des composants, compilee en Debug uniquement. Elle sert a
// juger le verre sur un fond contraste AVANT de construire des fonctionnalites
// dessus : un composant qui ne tient pas ici ne tiendra pas dans le notch.

struct DesignSystemGallery: View {

    private enum Filter: String, CaseIterable, Identifiable {
        case recent, images, colors, text, files, favorites
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recent: "Recent"
            case .images: "Images"
            case .colors: "Colors"
            case .text: "Text"
            case .files: "Files"
            case .favorites: "Favorites"
            }
        }
    }

    private struct Sample: Identifiable {
        let id = UUID()
        let image: NSImage
    }

    @State private var filter: Filter = .images
    @State private var activeTab: NotchTab = .home
    @State private var intensity: GlassIntensity = .dense

    private let samples: [Sample] = ["hammer.fill", "cube.fill", "paintpalette.fill",
                                     "figure.walk", "bolt.fill", "leaf.fill"]
        .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        .map(Sample.init)

    var body: some View {
        ZStack {
            checkerboard
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Formes") {
                        HStack(spacing: 16) {
                            ForEach([12.0, 18.0, 24.0], id: \.self) { radius in
                                NotchShape(bottomRadius: radius)
                                    .fill(Theme.Palette.slate)
                                    .frame(width: 120, height: 46)
                                    .overlay(alignment: .bottom) {
                                        Text("r\(Int(radius))")
                                            .font(Theme.Typography.data(9))
                                            .foregroundStyle(Theme.Palette.mist)
                                            .padding(.bottom, 4)
                                    }
                            }
                        }
                    }

                    section("Boutons") {
                        HStack(spacing: 10) {
                            ForEach(NotchTab.allCases) { tab in
                                GlassIconButton(tab: tab, isActive: activeTab == tab) {
                                    withAnimation(Theme.Motion.morph) { activeTab = tab }
                                }
                            }
                            Divider().frame(height: 22)
                            GlassActionButton(title: "Start timer", symbolName: "play.fill") {}
                        }
                    }

                    section("Filtres") {
                        GlassSegmentedRow(items: Filter.allCases, selection: $filter) { $0.title }
                    }

                    section("Grappe d’icônes") {
                        IconCluster(items: samples, rows: 3) { sample in
                            IconTile(content: .app(sample.image), label: "Exemple")
                        }
                    }

                    section("Cartes") {
                        HStack(spacing: 10) {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sam Jul").font(Theme.Typography.body(13, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.signal)
                                    Text("4").font(Theme.Typography.display(40))
                                        .foregroundStyle(.white)
                                }
                                .padding(12)
                            }
                            GlassCard {
                                Text("27° maintenant à Paris, ressenti 28°")
                                    .font(Theme.Typography.body(13))
                                    .foregroundStyle(.white)
                                    .padding(12)
                                    .frame(maxWidth: 220, alignment: .leading)
                            }
                        }
                    }

                    section("Intensité du verre") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("", selection: $intensity) {
                                ForEach(GlassIntensity.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 260)

                            Color.clear
                                .frame(width: 360, height: 60)
                                .glassEffect(
                                    intensity.shellGlass(tintedBy: nil),
                                    in: NotchShape(bottomRadius: 24)
                                )
                        }
                    }
                }
                .padding(28)
            }
        }
        .frame(minWidth: 640, minHeight: 620)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(Theme.Typography.data(9, weight: .semibold))
                .foregroundStyle(Theme.Palette.mist)
            content()
        }
    }

    /// Damier : un verre ne se juge que sur un fond qui varie.
    private var checkerboard: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            for row in 0...Int(size.height / step) {
                for column in 0...Int(size.width / step) {
                    let isDark = (row + column).isMultiple(of: 2)
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step,
                                    width: step, height: step)),
                        with: .color(isDark ? Color(white: 0.16) : Color(white: 0.34))
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}
#endif
