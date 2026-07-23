public struct PerformanceSnapshot: Equatable, Sendable {
    public var fps: Double
    public var frameMilliseconds: Double
    public var activeParticles: Int
    public var fluidGridAxis: Int
    public var renderScale: Double
    public var gpuPassMilliseconds: [String: Double]?

    public init(
        fps: Double,
        frameMilliseconds: Double,
        activeParticles: Int,
        fluidGridAxis: Int,
        renderScale: Double,
        gpuPassMilliseconds: [String: Double]? = nil
    ) {
        self.fps = fps
        self.frameMilliseconds = frameMilliseconds
        self.activeParticles = activeParticles
        self.fluidGridAxis = fluidGridAxis
        self.renderScale = renderScale
        self.gpuPassMilliseconds = gpuPassMilliseconds
    }
}
