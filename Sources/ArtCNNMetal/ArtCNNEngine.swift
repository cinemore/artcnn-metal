import Metal

/// 固定已验证的C4F16，FP32 direct卷积；内部特征不交付消费者。
public final class ArtCNNEngine {
    private let device: any MTLDevice
    private let layers: [any MTLComputePipelineState]
    private let luma: any MTLComputePipelineState
    private let color: any MTLComputePipelineState
    private struct Workspace {
        let y: any MTLTexture
        let skip: any MTLTexture
        let a: any MTLTexture
        let b: any MTLTexture
    }

    private var workspace: Workspace?

    public init(device: any MTLDevice) throws {
        let library = try device.makeDefaultLibrary(bundle: Bundle.module)
        self.device = device
        func pipeline(_ name: String) throws -> any MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else {
                throw ArtCNNError.unavailable(name)
            }
            return try device.makeComputePipelineState(function: function)
        }
        layers = try (0 ..< 7).map { try pipeline("artLayer\($0)") }
        luma = try pipeline("artLuma")
        color = try pipeline("artShuffleColor")
    }

    /// 便捷入口拥有encoder，调用方负责提交并等待GPU完成后再复用本实例。
    public func encode(
        command: any MTLCommandBuffer, input: any MTLTexture, output: any MTLTexture,
        coefficients: SIMD4<Float> = SIMD4(0.2126, 0.7152, 0.0722, 0), outputOriginX: Int = 0
    ) throws {
        guard command.device.registryID == device.registryID,
              let encoder = command.makeComputeCommandEncoder(dispatchType: .serial) else {
            throw ArtCNNError.unavailable("ArtCNN encoder")
        }
        defer { encoder.endEncoding() }
        try encode(encoder: encoder, input: input, output: output, coefficients: coefficients, outputOriginX: outputOriginX)
    }

    /// 调用方提供串行encoder并负责结束；可继续编码同一输出的分屏原画侧。
    /// 单实例须串行使用，直到GPU完成才能复用尺寸工作区。
    public func encode(
        encoder: any MTLComputeCommandEncoder, input: any MTLTexture, output: any MTLTexture,
        coefficients: SIMD4<Float> = SIMD4(0.2126, 0.7152, 0.0722, 0), outputOriginX: Int = 0
    ) throws {
        guard input !== output, output.width == input.width * 2, output.height == input.height * 2,
              input.textureType == .type2D, output.textureType == .type2D,
              input.device.registryID == device.registryID, output.device.registryID == device.registryID,
              (0...output.width).contains(outputOriginX),
              coefficients.x.isFinite, coefficients.y.isFinite, coefficients.z.isFinite
        else { throw ArtCNNError.invalidInput("Expected native 2x textures on the engine device and a valid output region") }
        let work = try prepare(width: input.width, height: input.height)
        // 串行dispatch保证卷积依赖，整帧复用一个encoder，避免逐层创建和结束。
        pass(luma, encoder: encoder, textures: [input, work.y], target: work.y, coefficients: coefficients)
        let pairs = [
            (work.y, work.skip),
            (work.skip, work.a),
            (work.a, work.b),
            (work.b, work.a),
            (work.a, work.b),
            (work.b, work.a),
            (work.a, work.b)
        ]
        for (index, pair) in pairs.enumerated() {
            pass(layers[index], encoder: encoder, textures: [pair.0, pair.1, work.skip], target: pair.1)
        }
        var originX = UInt32(outputOriginX)
        if Int(originX) < output.width {
            encoder.setComputePipelineState(color)
            encoder.setTexture(input, index: 0)
            encoder.setTexture(work.b, index: 1)
            encoder.setTexture(output, index: 2)
            var coefficients = coefficients
            encoder.setBytes(&coefficients, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setBytes(&originX, length: MemoryLayout<UInt32>.stride, index: 1)
            encoder.dispatchThreads(MTLSize(width: output.width - Int(originX), height: output.height, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        }
    }

    private func prepare(width: Int, height: Int) throws -> Workspace {
        if let workspace, workspace.y.width == width, workspace.y.height == height {
            return workspace
        }
        func texture(groups: Int, format: MTLPixelFormat) throws -> any MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            descriptor.textureType = .type2DArray; descriptor.arrayLength = groups
            descriptor.storageMode = .private; descriptor.usage = [.shaderRead, .shaderWrite]
            guard let result = device.makeTexture(descriptor: descriptor) else {
                throw ArtCNNError.unavailable("ArtCNN workspace")
            }
            return result
        }
        let result = try Workspace(y: texture(groups: 1, format: .r32Float),
                                   skip: texture(groups: 4, format: .rgba32Float), a: texture(groups: 4, format: .rgba32Float),
                                   b: texture(groups: 4, format: .rgba32Float))
        workspace = result
        return result
    }

    private func pass(
        _ pipeline: any MTLComputePipelineState,
        encoder: any MTLComputeCommandEncoder,
        textures: [any MTLTexture],
        target: any MTLTexture,
        coefficients: SIMD4<Float>? = nil
    ) {
        encoder.setComputePipelineState(pipeline)
        for (index, texture) in textures.enumerated() {
            encoder.setTexture(texture, index: index)
        }
        if var coefficients {
            encoder.setBytes(&coefficients, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        }
        encoder.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }
}
