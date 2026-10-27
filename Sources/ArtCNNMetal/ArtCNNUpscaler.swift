import CoreVideo
import Foundation
import Metal

/// 同步入口在内部串行处理并等待GPU完成，每次返回独立的输出缓冲。
public final class ArtCNNUpscaler: @unchecked Sendable {
    private let lock = NSLock()
    private let context: PixelBufferContext
    private let engine: ArtCNNEngine
    public init(device: (any MTLDevice)? = nil) throws {
        context = try PixelBufferContext(device: device)
        engine = try ArtCNNEngine(device: context.device)
    }

    public func enhance(pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        try lock.withLock {
            let coefficients = try Self.coefficients(pixelBuffer)
            return try context.process(pixelBuffer, width: CVPixelBufferGetWidth(pixelBuffer) * 2,
                                       height: CVPixelBufferGetHeight(pixelBuffer) * 2) { command, input, output in
                try engine.encode(command: command, input: input, output: output, coefficients: coefficients)
            }
        }
    }

    /// 固定模型按源矩阵恢复颜色；未知视频矩阵拒绝处理。
    public static func coefficients(_ source: CVPixelBuffer) throws -> SIMD4<Float> {
        let matrix = CVBufferCopyAttachment(source, kCVImageBufferYCbCrMatrixKey, nil) as? String
        if matrix == kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String { return SIMD4(0.299, 0.587, 0.114, 0) }
        if matrix == kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String { return SIMD4(0.2126, 0.7152, 0.0722, 0) }
        if matrix == nil, CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA,
           CVBufferCopyAttachment(source, kCVImageBufferColorPrimariesKey, nil) as? String == kCVImageBufferColorPrimaries_ITU_R_709_2 as String {
            return SIMD4(0.2126, 0.7152, 0.0722, 0)
        }
        throw ArtCNNError.invalidInput("Unknown or unsupported ArtCNN matrix")
    }
}
