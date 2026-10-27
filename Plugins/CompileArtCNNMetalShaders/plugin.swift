import Foundation
import PackagePlugin

@main
struct CompileArtCNNMetalShaders: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard target is SourceModuleTarget else { return [] }
        let shader = target.directory.appending("Shaders/ArtCNNKernels.generated.metal")
        let air = context.pluginWorkDirectory.appending("ArtCNN.air")
        let library = context.pluginWorkDirectory.appending("default.metallib")
        let cache = context.pluginWorkDirectory.appending("MetalModuleCache")
        return [
            .buildCommand(displayName: "Compile ArtCNN Metal kernels", executable: Path("/usr/bin/xcrun"),
                arguments: ["metal", "-c", "-ffast-math", "-ffp-contract=fast", "-fmodules-cache-path=\(cache.string)", shader.string, "-o", air.string],
                inputFiles: [shader], outputFiles: [air]),
            .buildCommand(displayName: "Link ArtCNN default.metallib", executable: Path("/usr/bin/xcrun"),
                arguments: ["metallib", air.string, "-o", library.string], inputFiles: [air], outputFiles: [library])
        ]
    }
}
