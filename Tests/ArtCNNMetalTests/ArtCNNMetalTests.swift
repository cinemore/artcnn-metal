@testable import ArtCNNMetal
import CoreGraphics
import CoreVideo
import Metal
import XCTest

final class ArtCNNMetalTests: XCTestCase {
    private func input(width: Int = 16, height: Int = 12) throws -> CVPixelBuffer {
        let buffer = try PixelBufferContext.buffer(width: width, height: height)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        for y in 0..<height {
            let row = address.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                row[x * 4] = UInt8((x * 13 + y * 7) % 256)
                row[x * 4 + 1] = 96
                row[x * 4 + 2] = 180
                row[x * 4 + 3] = 255
            }
        }
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        return buffer
    }

    private func bytes(_ buffer: CVPixelBuffer) throws -> [UInt8] {
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, .readOnly), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        return (0..<CVPixelBufferGetHeight(buffer)).flatMap { y in
            Array(UnsafeBufferPointer(start: address.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self),
                                      count: CVPixelBufferGetWidth(buffer) * 4))
        }
    }

    func testBundledKernelsPreserveSourceAndRetainedOutputs() throws {
        let source = try input()
        let before = try bytes(source)
        let upscaler = try ArtCNNUpscaler()
        let first = try upscaler.enhance(pixelBuffer: source)
        let frozen = try bytes(first)
        let second = try upscaler.enhance(pixelBuffer: source)
        XCTAssertFalse(first === second)
        XCTAssertEqual(CVPixelBufferGetWidth(first), 32)
        XCTAssertEqual(CVPixelBufferGetHeight(first), 24)
        XCTAssertEqual(try bytes(source), before)
        XCTAssertEqual(try bytes(first), frozen)
        XCTAssertEqual(try bytes(second), frozen)
        XCTAssertEqual(stride(from: 3, to: frozen.count, by: 4).map { frozen[$0] }, [UInt8](repeating: 255, count: 32 * 24))
    }

    func testRejectsHDRWithoutTouchingInput() throws {
        let source = try input()
        let before = try bytes(source)
        CVBufferSetAttachment(source, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ, .shouldPropagate)
        let upscaler = try ArtCNNUpscaler()
        XCTAssertThrowsError(try upscaler.enhance(pixelBuffer: source))
        XCTAssertEqual(try bytes(source), before)
    }

    func testDisplayApertureScalesWithOutput() throws {
        let source = try input()
        let aperture = [kCVImageBufferCleanApertureWidthKey as String: 14.0, kCVImageBufferCleanApertureHeightKey as String: 10.0,
                        kCVImageBufferCleanApertureHorizontalOffsetKey as String: 0.5, kCVImageBufferCleanApertureVerticalOffsetKey as String: 0.25]
        CVBufferSetAttachment(source, kCVImageBufferCleanApertureKey, aperture as CFDictionary, .shouldPropagate)
        let output = try ArtCNNUpscaler().enhance(pixelBuffer: source)
        let actual = try XCTUnwrap(CVBufferCopyAttachment(output, kCVImageBufferCleanApertureKey, nil) as? [String: Double])
        XCTAssertEqual(actual[kCVImageBufferCleanApertureWidthKey as String], 28)
        XCTAssertEqual(actual[kCVImageBufferCleanApertureHorizontalOffsetKey as String], 1)
        XCTAssertNil(CVBufferCopyAttachment(output, kCVImageBufferYCbCrMatrixKey, nil))
    }

    func testVideoToolboxNV12InputPreservesColorMetadata() throws {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                                       kCVPixelBufferMetalCompatibilityKey as String: true]
        XCTAssertEqual(CVPixelBufferCreate(nil, 16, 12, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                          attributes as CFDictionary, &buffer), kCVReturnSuccess)
        let source = try XCTUnwrap(buffer)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(source, []), kCVReturnSuccess)
        for plane in 0..<CVPixelBufferGetPlaneCount(source) {
            let address = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(source, plane))
            address.initializeMemory(as: UInt8.self, repeating: plane == 0 ? 96 : 128,
                count: CVPixelBufferGetBytesPerRowOfPlane(source, plane) * CVPixelBufferGetHeightOfPlane(source, plane))
        }
        CVPixelBufferUnlockBaseAddress(source, [])
        CVBufferSetAttachment(source, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(source, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(source, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        let output = try ArtCNNUpscaler().enhance(pixelBuffer: source)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(output), kCVPixelFormatType_32BGRA)
        XCTAssertEqual(CVPixelBufferGetWidth(output), 32)
        XCTAssertEqual(CVPixelBufferGetHeight(output), 24)
        XCTAssertEqual(CVBufferCopyAttachment(output, kCVImageBufferColorPrimariesKey, nil) as? String,
                       kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
        XCTAssertEqual(CVBufferCopyAttachment(output, kCVImageBufferTransferFunctionKey, nil) as? String,
                       kCVImageBufferTransferFunction_ITU_R_709_2 as String)
        XCTAssertNil(CVBufferCopyAttachment(output, kCVImageBufferYCbCrMatrixKey, nil))
        XCTAssertTrue(try bytes(output).contains { $0 > 0 && $0 < 255 })
    }

    func testCGImageEntryPoint() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 32,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let enhanced = try ArtCNNUpscaler().enhance(image: image)
        XCTAssertEqual(enhanced.width, 16)
        XCTAssertEqual(enhanced.height, 12)
    }

    func testMatrixSelectionAndUnknownMatrixRejection() throws {
        let source = try input()
        XCTAssertEqual(try ArtCNNUpscaler.coefficients(source), SIMD4(0.2126, 0.7152, 0.0722, 0))
        CVBufferSetAttachment(source, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, .shouldPropagate)
        XCTAssertEqual(try ArtCNNUpscaler.coefficients(source), SIMD4(0.299, 0.587, 0.114, 0))
        CVBufferSetAttachment(source, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
        XCTAssertEqual(CVBufferCopyAttachment(source, kCVImageBufferYCbCrMatrixKey, nil) as? String,
                       kCVImageBufferYCbCrMatrix_ITU_R_2020 as String)
        XCTAssertThrowsError(try ArtCNNUpscaler().enhance(pixelBuffer: source))
    }

    func testCallerEncoderAndOutputRegionMatchFullInference() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        func texture(_ width: Int, _ height: Int) throws -> any MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead, .shaderWrite]
            return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        }
        let source = try texture(8, 6), full = try texture(16, 12), partial = try texture(16, 12)
        let values = [UInt8](repeating: 96, count: 8 * 6 * 4)
        values.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 8, 6), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 32) }
        let sentinel = [UInt8](repeating: 37, count: 16 * 12 * 4)
        sentinel.withUnsafeBytes { partial.replace(region: MTLRegionMake2D(0, 0, 16, 12), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 64) }
        let engine = try ArtCNNEngine(device: device)
        let first = try XCTUnwrap(queue.makeCommandBuffer())
        try engine.encode(command: first, input: source, output: full)
        first.commit(); first.waitUntilCompleted()
        XCTAssertEqual(first.status, .completed)
        let second = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(second.makeComputeCommandEncoder(dispatchType: .serial))
        try engine.encode(encoder: encoder, input: source, output: partial, outputOriginX: 8)
        encoder.endEncoding()
        second.commit(); second.waitUntilCompleted()
        XCTAssertEqual(second.status, .completed)
        var a = sentinel, b = sentinel
        a.withUnsafeMutableBytes { full.getBytes($0.baseAddress!, bytesPerRow: 64, from: MTLRegionMake2D(0, 0, 16, 12), mipmapLevel: 0) }
        b.withUnsafeMutableBytes { partial.getBytes($0.baseAddress!, bytesPerRow: 64, from: MTLRegionMake2D(0, 0, 16, 12), mipmapLevel: 0) }
        for y in 0..<12 {
            XCTAssertEqual(Array(b[(y * 64)..<(y * 64 + 32)]), [UInt8](repeating: 37, count: 32))
            XCTAssertEqual(Array(b[(y * 64 + 32)..<(y * 64 + 64)]), Array(a[(y * 64 + 32)..<(y * 64 + 64)]))
        }
    }
}
