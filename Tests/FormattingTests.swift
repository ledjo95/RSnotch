import Foundation
import Testing
@testable import RSnotch

// MARK: - Formatage des durees
//
// Deux formateurs distincts — l'un pour le decompte du minuteur, l'autre pour
// la lecture — parce qu'ils divergent sur un point : le minuteur arrondit AU
// SUPERIEUR (afficher 0:00 alors qu'il reste une fraction parait casse), la
// lecture arrondit au plus proche. Ces tests fixent cette difference.

@Suite("Formatage des durées")
struct FormattingTests {

    @Test("Décompte : minutes et secondes sous l'heure")
    func countdownUnderHour() {
        #expect(Duration.seconds(0).countdownLabel == "0:00")
        #expect(Duration.seconds(5).countdownLabel == "0:05")
        #expect(Duration.seconds(65).countdownLabel == "1:05")
        #expect(Duration.seconds(600).countdownLabel == "10:00")
    }

    @Test("Décompte : l'heure n'apparaît qu'au-delà de 3600 s")
    func countdownHourBoundary() {
        #expect(Duration.seconds(3599).countdownLabel == "59:59")
        #expect(Duration.seconds(3600).countdownLabel == "1:00:00")
        #expect(Duration.seconds(3661).countdownLabel == "1:01:01")
    }

    @Test("Décompte : arrondi AU SUPÉRIEUR d'une fraction restante")
    func countdownRoundsUp() {
        // Il reste 0,1 s : le minuteur doit montrer 0:01, pas 0:00.
        #expect(Duration.milliseconds(100).countdownLabel == "0:01")
        #expect(Duration.milliseconds(1_500).countdownLabel == "0:02")
    }

    @Test("Lecture : minutes et secondes")
    func playbackUnderHour() {
        #expect(TimeInterval(0).playbackLabel == "0:00")
        #expect(TimeInterval(222).playbackLabel == "3:42")
        #expect(TimeInterval(59).playbackLabel == "0:59")
    }

    @Test("Lecture : l'heure apparaît au-delà de 3600 s")
    func playbackHours() {
        #expect(TimeInterval(3600).playbackLabel == "1:00:00")
        #expect(TimeInterval(3725).playbackLabel == "1:02:05")
    }
}
