import Foundation

enum UVCUnit {
    case cameraTerminal
    case processingUnit
}

enum UVCGroup: String, CaseIterable, Identifiable {
    case exposure
    case lens
    case color
    case image
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exposure: return "Exposure"
        case .lens: return "Lens"
        case .color: return "Color"
        case .image: return "Image"
        case .advanced: return "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .exposure: return "sun.max"
        case .lens: return "camera.aperture"
        case .color: return "paintpalette"
        case .image: return "slider.horizontal.3"
        case .advanced: return "gearshape.2"
        }
    }
}

struct UVCControlDefinition: Identifiable {
    enum Format {
        case raw
        case exposureTime
        case temperature
        case powerLine
    }

    let id: String
    let label: String
    let selector: UInt8
    let unit: UVCUnit
    let byteCount: Int
    let isSigned: Bool
    let controlBit: Int
    let group: UVCGroup
    let format: Format
    let isAutoControl: Bool
    let manualControlID: String?
    let autoControlID: String?
    let autoOffValue: Int?
    let autoOnValue: Int?

    func formatted(_ value: Int) -> String {
        switch format {
        case .raw:
            return "\(value)"
        case .exposureTime:
            let milliseconds = Double(value) / 10.0
            if milliseconds >= 100 {
                return String(format: "%.0f ms", milliseconds)
            }
            return String(format: "%.1f ms", milliseconds)
        case .temperature:
            return "\(value) K"
        case .powerLine:
            switch value {
            case 0: return "Off"
            case 1: return "50 Hz"
            case 2: return "60 Hz"
            default: return "\(value)"
            }
        }
    }
}

extension UVCControlDefinition {
    static let all: [UVCControlDefinition] = [

        UVCControlDefinition(
            id: "exposureAuto",
            label: "Auto Exposure",
            selector: 0x02,
            unit: .cameraTerminal,
            byteCount: 1,
            isSigned: false,
            controlBit: 1,
            group: .exposure,
            format: .raw,
            isAutoControl: true,
            manualControlID: "exposure",
            autoControlID: nil,
            autoOffValue: 1,
            autoOnValue: 2
        ),
        UVCControlDefinition(
            id: "exposure",
            label: "Exposure Time",
            selector: 0x04,
            unit: .cameraTerminal,
            byteCount: 4,
            isSigned: false,
            controlBit: 3,
            group: .exposure,
            format: .exposureTime,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: "exposureAuto",
            autoOffValue: nil,
            autoOnValue: nil
        ),
        UVCControlDefinition(
            id: "focusAuto",
            label: "Auto Focus",
            selector: 0x08,
            unit: .cameraTerminal,
            byteCount: 1,
            isSigned: false,
            controlBit: 7,
            group: .lens,
            format: .raw,
            isAutoControl: true,
            manualControlID: "focus",
            autoControlID: nil,
            autoOffValue: 0,
            autoOnValue: 1
        ),
        UVCControlDefinition(
            id: "focus",
            label: "Focus",
            selector: 0x06,
            unit: .cameraTerminal,
            byteCount: 2,
            isSigned: false,
            controlBit: 5,
            group: .lens,
            format: .raw,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: "focusAuto",
            autoOffValue: nil,
            autoOnValue: nil
        ),
        UVCControlDefinition(
            id: "zoom",
            label: "Zoom",
            selector: 0x0B,
            unit: .cameraTerminal,
            byteCount: 2,
            isSigned: false,
            controlBit: 10,
            group: .lens,
            format: .raw,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: nil,
            autoOffValue: nil,
            autoOnValue: nil
        ),


        UVCControlDefinition(
            id: "whiteBalanceAuto",
            label: "Auto White Balance",
            selector: 0x11,
            unit: .processingUnit,
            byteCount: 1,
            isSigned: false,
            controlBit: 17,
            group: .color,
            format: .raw,
            isAutoControl: true,
            manualControlID: "whiteBalance",
            autoControlID: nil,
            autoOffValue: 0,
            autoOnValue: 1
        ),
        UVCControlDefinition(
            id: "whiteBalance",
            label: "White Balance",
            selector: 0x0A,
            unit: .processingUnit,
            byteCount: 2,
            isSigned: false,
            controlBit: 9,
            group: .color,
            format: .temperature,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: "whiteBalanceAuto",
            autoOffValue: nil,
            autoOnValue: nil
        ),
        UVCControlDefinition(
            id: "hue",
            label: "Hue",
            selector: 0x06,
            unit: .processingUnit,
            byteCount: 2,
            isSigned: true,
            controlBit: 5,
            group: .color,
            format: .raw,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: nil,
            autoOffValue: nil,
            autoOnValue: nil
        ),
        UVCControlDefinition(
            id: "saturation",
            label: "Saturation",
            selector: 0x07,
            unit: .processingUnit,
            byteCount: 2,
            isSigned: false,
            controlBit: 6,
            group: .color,
            format: .raw,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: nil,
            autoOffValue: nil,
            autoOnValue: nil
        ),
        UVCControlDefinition(
            id: "brightness",
            label: "Brightness",
            selector: 0x02,
            unit: .processingUnit,
            byteCount: 2,
            isSigned: true,
            controlBit: 1,
            group: .image,
            format: .raw,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: nil,
            autoOffValue: nil,
            autoOnValue: nil
        ),
        UVCControlDefinition(
            id: "contrast",
            label: "Contrast",
            selector: 0x03,
            unit: .processingUnit,
            byteCount: 2,
            isSigned: false,
            controlBit: 2,
            group: .image,
            format: .raw,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: nil,
            autoOffValue: nil,
            autoOnValue: nil
        ),
        UVCControlDefinition(
            id: "gain",
            label: "Gain",
            selector: 0x04,
            unit: .processingUnit,
            byteCount: 2,
            isSigned: false,
            controlBit: 3,
            group: .image,
            format: .raw,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: nil,
            autoOffValue: nil,
            autoOnValue: nil
        ),
        UVCControlDefinition(
            id: "sharpness",
            label: "Sharpness",
            selector: 0x08,
            unit: .processingUnit,
            byteCount: 2,
            isSigned: false,
            controlBit: 7,
            group: .image,
            format: .raw,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: nil,
            autoOffValue: nil,
            autoOnValue: nil
        ),
        UVCControlDefinition(
            id: "gamma",
            label: "Gamma",
            selector: 0x09,
            unit: .processingUnit,
            byteCount: 2,
            isSigned: false,
            controlBit: 8,
            group: .image,
            format: .raw,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: nil,
            autoOffValue: nil,
            autoOnValue: nil
        ),
        UVCControlDefinition(
            id: "backlight",
            label: "Backlight Compensation",
            selector: 0x01,
            unit: .processingUnit,
            byteCount: 2,
            isSigned: false,
            controlBit: 0,
            group: .image,
            format: .raw,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: nil,
            autoOffValue: nil,
            autoOnValue: nil
        ),
        UVCControlDefinition(
            id: "powerLine",
            label: "Power Line Frequency",
            selector: 0x05,
            unit: .processingUnit,
            byteCount: 1,
            isSigned: false,
            controlBit: 4,
            group: .advanced,
            format: .powerLine,
            isAutoControl: false,
            manualControlID: nil,
            autoControlID: nil,
            autoOffValue: nil,
            autoOnValue: nil
        )
    ]

    static func definition(withID id: String) -> UVCControlDefinition? {
        all.first { $0.id == id }
    }
}
