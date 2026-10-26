import Foundation

struct SoftwareSettings: Equatable, Codable {
    var enabled = true

    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var gamma: Double = 1

    var red: Double = 1
    var green: Double = 1
    var blue: Double = 1

    var temperature: Double = 6500
    var tint: Double = 0

    var mirror = false

    static let defaultTemperature = 6500.0

    var isNeutral: Bool {
        brightness == 0
            && contrast == 1
            && saturation == 1
            && gamma == 1
            && red == 1
            && green == 1
            && blue == 1
            && temperature == Self.defaultTemperature
            && tint == 0
            && !mirror
    }

    mutating func reset() {
        self = SoftwareSettings()
    }
}
