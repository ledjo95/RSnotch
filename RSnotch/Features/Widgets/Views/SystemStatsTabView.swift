import SwiftUI

// MARK: - SystemStatsTabView
//
// Six jauges circulaires : CPU, mémoire, disque, réseau, batterie, espace
// libre. Grille 3×2 — la largeur de l'onglet (§ Theme.Metrics.contentWidth)
// tient trois colonnes sans tasser les libellés.
//
// Contrairement aux autres onglets, les valeurs bougent chaque seconde :
// `SystemStatsService` ne tourne que pendant que cet onglet est affiché
// (§ ExpandedPanelView.onAppear/onDisappear), pour ne pas sonder le CPU en
// continu depuis un panneau fermé.

struct SystemStatsTabView: View {

    let service: SystemStatsService

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        Group {
            if let snapshot = service.snapshot {
                LazyVGrid(columns: columns, spacing: 8) {
                    gauge(
                        title: "CPU", symbolName: "cpu",
                        fraction: snapshot.cpuUsage,
                        value: percentLabel(snapshot.cpuUsage),
                        detail: "Utilisation"
                    )
                    gauge(
                        title: "Mémoire", symbolName: "memorychip",
                        fraction: snapshot.memoryUsage,
                        value: percentLabel(snapshot.memoryUsage),
                        detail: "\(bytesLabel(snapshot.memoryUsedBytes)) / \(bytesLabel(snapshot.memoryTotalBytes))"
                    )
                    gauge(
                        title: "Stockage", symbolName: "internaldrive",
                        fraction: snapshot.diskUsage,
                        value: percentLabel(snapshot.diskUsage),
                        detail: "\(bytesLabel(snapshot.diskFreeBytes)) libres"
                    )
                    gauge(
                        title: "Réseau", symbolName: "network",
                        fraction: nil,
                        value: rateLabel(snapshot.networkBytesPerSecond),
                        detail: "Débit"
                    )
                    if let battery = snapshot.batteryPercentage {
                        gauge(
                            title: "Batterie", symbolName: "battery.100percent",
                            fraction: Double(battery) / 100,
                            value: "\(battery) %",
                            detail: "Charge"
                        )
                    }
                    gauge(
                        title: "Disque libre", symbolName: "externaldrive",
                        fraction: 1 - snapshot.diskUsage,
                        value: bytesLabel(snapshot.diskFreeBytes),
                        detail: "Espace disponible"
                    )
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { service.start() }
        .onDisappear { service.stop() }
    }

    // MARK: Carte

    private func gauge(
        title: String, symbolName: String, fraction: Double?, value: String, detail: String
    ) -> some View {
        GlassCard {
            HStack(spacing: 10) {
                CircularGauge(fraction: fraction, symbolName: symbolName)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.body(11, weight: .medium))
                        .foregroundStyle(Theme.Palette.mist)
                    Text(value)
                        .font(Theme.Typography.body(17, weight: .semibold))
                        .foregroundStyle(Theme.Palette.frost)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detail)
                        .font(Theme.Typography.body(10))
                        .foregroundStyle(Theme.Palette.mist)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) : \(value), \(detail)")
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.Palette.mist)
            Text("Lecture des statistiques…")
                .font(Theme.Typography.body(12))
                .foregroundStyle(Theme.Palette.mist)
        }
    }

    // MARK: Formatage

    private func percentLabel(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private func bytesLabel(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    /// `ByteCountFormatter` rend "Zéro ko" pour 0 octet — correct au sens
    /// strict mais premier relevé quasi garanti (pas encore de delta entre
    /// deux échantillons), donc un "0 Ko/s" plus sobre lui est préféré ici.
    private func rateLabel(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 Ko/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }
}

// MARK: - CircularGauge
/// Anneau de progression seul, sans texte au centre à l'exception d'un
/// symbole SF — le pourcentage vit déjà à côté dans la carte (§ gauge(...)),
/// le répéter au centre serait redondant à cette taille.
private struct CircularGauge: View {
    /// `nil` pour une jauge sans notion de remplissage (le débit réseau n'a
    /// pas de plafond naturel) : l'anneau tourne alors en continu au lieu de
    /// se figer sur une fraction arbitraire.
    let fraction: Double?
    let symbolName: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Palette.filament, lineWidth: 3)

            if let fraction {
                Circle()
                    .trim(from: 0, to: max(min(fraction, 1), 0.01))
                    .stroke(tint(for: fraction), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: fraction)
            } else {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Theme.Palette.ember, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                            rotation = 270
                        }
                    }
            }

            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Palette.frost)
        }
    }

    @State private var rotation: Double = -90

    private func tint(for fraction: Double) -> Color {
        fraction >= 0.85 ? Theme.Palette.signal : Theme.Palette.ember
    }
}
