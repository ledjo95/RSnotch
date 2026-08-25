import SwiftUI

// MARK: - WeatherWidgetView
//
// Phrase continue plutot que tableau de valeurs : « 27° maintenant à Paris,
// ressenti 28° ». Les chiffres et les noms propres sont en blanc, les mots de
// liaison en `mist` — la donnee ressort sans qu'on ait besoin d'etiquettes.

struct WeatherWidgetView: View {

    let availability: WeatherAvailability

    var body: some View {
        Button { AppLauncher.open(.weather) } label: {
            reading
        }
        .buttonStyle(.plain)
        .help(AppLauncher.isInstalled(.weather) ? "Ouvrir Météo" : "")
        .accessibilityAddTraits(AppLauncher.isInstalled(.weather) ? [.isButton] : [])
        .accessibilityHint(AppLauncher.isInstalled(.weather) ? "Ouvre Météo" : "")
    }

    private var reading: some View {
        Group {
            switch availability {
            case .idle, .loading:
                placeholder
            case .ready(let snapshot):
                reading(snapshot)
            case .unavailable(let reason):
                unavailable(reason)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .contentShape(Rectangle())
    }

    // MARK: Etats

    private func reading(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(phrase(for: snapshot))
                .font(Theme.Typography.body(16, weight: .semibold))
            .lineSpacing(1)
            .minimumScaleFactor(0.75)

            HStack(spacing: 5) {
                Image(systemName: snapshot.symbolName)
                    .symbolRenderingMode(.hierarchical)
                Text(snapshot.condition)
            }
            .font(Theme.Typography.body(12))
            .foregroundStyle(Theme.Palette.mist)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    /// Phrase composee : les valeurs et noms propres en blanc, les mots de
    /// liaison en `mist`. Construite en AttributedString — la concatenation de
    /// `Text` par `+` est depreciee depuis macOS 26.
    private func phrase(for snapshot: WeatherSnapshot) -> AttributedString {
        var result = AttributedString()

        func append(_ text: String, _ color: Color) {
            var piece = AttributedString(text)
            piece.foregroundColor = color
            result.append(piece)
        }

        append(snapshot.formattedTemperature(snapshot.temperature), .white)
        append(" maintenant à ", Theme.Palette.mist)
        append(snapshot.locationName, .white)
        append(", ressenti ", Theme.Palette.mist)
        append(snapshot.formattedTemperature(snapshot.feelsLike), .white)
        return result
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<2, id: \.self) { index in
                Capsule()
                    .fill(Theme.Palette.filament)
                    .frame(width: index == 0 ? 150 : 90, height: 12)
            }
        }
        .accessibilityLabel("Météo en cours de chargement")
    }

    /// Un echec de meteo ne doit pas laisser une carte vide : on dit ce qui
    /// manque, sinon l'utilisateur croit a un bug de l'app.
    private func unavailable(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "cloud.slash")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Palette.mist)
            Text(reason)
                .font(Theme.Typography.body(12))
                .foregroundStyle(Theme.Palette.mist)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}
