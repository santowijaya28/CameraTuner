import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib

enum UVCRequest: UInt8 {
    case setCurrent = 0x01
    case getCurrent = 0x81
    case getMinimum = 0x82
    case getMaximum = 0x83
    case getResolution = 0x84
    case getInfo = 0x86
    case getDefault = 0x87
}

struct UVCError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private typealias PlugInPointer = UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>
private typealias DevicePointer = UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>
private typealias InterfacePointer = UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>?>

private func uvcUUID(_ bytes: [UInt8]) -> CFUUID {
    CFUUIDGetConstantUUIDWithBytes(
        kCFAllocatorDefault,
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    )!
}

private let plugInInterfaceUUID = uvcUUID([
    0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
    0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F
])

private let deviceUserClientUUID = uvcUUID([
    0x9D, 0xC7, 0xB7, 0x80, 0x9E, 0xC0, 0x11, 0xD4,
    0xA5, 0x4F, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61
])

private let deviceInterfaceUUID = uvcUUID([
    0x5C, 0x81, 0x87, 0xD0, 0x9E, 0xF3, 0x11, 0xD4,
    0x8B, 0x45, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61
])

private let interfaceUserClientUUID = uvcUUID([
    0x2D, 0x97, 0x86, 0xC6, 0x9E, 0xF3, 0x11, 0xD4,
    0xAD, 0x51, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61
])

private let interfaceInterfaceUUID = uvcUUID([
    0x73, 0xC9, 0x7A, 0xE8, 0x9E, 0xF3, 0x11, 0xD4,
    0xB1, 0xD0, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61
])

private func queryInterface<T>(
    plugin: PlugInPointer,
    uuid: CFUUID
) -> UnsafeMutablePointer<UnsafeMutablePointer<T>?>? {
    var result: UnsafeMutablePointer<UnsafeMutablePointer<T>?>?
    let status = withUnsafeMutablePointer(to: &result) { pointer in
        pointer.withMemoryRebound(to: Optional<LPVOID>.self, capacity: 1) { rebound in
            plugin.pointee!.pointee.QueryInterface(
                plugin,
                CFUUIDGetUUIDBytes(uuid),
                rebound
            )
        }
    }
    return status == kIOReturnSuccess ? result : nil
}

private func registryProperty<T>(_ service: io_service_t, _ key: String) -> T? {
    IORegistryEntryCreateCFProperty(
        service,
        key as CFString,
        kCFAllocatorDefault,
        0
    )?.takeRetainedValue() as? T
}

private func hexStatus(_ status: IOReturn) -> String {
    String(format: "0x%08X", UInt32(bitPattern: status))
}

final class UVCDevice {
    let service: io_service_t
    let name: String
    let vendorID: Int
    let productID: Int
    let locationID: Int

    private(set) var interfaceNumber: UInt8 = 0
    private(set) var cameraTerminalID: UInt8 = 0
    private(set) var processingUnitID: UInt8 = 0
    private(set) var hasVideoControl = false

    private var cameraControls: UInt64 = 0
    private var processingControls: UInt64 = 0

    private var plugIn: PlugInPointer?
    private var device: DevicePointer?
    private var interfacePlugIn: PlugInPointer?
    private var interface: InterfacePointer?

    private var isOpen = false
    private var usesInterface = false

    var identity: String {
        String(format: "%04X:%04X", vendorID, productID)
    }

    var isUsingInterface: Bool { usesInterface }

    init?(service: io_service_t) {
        self.service = service
        self.name = registryProperty(service, "USB Product Name")
            ?? registryProperty(service, "Product Name")
            ?? "USB Camera"
        self.vendorID = registryProperty(service, "idVendor") ?? 0
        self.productID = registryProperty(service, "idProduct") ?? 0
        self.locationID = registryProperty(service, "locationID") ?? 0

        var score: Int32 = 0
        var plugin: PlugInPointer?
        guard IOCreatePlugInInterfaceForService(
            service,
            deviceUserClientUUID,
            plugInInterfaceUUID,
            &plugin,
            &score
        ) == kIOReturnSuccess, let plugin else {
            return nil
        }
        self.plugIn = plugin

        guard let device: DevicePointer = queryInterface(plugin: plugin, uuid: deviceInterfaceUUID) else {
            return nil
        }
        self.device = device

        parseDescriptors()
        guard hasVideoControl else { return nil }
    }

    deinit {
        close()
        IOObjectRelease(service)
    }

