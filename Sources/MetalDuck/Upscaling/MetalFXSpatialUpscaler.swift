import Foundation
import Metal
import MetalFX

enum MetalFXSpatialUpscalerError: Error {
    case unsupportedDevice
    case scalerCreationFailed
}

final class MetalFXSpatialUpscaler {
    private let device: MTLDevice
    private var scaler: MTLFXSpatialScaler?
    private var cachedInputSize = MTLSizeMake(0, 0, 1)
    private var cachedOutputSize = MTLSizeMake(0, 0, 1)
    private var cachedInputFormat: MTLPixelFormat = .invalid
    private var cachedOutputFormat: MTLPixelFormat = .invalid

    init(device: MTLDevice) {
        self.device = device
    }

    var isSupported: Bool {
        MTLFXSpatialScalerDescriptor.supportsDevice(device)
    }

    func encode(
        commandBuffer: MTLCommandBuffer,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture
    ) throws {
        guard isSupported else {
            throw MetalFXSpatialUpscalerError.unsupportedDevice
        }

        try ensureScaler(
            inputWidth: inputTexture.width,
            inputHeight: inputTexture.height,
            inputFormat: inputTexture.pixelFormat,
            outputWidth: outputTexture.width,
            outputHeight: outputTexture.height,
            outputFormat: outputTexture.pixelFormat
        )

        guard let scaler else {
            throw MetalFXSpatialUpscalerError.scalerCreationFailed
        }

        scaler.colorTexture = inputTexture
        scaler.outputTexture = outputTexture
        scaler.inputContentWidth = inputTexture.width
        scaler.inputContentHeight = inputTexture.height
        scaler.encode(commandBuffer: commandBuffer)
    }

    private func ensureScaler(
        inputWidth: Int,
        inputHeight: Int,
        inputFormat: MTLPixelFormat,
        outputWidth: Int,
        outputHeight: Int,
        outputFormat: MTLPixelFormat
    ) throws {
        let inputSize = MTLSizeMake(inputWidth, inputHeight, 1)
        let outputSize = MTLSizeMake(outputWidth, outputHeight, 1)

        let cachedMatches =
            inputSize.width == cachedInputSize.width &&
            inputSize.height == cachedInputSize.height &&
            outputSize.width == cachedOutputSize.width &&
            outputSize.height == cachedOutputSize.height &&
            cachedInputFormat == inputFormat &&
            cachedOutputFormat == outputFormat

        if scaler != nil && cachedMatches {
            return
        }

        let descriptor = MTLFXSpatialScalerDescriptor()
        descriptor.inputWidth = inputWidth
        descriptor.inputHeight = inputHeight
        descriptor.outputWidth = outputWidth
        descriptor.outputHeight = outputHeight
        descriptor.colorTextureFormat = inputFormat
        descriptor.outputTextureFormat = outputFormat
        // Screen capture content is already perceptual encoded (sRGB-like).
        descriptor.colorProcessingMode = .perceptual

        guard let scaler = descriptor.makeSpatialScaler(device: device) else {
            throw MetalFXSpatialUpscalerError.scalerCreationFailed
        }

        self.scaler = scaler
        self.cachedInputSize = inputSize
        self.cachedOutputSize = outputSize
        self.cachedInputFormat = inputFormat
        self.cachedOutputFormat = outputFormat
    }
}
