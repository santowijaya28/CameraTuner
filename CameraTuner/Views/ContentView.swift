import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case hardware
    case software
    case presets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hardware: return "Camera"
        case .software: return "Look"
        case .presets: return "Presets"
        }
    }

    var symbol: String {
        switch self {
        case .hardware: return "camera"
        case .software: return "wand.and.stars"
        case .presets: return "square.stack.3d.up"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                previewPane
                Divider()
                sidebar
            }
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Camera Tuner")
                    .font(.title2.weight(.semibold))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Picker("Camera", selection: $model.selectedCameraID) {
                if model.cameras.isEmpty {
                    Text("No cameras found").tag(Optional<String>.none)
                }
                ForEach(model.cameras) { camera in
                    Text(camera.name).tag(Optional(camera.id))
                }
            }
            .labelsHidden()
            .frame(width: 260)

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh camera list")

            Button {
                model.reloadHardware()
            } label: {
                Image(systemName: "cable.connector")
            }
            .help("Reload UVC controls")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusText: String {
        if !model.cameraAuthorized {
            return model.permissionDenied ? "Camera access is disabled" : "Requesting camera access…"
        }
        if let camera = model.selectedCamera {
            if let uvcName = model.uvcName {
                return "\(camera.name) · \(uvcName) (\(model.uvcIdentity ?? ""))"
            }
            return "\(camera.name) · software controls"
        }
        return "No camera selected"
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black)

                CameraPreviewView(
                    device: model.previewDevice,
                    settings: model.software
                )

                if !model.cameraAuthorized {
                    permissionOverlay
                } else if model.selectedCamera == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 34, weight: .light))
                        Text("No camera available")
                            .font(.headline)
                        Text("Connect a USB or Continuity camera, then refresh.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(24)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

            HStack(spacing: 10) {
                if model.software.enabled {
                    Label("Software look active", systemImage: "wand.and.stars")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Software look bypassed", systemImage: "slash.circle")
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if let uvcName = model.uvcName {
                    Label(uvcName, systemImage: "camera.aperture")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if let error = model.hardwareError {
                NoticeBanner(text: error)
            }
        }
        .padding(18)
        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var permissionOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: model.permissionDenied ? "video.slash" : "video")
                .font(.system(size: 34, weight: .light))
            Text(model.permissionDenied ? "Camera access is off" : "Camera access needed")
                .font(.headline)
            Text(
                model.permissionDenied
                    ? "Allow Camera Tuner in System Settings to see a live preview."
                    : "The system will ask for camera access when it is ready."
            )
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 280)

            if model.permissionDenied {
                Button("Open System Settings") {
                    model.openCameraPrivacySettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(20)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $model.section) {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            ScrollView {
                Group {
                    switch model.section {
                    case .hardware:
                        HardwareControlsView(model: model)
                    case .software:
                        SoftwareControlsView(model: model)
                    case .presets:
                        PresetsView(model: model)
                    }
                }
                .padding(14)
            }

            if model.section != .presets {
                Divider()

                HStack {
                    Button(model.section == .hardware ? "Reset Camera Defaults" : "Reset Look") {
                        switch model.section {
                        case .hardware:
                            model.resetHardware()
                        case .software:
                            model.resetSoftware()
                        case .presets:
                            break
                        }
                    }
                    .disabled(model.section == .hardware && !model.hasHardwareControls)

                    Spacer()

                    if model.section == .hardware {
                        Button {
                            model.refreshHardwareValues()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .help("Read current camera values")
                        .disabled(!model.hasHardwareControls)
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 340, idealWidth: 380, maxWidth: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
