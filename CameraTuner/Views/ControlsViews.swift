import SwiftUI

struct ControlSection<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        }
    }
}

struct NoticeBanner: View {
    let text: String
    var symbol = "exclamationmark.triangle"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

struct HardwareControlsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let uvcName = model.uvcName {
                ControlSection(title: "UVC Camera", symbol: "camera.aperture") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(uvcName)
                            if let identity = model.uvcIdentity {
                                Text(identity)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }

                    Text("These controls are written directly to the camera hardware and affect other apps too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.hasHardwareControls {
                ForEach(UVCGroup.allCases) { group in
                    let states = model.hardwareStates(in: group)
                    if !states.isEmpty {
                        ControlSection(title: group.title, symbol: group.symbol) {
                            VStack(spacing: 10) {
                                ForEach(states) { state in
                                    HardwareControlRow(model: model, state: state)
                                    if state.id != states.last?.id {
                                        Divider().opacity(0.5)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                ControlSection(title: "No UVC controls", symbol: "camera.metering.unknown") {
                    Text(
                        model.hardwareError
                            ?? "Select an external UVC camera to see brightness, contrast, color, and exposure controls."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Button("Reload UVC controls") {
                        model.reloadHardware()
                    }
                    .controlSize(.small)
                }
            }

            if model.hasHardwareControls, let error = model.hardwareError {
                NoticeBanner(text: error)
            }
        }
    }
}

struct HardwareControlRow: View {
    @ObservedObject var model: AppModel
    let state: HardwareControlState

    private var auto: HardwareControlState? {
        model.autoState(for: state.id)
    }

    private var isAuto: Bool {
        auto != nil && model.isAuto(state.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.definition.label)
                    .lineLimit(1)
                Spacer()
                Text(state.definition.formatted(state.value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if state.definition.format == .powerLine, state.maximum >= 2 {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.hardware[state.id]?.value ?? state.value },
                            set: { model.setHardwareValue(state.id, value: $0) }
                        )
                    ) {
                        Text("Off").tag(0)
                        Text("50 Hz").tag(1)
                        Text("60 Hz").tag(2)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                } else if state.isToggle {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { (model.hardware[state.id]?.value ?? state.value) != 0 },
                            set: { model.setHardwareValue(state.id, value: $0 ? 1 : 0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                } else {
                    Slider(
                        value: model.hardwareBinding(state.id),
                        in: state.hasRange
                            ? Double(state.minimum)...Double(state.maximum)
                            : 0...1
                    )
                    .disabled(!state.hasRange || isAuto)
                }

                if auto != nil {
                    Toggle("Auto", isOn: model.autoBinding(state.id))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }

            if !state.hasRange, auto == nil {
                Text("No usable range reported by the camera.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct SoftwareControlsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ControlSection(title: "Preview", symbol: "wand.and.stars") {
                Toggle("Enable software adjustments", isOn: $model.software.enabled)
                    .toggleStyle(.switch)

                Text("Software adjustments change the live preview only; they are not applied to the camera feed used by other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                ControlSection(title: "Light", symbol: "sun.max") {
                    SoftwareSlider(
                        label: "Brightness",
                        value: $model.software.brightness,
                        range: -1...1
                    ) {
                        String(format: "%+.0f%%", $0 * 100)
                    }

                    SoftwareSlider(
                        label: "Contrast",
                        value: $model.software.contrast,
                        range: 0...2
                    ) {
                        String(format: "%.0f%%", $0 * 100)
                    }

                    SoftwareSlider(
                        label: "Gamma",
                        value: $model.software.gamma,
                        range: 0.2...3
                    ) {
                        String(format: "%.2f", $0)
                    }
                }

                ControlSection(title: "Color", symbol: "paintpalette") {
                    SoftwareSlider(
                        label: "Saturation",
                        value: $model.software.saturation,
                        range: 0...2
                    ) {
                        String(format: "%.0f%%", $0 * 100)
                    }

                    SoftwareSlider(
                        label: "Temperature",
                        value: $model.software.temperature,
                        range: 2000...10000,
                        step: 100
                    ) {
                        String(format: "%.0f K", $0)
                    }

                    SoftwareSlider(
                        label: "Tint",
                        value: $model.software.tint,
                        range: -150...150
                    ) {
                        String(format: "%+.0f", $0)
                    }

                    Divider()

                    SoftwareSlider(label: "Red", value: $model.software.red, range: 0...2) {
                        String(format: "%.0f%%", $0 * 100)
                    }
                    SoftwareSlider(label: "Green", value: $model.software.green, range: 0...2) {
                        String(format: "%.0f%%", $0 * 100)
                    }
                    SoftwareSlider(label: "Blue", value: $model.software.blue, range: 0...2) {
                        String(format: "%.0f%%", $0 * 100)
                    }
                }

                ControlSection(title: "Geometry", symbol: "rectangle.portrait.rotate") {
                    Toggle("Mirror preview", isOn: $model.software.mirror)
                        .toggleStyle(.switch)
                }
            }
            .disabled(!model.software.enabled)
            .opacity(model.software.enabled ? 1 : 0.5)

            if model.software.enabled, model.software.isNeutral {
                Text("No software adjustments are active.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct SoftwareSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let format: (Double) -> String

    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        format: @escaping (Double) -> String
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(format(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
    }
}