    static func discover() -> [UVCDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOUSBDevice"),
            &iterator
        ) == kIOReturnSuccess else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [UVCDevice] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            if let device = UVCDevice(service: service) {
                devices.append(device)
            }
        }
        return devices
    }

    func matches(modelID: String, cameraName: String) -> Bool {
        let decimal = "VendorID_\(vendorID) ProductID_\(productID)"
        let hex = String(format: "VendorID_%04X ProductID_%04X", vendorID, productID)
        if modelID.localizedCaseInsensitiveContains(decimal)
            || modelID.localizedCaseInsensitiveContains(hex) {
            return true
        }

        let normalizedModel = modelID.replacingOccurrences(of: "_", with: " ")
        if !name.isEmpty, !normalizedModel.isEmpty,
           normalizedModel.localizedCaseInsensitiveContains(name)
               || name.localizedCaseInsensitiveContains(normalizedModel) {
            return true
        }

        if !name.isEmpty, !cameraName.isEmpty,
           cameraName.localizedCaseInsensitiveContains(name)
               || name.localizedCaseInsensitiveContains(cameraName) {
            return true
        }

        return false
    }

    func supports(_ control: UVCControlDefinition) -> Bool {
        switch control.unit {
        case .cameraTerminal:
            guard cameraTerminalID != 0 else { return false }
            return cameraControls & (UInt64(1) << UInt64(control.controlBit)) != 0
        case .processingUnit:
            guard processingUnitID != 0 else { return false }
            return processingControls & (UInt64(1) << UInt64(control.controlBit)) != 0
        }
    }

    func open() throws {
        if isOpen { return }
        guard let device else {
            throw UVCError(message: "USB device interface is unavailable.")
        }

        var status = device.pointee!.pointee.USBDeviceOpen(device)
        if status != kIOReturnSuccess {
            status = device.pointee!.pointee.USBDeviceOpenSeize(device)
        }
        if status == kIOReturnSuccess {
            isOpen = true
            usesInterface = false
            return
        }

        let deviceStatus = hexStatus(status)

        var request = IOUSBFindInterfaceRequest(
            bInterfaceClass: 0x0E,
            bInterfaceSubClass: 0x01,
            bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
            bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
        )
        var iterator: io_iterator_t = 0
        guard device.pointee!.pointee.CreateInterfaceIterator(device, &request, &iterator) == kIOReturnSuccess else {
            throw UVCError(message: "Could not enumerate the camera's video interfaces.")
        }
        defer { IOObjectRelease(iterator) }

        let interfaceService = IOIteratorNext(iterator)
        guard interfaceService != 0 else {
            throw UVCError(message: "No UVC VideoControl interface was found.")
        }
        defer { IOObjectRelease(interfaceService) }

        var score: Int32 = 0
        var plugin: PlugInPointer?
        guard IOCreatePlugInInterfaceForService(
            interfaceService,
            interfaceUserClientUUID,
            plugInInterfaceUUID,
            &plugin,
            &score
        ) == kIOReturnSuccess, let plugin else {
            throw UVCError(message: "Could not create a USB interface plug-in.")
        }
        interfacePlugIn = plugin

        guard let interface: InterfacePointer = queryInterface(plugin: plugin, uuid: interfaceInterfaceUUID) else {
            throw UVCError(message: "Could not query the USB interface.")
        }
        self.interface = interface

        var number: UInt8 = 0
        _ = interface.pointee!.pointee.GetInterfaceNumber(interface, &number)
        interfaceNumber = number

        status = interface.pointee!.pointee.USBInterfaceOpen(interface)
        if status != kIOReturnSuccess {
            status = interface.pointee!.pointee.USBInterfaceOpenSeize(interface)
        }
        guard status == kIOReturnSuccess else {
            throw UVCError(
                message: "Could not open the camera (device \(deviceStatus), interface \(hexStatus(status)))."
            )
        }

        isOpen = true
        usesInterface = true
    }

    func close() {
        if let interface {
            if usesInterface {
                _ = interface.pointee!.pointee.USBInterfaceClose(interface)
            }
            _ = interface.pointee!.pointee.Release(interface)
            self.interface = nil
        }

        if let interfacePlugIn {
            IODestroyPlugInInterface(interfacePlugIn)
            self.interfacePlugIn = nil
        }

        if let device {
            if isOpen && !usesInterface {
                _ = device.pointee!.pointee.USBDeviceClose(device)
            }
            _ = device.pointee!.pointee.Release(device)
            self.device = nil
        }

        if let plugIn {
            IODestroyPlugInInterface(plugIn)
            self.plugIn = nil
        }

        isOpen = false
        usesInterface = false
    }

    func value(
        _ control: UVCControlDefinition,
        request: UVCRequest = .getCurrent
    ) throws -> Int {
        var bytes = [UInt8](repeating: 0, count: control.byteCount)
        try transfer(request, control: control, data: &bytes)
        return decode(bytes, signed: control.isSigned)
    }

    func setValue(_ control: UVCControlDefinition, to value: Int) throws {
        guard control.byteCount > 0 else { return }
        var bytes = encode(value, length: control.byteCount)
        try transfer(.setCurrent, control: control, data: &bytes)
    }

    func info(for control: UVCControlDefinition) -> UInt8? {
        var bytes = [UInt8](repeating: 0, count: 1)
        guard (try? transfer(.getInfo, control: control, data: &bytes)) != nil else {
            return nil
        }
        return bytes[0]
    }

    private func transfer(
        _ request: UVCRequest,
        control: UVCControlDefinition,
        data: inout [UInt8]
    ) throws {
        try open()

        guard let device else {
            throw UVCError(message: "USB device is not open.")
        }

        let unitID: UInt8
        switch control.unit {
        case .cameraTerminal:
            unitID = cameraTerminalID
        case .processingUnit:
            unitID = processingUnitID
        }
        guard unitID != 0 else {
            throw UVCError(message: "The camera did not expose a \(control.unit) unit.")
        }

        let isRead = request != .setCurrent
        var usbRequest = IOUSBDevRequest()
        usbRequest.bmRequestType = isRead ? 0xA1 : 0x21
        usbRequest.bRequest = request.rawValue
        usbRequest.wValue = UInt16(control.selector) << 8
        usbRequest.wIndex = (UInt16(unitID) << 8) | UInt16(interfaceNumber)
        usbRequest.wLength = UInt16(data.count)

        let status: IOReturn = data.withUnsafeMutableBytes { buffer in
            usbRequest.pData = buffer.baseAddress
            if usesInterface, let interface {
                return interface.pointee!.pointee.ControlRequest(interface, 0, &usbRequest)
            }
            return device.pointee!.pointee.DeviceRequest(device, &usbRequest)
        }

        guard status == kIOReturnSuccess else {
            throw UVCError(
                message: "UVC request for \(control.label) failed (\(hexStatus(status)))."
            )
        }
    }

    private func decode(_ bytes: [UInt8], signed: Bool) -> Int {
        var raw: UInt64 = 0
        for (index, byte) in bytes.enumerated() {
            raw |= UInt64(byte) << UInt64(index * 8)
        }

        guard signed else { return Int(raw) }

        switch bytes.count {
        case 1:
            return Int(Int8(bitPattern: UInt8(truncatingIfNeeded: raw)))
        case 2:
            return Int(Int16(bitPattern: UInt16(truncatingIfNeeded: raw)))
        case 4:
            return Int(Int32(bitPattern: UInt32(truncatingIfNeeded: raw)))
        default:
            return Int(raw)
        }
    }

    private func encode(_ value: Int, length: Int) -> [UInt8] {
        let raw = UInt64(bitPattern: Int64(value))
        return (0..<length).map { index in
            UInt8((raw >> UInt64(index * 8)) & 0xFF)
        }
    }

    private func parseDescriptors() {
        guard let device else { return }

        var descriptorPointer: IOUSBConfigurationDescriptorPtr?
        guard device.pointee!.pointee.GetConfigurationDescriptorPtr(
            device,
            0,
            &descriptorPointer
        ) == kIOReturnSuccess, let descriptorPointer else {
            return
        }

        let bytes = UnsafeRawPointer(descriptorPointer)
            .assumingMemoryBound(to: UInt8.self)
        let totalLength = Int(UInt16(littleEndian: descriptorPointer.pointee.wTotalLength))
        var offset = 0
        var isVideoControlInterface = false

        while offset + 2 <= totalLength {
            let length = Int(bytes[offset])
            let type = bytes[offset + 1]
            if length == 0 { break }

            if type == 0x04, length >= 9 {
                isVideoControlInterface = bytes[offset + 5] == 0x0E
                    && bytes[offset + 6] == 0x01
                if isVideoControlInterface {
                    interfaceNumber = bytes[offset + 2]
                    hasVideoControl = true
                }
            } else if isVideoControlInterface && type == 0x24, length >= 3 {
                let subtype = bytes[offset + 2]

                if subtype == 0x02, length >= 16 {
                    let terminalType = UInt16(bytes[offset + 4])
                        | (UInt16(bytes[offset + 5]) << 8)
                    if terminalType == 0x0201 {
                        cameraTerminalID = bytes[offset + 3]
                        let controlSize = Int(bytes[offset + 14])
                        cameraControls = readBitmap(
                            bytes,
                            start: offset + 15,
                            size: controlSize,
                            limit: offset + length
                        )
                    }
                } else if subtype == 0x05, length >= 9 {
                    processingUnitID = bytes[offset + 3]
                    let controlSize = Int(bytes[offset + 7])
                    processingControls = readBitmap(
                        bytes,
                        start: offset + 8,
                        size: controlSize,
                        limit: offset + length
                    )
                }
            }

            offset += length
        }
    }

    private func readBitmap(
        _ bytes: UnsafePointer<UInt8>,
        start: Int,
        size: Int,
        limit: Int
    ) -> UInt64 {
        guard size > 0 else { return 0 }
        let available = max(0, min(size, limit - start, 8))
        var bitmap: UInt64 = 0
        for index in 0..<available {
            bitmap |= UInt64(bytes[start + index]) << UInt64(index * 8)
        }
        return bitmap
    }
}
