import AppKit
import AVFoundation
import CoreImage
import MetalKit
import SwiftUI
import os

private let previewLogger = Logger(subsystem: "com.santowijaya.CameraTuner", category: "Preview")

struct CameraPreviewView: NSViewRepresentable {
    let device: AVCaptureDevice?
    let settings: SoftwareSettings

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.update(device: device, settings: settings)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.update(device: device, settings: settings)
    }

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: Void) {
        nsView.stop()
    }
}

final class CameraPreviewNSView: NSView, AVCaptureVideoDataOutputSampleBufferDelegate, MTKViewDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "CameraTuner.capture-session")
    private let frameQueue = DispatchQueue(label: "CameraTuner.capture-frames", qos: .userInitiated)
    private let frameLock = NSLock()

    private let metalView = MTKView()
    private var ciContext: CIContext?
    private var commandQueue: MTLCommandQueue?

    private var currentDeviceID: String?
    private var latestFrame: CIImage?
    private var settings = SoftwareSettings()
    private var hasLoggedFirstFrame = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        metalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metalView)
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setupMetal()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(device: AVCaptureDevice?, settings: SoftwareSettings) {
        frameLock.lock()
        self.settings = settings
        frameLock.unlock()

        let newDeviceID = device?.uniqueID
        if newDeviceID != currentDeviceID {
            previewLogger.info("Preview device changed: \(newDeviceID ?? "nil", privacy: .public)")
            currentDeviceID = newDeviceID
            frameLock.lock()
            latestFrame = nil
            hasLoggedFirstFrame = false
            frameLock.unlock()
            sessionQueue.async { [weak self] in
                self?.configureSession(device: device)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.metalView.setNeedsDisplay(self.metalView.bounds)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.session.commitConfiguration()
        }
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return
        }

        metalView.device = device
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = false
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        metalView.autoResizeDrawable = true
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.delegate = self

        commandQueue = queue
        ciContext = CIContext(mtlCommandQueue: queue)
    }

    private func configureSession(device: AVCaptureDevice?) {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.sessionPreset = .high

        var addedInput = false

        if let device {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                    addedInput = true
                }
            } catch {
                addedInput = false
            }

            if addedInput {
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                output.setSampleBufferDelegate(self, queue: frameQueue)
                if session.canAddOutput(output) {
                    session.addOutput(output)
                }
            }
        }

        session.commitConfiguration()

        if addedInput {
            if !session.isRunning {
                session.startRunning()
            }
            previewLogger.info("Capture session running: \(self.session.isRunning, privacy: .public)")
        } else if session.isRunning {
            session.stopRunning()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        frameLock.lock()
        let currentSettings = settings
        let shouldLogFirstFrame = !hasLoggedFirstFrame
        hasLoggedFirstFrame = true
        frameLock.unlock()

        if shouldLogFirstFrame {
            previewLogger.info("First preview frame \(width, privacy: .public)x\(height, privacy: .public)")
        }

        let rendered = Self.applyFilters(to: source, settings: currentSettings)

        frameLock.lock()
        latestFrame = rendered
        frameLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.metalView.setNeedsDisplay(self.metalView.bounds)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay(view.bounds)
    }

    func draw(in view: MTKView) {
        frameLock.lock()
        let image = latestFrame
        frameLock.unlock()

        guard let image,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let ciContext else {
            return
        }

        let size = view.drawableSize
        guard size.width > 0, size.height > 0 else { return }

        let bounds = CGRect(origin: .zero, size: size)
        let fitted = Self.aspectFit(image, in: size)
        let background = CIImage(color: CIColor.black).cropped(to: bounds)
        let composed = fitted.composited(over: background)

        ciContext.render(
            composed,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static func aspectFit(_ image: CIImage, in size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let scale = min(size.width / extent.width, size.height / extent.height)
        let normalized = image.transformed(
            by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        )
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent
        let dx = (size.width - scaledExtent.width) / 2
        let dy = (size.height - scaledExtent.height) / 2

        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))
    }

    private static func applyFilters(to source: CIImage, settings: SoftwareSettings) -> CIImage {
        guard settings.enabled else { return source }

        var output = source

        if settings.mirror {
            let extent = output.extent
            output = output.transformed(
                by: CGAffineTransform(
                    a: -1,
                    b: 0,
                    c: 0,
                    d: 1,
                    tx: extent.minX + extent.maxX,
                    ty: 0
                )
            )
        }

        if settings.red != 1 || settings.green != 1 || settings.blue != 1 {
            if let filter = CIFilter(name: "CIColorMatrix") {
                filter.setValue(output, forKey: kCIInputImageKey)
                filter.setValue(CIVector(x: settings.red, y: 0, z: 0, w: 0), forKey: "inputRVector")
                filter.setValue(CIVector(x: 0, y: settings.green, z: 0, w: 0), forKey: "inputGVector")
                filter.setValue(CIVector(x: 0, y: 0, z: settings.blue, w: 0), forKey: "inputBVector")
                filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
                filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
                output = filter.outputImage ?? output
            }
        }

        if settings.brightness != 0 || settings.contrast != 1 || settings.saturation != 1 {
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(output, forKey: kCIInputImageKey)
                filter.setValue(settings.brightness, forKey: kCIInputBrightnessKey)
                filter.setValue(settings.contrast, forKey: kCIInputContrastKey)
                filter.setValue(settings.saturation, forKey: kCIInputSaturationKey)
                output = filter.outputImage ?? output
            }
        }

        if settings.gamma != 1 {
            if let filter = CIFilter(name: "CIGammaAdjust") {
                filter.setValue(output, forKey: kCIInputImageKey)
                filter.setValue(settings.gamma, forKey: "inputPower")
                output = filter.outputImage ?? output
            }
        }

        if settings.temperature != SoftwareSettings.defaultTemperature || settings.tint != 0 {
            if let filter = CIFilter(name: "CITemperatureAndTint") {
                filter.setValue(output, forKey: kCIInputImageKey)
                filter.setValue(
                    CIVector(x: SoftwareSettings.defaultTemperature, y: 0),
                    forKey: "inputNeutral"
                )
                filter.setValue(
                    CIVector(x: settings.temperature, y: settings.tint),
                    forKey: "inputTargetNeutral"
                )
                output = filter.outputImage ?? output
            }
        }

        return output.cropped(to: source.extent)
    }
}
