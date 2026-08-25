import Foundation
import Observation

// MARK: - WeatherSnapshot
/// Ce dont le widget a besoin, et rien de plus. Garder ce type independant de
/// WeatherKit permet de developper l'UI avant que la capability soit accordee,
/// et de basculer de source sans toucher aux vues.
struct WeatherSnapshot: Equatable, Sendable {
    let temperature: Measurement<UnitTemperature>
    let feelsLike: Measurement<UnitTemperature>
    /// Condition traduite, prete a afficher.
    let condition: String
    /// Symbole SF fourni par la source (WeatherKit en expose un directement).
    let symbolName: String
    let locationName: String

    func formattedTemperature(_ value: Measurement<UnitTemperature>) -> String {
        let rounded = value.converted(to: .celsius).value.rounded()
        return "\(Int(rounded))°"
    }
}

// MARK: - WeatherProviding
protocol WeatherProviding: Sendable {
    func current() async throws -> WeatherSnapshot
}

// MARK: - WeatherAvailability
/// Etat expose a l'UI. Une source de meteo peut echouer pour des raisons tres
/// differentes (pas de reseau, localisation refusee, capability absente) et
/// chacune appelle un message different — d'ou un enum plutot qu'un `Error` nu.
enum WeatherAvailability: Equatable, Sendable {
    case idle
    case loading
    case ready(WeatherSnapshot)
    case unavailable(reason: String)
}

// MARK: - WeatherService
@MainActor
@Observable
final class WeatherService {

    private(set) var availability: WeatherAvailability = .idle

    private let provider: any WeatherProviding
    private var refreshTask: Task<Void, Never>?

    /// Intervalle de rafraichissement. La meteo ne bouge pas a la minute et
    /// chaque appel WeatherKit est facture au quota : 15 minutes suffisent.
    private let refreshInterval: Duration = .seconds(15 * 60)

    init(provider: any WeatherProviding = MockWeatherProvider()) {
        self.provider = provider
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.refreshInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        if case .ready = availability {} else { availability = .loading }
        do {
            availability = .ready(try await provider.current())
        } catch let error as WeatherProviderError {
            availability = .unavailable(reason: error.message)
        } catch {
            availability = .unavailable(reason: "Météo indisponible.")
        }
    }
}

// MARK: - WeatherProviderError
enum WeatherProviderError: Error, Sendable {
    case locationDenied
    case offline
    case notConfigured

    var message: String {
        switch self {
        case .locationDenied: "Localisation refusée."
        case .offline: "Hors ligne."
        case .notConfigured: "WeatherKit non configuré."
        }
    }
}

// MARK: - MockWeatherProvider
//
// Source de developpement. Elle existe pour que la Phase 2 se construise sans
// dependre d'une capability Apple Developer : brancher WeatherKit consistera a
// fournir un autre `WeatherProviding`, sans toucher au widget.
struct MockWeatherProvider: WeatherProviding {
    func current() async throws -> WeatherSnapshot {
        try? await Task.sleep(for: .milliseconds(120))
        return WeatherSnapshot(
            temperature: Measurement(value: 27, unit: .celsius),
            feelsLike: Measurement(value: 28, unit: .celsius),
            condition: "Partiellement nuageux",
            symbolName: "cloud.sun.fill",
            locationName: "Paris"
        )
    }
}
