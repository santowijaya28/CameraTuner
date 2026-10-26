import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI
import os

struct CameraChoice: Identifiable {
    let id: String
    let name: String
    let modelID: String
    let device: AVCaptureDevice
}

struct HardwareControlState: Identifiable {
    let definition: UVCControlDefinition
    var value: Int
    var minimum: Int
    var maximum: Int
    var defaultValue: Int

    var id: String { definition.id }

    var hasRange: Bool {
        maximum > minimum
    }

    var isToggle: Bool {
        definition.format == .raw && minimum == 0 && maximum == 1
    }
}

private let logger = Logger(subsystem: "com.santowijaya.CameraTuner", category: "CameraTuner")

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var cameras: [CameraChoice] = []
    @Published var selectedCameraID: String? {
        didSet {
            guard oldValue != selectedCameraID else { return }
            lastAutoAppliedProfileKey = nil
            profileMessage = nil
            reloadHardware()
        }
    }

    @Published private(set) var hardware: [String: HardwareControlState] = [:]
    @Published private(set) var hardwareError: String?
    @Published private(set) var uvcName: String?
    @Published private(set) var uvcIdentity: String?

    @Published var software = SoftwareSettings()
    @Published var section: SidebarSection = .hardware
    @Published var newProfileName = ""
    @Published private(set) var profiles: [CameraProfile] = []
    @Published private(set) var defaultProfileName: String?
    @Published private(set) var profileMessage: String?
    @Published private(set) var cameraAuthorized = false
    @Published private(set) var permissionDenied = false

    private var uvcDevices: [UVCDevice] = []
    private var activeUVC: UVCDevice?
    private var deviceObservers: [NSObjectProtocol] = []
    private var profileStore = ProfileStore()
    private var lastAutoAppliedProfileKey: String?

    var selectedCamera: CameraChoice? {
        guard let selectedCameraID else { return nil }
        return cameras.first { $0.id == selectedCameraID }
    }

    var previewDevice: AVCaptureDevice? {
        cameraAuthorized ? selectedCamera?.device : nil
    }

    var hasHardwareControls: Bool {
        !hardware.isEmpty
    }

    var profileKey: String? {
        selectedCamera.map { "model:\($0.modelID)" }
    }

    init() {
        observeDeviceChanges()
        checkCameraPermission()
        refreshCameras()
    }

    deinit {
        deviceObservers.forEach { NotificationCenter.default.removeObserver($0) }
        uvcDevices.forEach { $0.close() }
    }


    func refresh() {
        refreshCameras()
    }

    func refreshCameras() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )

        cameras = discovery.devices.map { device in
            CameraChoice(
                id: device.uniqueID,
                name: device.localizedName,
                modelID: device.modelID,
                device: device
            )
        }

        let targetID: String?
        if let selectedCameraID, cameras.contains(where: { $0.id == selectedCameraID }) {
            targetID = selectedCameraID
        } else {
            targetID = cameras.first?.id
        }

        if targetID != selectedCameraID {
            selectedCameraID = targetID
        } else {
            reloadHardware()
        }
    }

    private func observeDeviceChanges() {
        let center = NotificationCenter.default
        deviceObservers.append(
            center.addObserver(
                forName: .AVCaptureDeviceWasConnected,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.lastAutoAppliedProfileKey = nil
                    self?.refreshCameras()
                }
            }
        )
        deviceObservers.append(
            center.addObserver(
                forName: .AVCaptureDeviceWasDisconnected,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.lastAutoAppliedProfileKey = nil
                    self?.refreshCameras()
                }
            }
        )
        deviceObservers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.checkCameraPermission()
                }
            }
        )
    }


    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        logger.debug("Camera authorization status: \(status.rawValue, privacy: .public)")
        switch status {
        case .authorized:
            cameraAuthorized = true
            permissionDenied = false
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    logger.debug("Camera access granted: \(granted, privacy: .public)")
                    self?.cameraAuthorized = granted
                    self?.permissionDenied = !granted
                    if granted {
                        self?.refreshCameras()
                    }
                }
            }
        default:
            cameraAuthorized = false
            permissionDenied = true
        }
    }

    func openCameraPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else { return }
        NSWorkspace.shared.open(url)
    }


    func reloadHardware() {
        profileMessage = nil
        defer {
            refreshProfiles()
            autoApplyDefaultProfileIfNeeded()
        }

        uvcDevices.forEach { $0.close() }
        uvcDevices = UVCDevice.discover()
        logger.info("Found \(self.cameras.count, privacy: .public) camera(s), \(self.uvcDevices.count, privacy: .public) UVC device(s)")
        activeUVC = nil
        hardware = [:]
        hardwareError = nil
        uvcName = nil
        uvcIdentity = nil

        guard let camera = selectedCamera else {
            if !cameras.isEmpty {
                hardwareError = "Select a camera to read its controls."
            }
            return
        }

        guard let device = uvcDevices.first(where: {
            $0.matches(modelID: camera.modelID, cameraName: camera.name)
        }) else {
            hardwareError = "No UVC hardware controls were found for this camera. Built-in and Continuity cameras usually do not expose them."
            logger.info("No UVC device matched camera \(camera.name, privacy: .public) (\(camera.modelID, privacy: .public))")
            return
        }

        do {
            try device.open()
            activeUVC = device
            uvcName = device.name
            uvcIdentity = device.identity
            loadHardwareValues(from: device)
            logger.info("Loaded \(self.hardware.count, privacy: .public) controls from \(device.name, privacy: .public) via \(device.isUsingInterface ? "VideoControl interface" : "USB device", privacy: .public)")

            if hardware.isEmpty {
                hardwareError = "This camera does not expose any standard UVC controls."
            }
        } catch {
            activeUVC = nil
            hardwareError = error.localizedDescription
            logger.error("UVC load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refreshHardwareValues() {
        guard let device = activeUVC else { return }
        for id in Array(hardware.keys) {
            guard let state = hardware[id] else { continue }
            if let value = try? device.value(state.definition) {
                setCachedValue(value, for: id)
            }
        }
        hardwareError = nil
    }

    private func loadHardwareValues(from device: UVCDevice) {
        for definition in UVCControlDefinition.all where device.supports(definition) {
            guard let current = try? device.value(definition) else { continue }

            var minimum = (try? device.value(definition, request: .getMinimum)) ?? current
            var maximum = (try? device.value(definition, request: .getMaximum)) ?? current
            let defaultValue = (try? device.value(definition, request: .getDefault)) ?? current

            if maximum <= minimum {
                if definition.byteCount == 4 {
                    minimum = 0
                    maximum = max(current, 10_000)
                } else if definition.isSigned {
                    minimum = -100
                    maximum = max(current, 100)
                } else {
                    minimum = 0
                    maximum = max(current, 255)
                }
            }

            hardware[definition.id] = HardwareControlState(
                definition: definition,
                value: current,
                minimum: minimum,
                maximum: maximum,
                defaultValue: defaultValue
            )
        }
    }

    func hardwareStates(in group: UVCGroup) -> [HardwareControlState] {
        UVCControlDefinition.all.compactMap { definition in
            guard definition.group == group, !definition.isAutoControl else { return nil }
            return hardware[definition.id]
        }
    }

    func autoState(for controlID: String) -> HardwareControlState? {
        guard let manual = hardware[controlID],
              let autoID = manual.definition.autoControlID else {
            return nil
        }
        return hardware[autoID]
    }

    func isAuto(_ controlID: String) -> Bool {
        guard let auto = autoState(for: controlID),
              let offValue = auto.definition.autoOffValue else {
            return false
        }
        return auto.value != offValue
    }

    func hardwareBinding(_ controlID: String) -> Binding<Double> {
        Binding(
            get: { Double(self.hardware[controlID]?.value ?? 0) },
            set: { self.setHardwareValue(controlID, value: Int($0.rounded())) }
        )
    }

    func autoBinding(_ controlID: String) -> Binding<Bool> {
        Binding(
            get: { self.isAuto(controlID) },
            set: { self.setAuto(controlID, enabled: $0) }
        )
    }

    func setHardwareValue(_ controlID: String, value: Int) {
        guard let device = activeUVC,
              let state = hardware[controlID] else {
            return
        }

        let clamped = min(max(value, state.minimum), state.maximum)

        do {
            if let auto = autoState(for: controlID),
               isAuto(controlID),
               let offValue = auto.definition.autoOffValue {
                try device.setValue(auto.definition, to: offValue)
                setCachedValue(offValue, for: auto.id)
            }

            try device.setValue(state.definition, to: clamped)
            setCachedValue(clamped, for: controlID)
            hardwareError = nil
        } catch {
            hardwareError = error.localizedDescription
        }
    }

    func setAuto(_ controlID: String, enabled: Bool) {
        guard let device = activeUVC,
              let auto = autoState(for: controlID) else {
            return
        }

        let offValue = auto.definition.autoOffValue ?? 0
        let onValue: Int
        if auto.defaultValue != offValue, auto.defaultValue != 0 {
            onValue = auto.defaultValue
        } else {
            onValue = auto.definition.autoOnValue ?? 1
        }
        let target = enabled ? onValue : offValue

        do {
            try device.setValue(auto.definition, to: target)
            setCachedValue(target, for: auto.id)

            if !enabled, let manual = hardware[controlID],
               let current = try? device.value(manual.definition) {
                setCachedValue(current, for: controlID)
            }
            hardwareError = nil
        } catch {
            hardwareError = error.localizedDescription
        }
    }

    func resetHardware() {
        guard let device = activeUVC else { return }

        let autoStates = hardware.values.filter { $0.definition.isAutoControl }
        let manualStates = hardware.values.filter { !$0.definition.isAutoControl }

        for state in autoStates {
            if let offValue = state.definition.autoOffValue {
                try? device.setValue(state.definition, to: offValue)
            }
        }
        for state in manualStates {
            try? device.setValue(state.definition, to: state.defaultValue)
        }
        for state in autoStates {
            try? device.setValue(state.definition, to: state.defaultValue)
        }

        refreshHardwareValues()
    }

    private func setCachedValue(_ value: Int, for controlID: String) {
        guard var state = hardware[controlID] else { return }
        state.value = value
        hardware[controlID] = state
    }

    func saveCurrentProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            profileMessage = "Enter a preset name."
            return
        }
        guard let key = profileKey else {
            profileMessage = "Select a camera first."
            return
        }

        let values = hardware.mapValues { $0.value }
        let profile = profileStore.saveProfile(
            named: name,
            software: software,
            hardware: values,
            for: key
        )

        if profileStore.defaultName(for: key) == nil {
            profileStore.setDefaultProfile(named: profile.name, for: key)
        }

        newProfileName = ""
        refreshProfiles()
        profileMessage = "Saved \(profile.name)."
        logger.info("Saved preset \(profile.name, privacy: .public) with \(values.count, privacy: .public) hardware values")
    }

    func applyProfile(_ profile: CameraProfile) {
        software = profile.software

        if activeUVC != nil {
            applyHardwareValues(profile.hardware)
        }

        if !profile.hardware.isEmpty, activeUVC == nil {
            profileMessage = "Applied \(profile.name) look; camera hardware is unavailable."
        } else if hardwareError != nil {
            profileMessage = "Applied \(profile.name) with camera errors."
        } else {
            profileMessage = "Applied \(profile.name)."
        }
        logger.info("Applied preset \(profile.name, privacy: .public)")
    }

    func setDefaultProfile(_ name: String?) {
        guard let key = profileKey else { return }
        profileStore.setDefaultProfile(named: name, for: key)
        refreshProfiles()

        if let name {
            profileMessage = "\(name) will auto-apply for this camera."
        } else {
            profileMessage = "Auto-apply disabled for this camera."
        }
    }

    func deleteProfile(_ profile: CameraProfile) {
        guard let key = profileKey else { return }
        profileStore.deleteProfile(named: profile.name, for: key)
        refreshProfiles()
        profileMessage = "Deleted \(profile.name)."
    }

    private func refreshProfiles() {
        guard let key = profileKey else {
            profiles = []
            defaultProfileName = nil
            return
        }

        profiles = profileStore.profiles(for: key).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        defaultProfileName = profileStore.defaultName(for: key)
    }

    private func autoApplyDefaultProfileIfNeeded() {
        guard let key = profileKey else { return }
        guard lastAutoAppliedProfileKey != key else { return }

        guard let name = defaultProfileName,
              let profile = profiles.first(where: {
                  $0.name.caseInsensitiveCompare(name) == .orderedSame
              }) else {
            lastAutoAppliedProfileKey = key
            return
        }

        guard profile.hardware.isEmpty || activeUVC != nil else { return }

        applyProfile(profile)
        lastAutoAppliedProfileKey = key
        profileMessage = "Auto-applied \(profile.name)."
        logger.info("Auto-applied preset \(profile.name, privacy: .public)")
    }

    private func applyHardwareValues(_ values: [String: Int]) {
        guard let device = activeUVC else { return }

        var failure: String?
        let autoStates = hardware.values.filter { $0.definition.isAutoControl }

        for auto in autoStates {
            let manualHasValue = auto.definition.manualControlID.flatMap { values[$0] } != nil
            guard values[auto.id] != nil || manualHasValue else { continue }
            guard let offValue = auto.definition.autoOffValue else { continue }

            do {
                try device.setValue(auto.definition, to: offValue)
                setCachedValue(offValue, for: auto.id)
            } catch {
                failure = error.localizedDescription
            }
        }

        for (id, value) in values {
            guard let state = hardware[id], !state.definition.isAutoControl else { continue }
            let clamped = min(max(value, state.minimum), state.maximum)

            do {
                try device.setValue(state.definition, to: clamped)
                setCachedValue(clamped, for: id)
            } catch {
                failure = error.localizedDescription
            }
        }

        for (id, value) in values {
            guard let state = hardware[id], state.definition.isAutoControl else { continue }

            do {
                try device.setValue(state.definition, to: value)
                setCachedValue(value, for: id)
            } catch {
                failure = error.localizedDescription
            }
        }

        hardwareError = failure
    }

    func resetSoftware() {
        software.reset()
    }
}
