import SwiftUI

struct PresetsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ControlSection(title: "Save Current", symbol: "square.and.arrow.down") {
                Text("A preset saves the current camera hardware values and the software look.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Preset name", text: $model.newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.saveCurrentProfile()
                    }

                HStack {
                    Button("Save Preset") {
                        model.saveCurrentProfile()
                    }
                    .disabled(
                        model.selectedCamera == nil
                            || model.newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Spacer()

                    if let defaultName = model.defaultProfileName {
                        Label("Auto: \(defaultName)", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let camera = model.selectedCamera {
                ControlSection(title: "Presets for \(camera.name)", symbol: "square.stack.3d.up") {
                    if model.profiles.isEmpty {
                        Text("No presets yet. Save the current setup above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(model.profiles) { profile in
                                PresetRow(
                                    model: model,
                                    profile: profile,
                                    isDefault: (model.defaultProfileName ?? "")
                                        .caseInsensitiveCompare(profile.name) == .orderedSame
                                )
                            }
                        }
                    }

                    if model.defaultProfileName == nil, !model.profiles.isEmpty {
                        Text("Star a preset to auto-apply it when this camera is selected or reconnects.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ControlSection(title: "Presets", symbol: "square.stack.3d.up") {
                    Text("Select a camera to manage its presets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = model.profileMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PresetRow: View {
    @ObservedObject var model: AppModel
    let profile: CameraProfile
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.applyProfile(profile)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .lineLimit(1)
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Apply \(profile.name)")

            Button {
                model.setDefaultProfile(isDefault ? nil : profile.name)
            } label: {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .foregroundStyle(isDefault ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(isDefault ? "Disable auto-apply" : "Auto-apply for this camera")

            Menu {
                Button("Apply") {
                    model.applyProfile(profile)
                }
                Button(isDefault ? "Disable Auto-Apply" : "Auto-Apply for This Camera") {
                    model.setDefaultProfile(isDefault ? nil : profile.name)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    model.deleteProfile(profile)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .help("Preset actions")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDefault ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
    }

    private var summary: String {
        let controlCount = profile.hardware.count
        if controlCount > 0 {
            let look = profile.software.isNeutral ? "neutral" : "custom"
            return "\(controlCount) camera values · \(look) look"
        }
        return profile.software.isNeutral ? "Neutral look" : "Custom look"
    }
}
