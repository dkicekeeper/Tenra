//
//  SiriWaveMetalView.swift
//  Tenra
//
//  MTKView renderer + UIViewRepresentable wrapper for the Aurora wave shader.
//

import SwiftUI
import MetalKit
import os

// MARK: - AudioLevelRef

/// Shared mutable amplitude state updated by the audio tap (main thread)
/// and read directly by the Metal renderer in draw(in:) — no SwiftUI cycle needed.
/// Uses os_unfair_lock for thread-safe access between main and render threads.
final class AudioLevelRef: @unchecked Sendable {
    private var _value: Float = 0.3
    // nonisolated(unsafe): lock accessed from both main thread and Metal render thread;
    // guarded by os_unfair_lock itself — no Swift concurrency protection needed.
    nonisolated(unsafe) private var lock = os_unfair_lock()

    /// Normalized mic amplitude 0–1. Thread-safe read/write.
    var value: Float {
        get {
            os_unfair_lock_lock(&lock)
            let v = _value
            os_unfair_lock_unlock(&lock)
            return v
        }
        set {
            os_unfair_lock_lock(&lock)
            _value = newValue
            os_unfair_lock_unlock(&lock)
        }
    }
}

// MARK: - WaveUniforms (layout must match SiriWaveShader.metal exactly)

private struct WaveUniforms {
    var time:      Float
    var amplitude: Float
    var resW:      Float
    var resH:      Float
    var cornerR:   Float  // device screen corner radius in pixels
}

// MARK: - Renderer

private final class SiriWaveRenderer: NSObject, MTKViewDelegate {

    // MARK: Metal state

    private let device:         MTLDevice
    private let commandQueue:   MTLCommandQueue
    private let pipeline:       MTLRenderPipelineState
    private let vertexBuffer:   MTLBuffer
    private let uniformsBuffer: MTLBuffer

    // MARK: Mutable state

    private let startTime: CFTimeInterval = CACurrentMediaTime()
    /// Holds the live amplitude; renderer reads `amplitudeRef.value` every frame.
    var amplitudeRef: AudioLevelRef = AudioLevelRef()

    // MARK: Init

    init?(device: MTLDevice) {
        self.device = device

        guard let queue = device.makeCommandQueue() else { return nil }
        commandQueue = queue

        // Full-screen quad as a triangle strip: BL, BR, TL, TR in NDC space
        let verts: [SIMD2<Float>] = [
            .init(-1, -1), .init(1, -1),
            .init(-1,  1), .init(1,  1)
        ]
        guard let vBuf = device.makeBuffer(
            bytes: verts,
            length: MemoryLayout<SIMD2<Float>>.stride * 4,
            options: .storageModeShared
        ) else { return nil }
        vertexBuffer = vBuf

        var empty = WaveUniforms(time: 0, amplitude: 0.3, resW: 1, resH: 1, cornerR: 47)
        guard let uBuf = device.makeBuffer(
            bytes: &empty,
            length: MemoryLayout<WaveUniforms>.stride,
            options: .storageModeShared
        ) else { return nil }
        uniformsBuffer = uBuf

        // Shader functions from the default Metal library (SiriWaveShader.metal)
        guard
            let lib    = device.makeDefaultLibrary(),
            let vertFn = lib.makeFunction(name: "waveVertex"),
            let fragFn = lib.makeFunction(name: "waveFragment")
        else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vertFn
        desc.fragmentFunction = fragFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Standard over-compositing so transparent background shows through
        let att = desc.colorAttachments[0]!
        att.isBlendingEnabled           = true
        att.sourceRGBBlendFactor        = .sourceAlpha
        att.destinationRGBBlendFactor   = .oneMinusSourceAlpha
        att.sourceAlphaBlendFactor      = .one
        att.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipe = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        pipeline = pipe

        super.init()
    }

    // MARK: MTKViewDelegate

    func draw(in view: MTKView) {
        guard
            let drawable   = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let cmdBuf     = commandQueue.makeCommandBuffer(),
            let encoder    = cmdBuf.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        // Transparent clear so SwiftUI background shows through
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        let sz = view.drawableSize
        let scale = Float(view.contentScaleFactor)
        var uni = WaveUniforms(
            time:      Float(CACurrentMediaTime() - startTime),
            amplitude: amplitudeRef.value,   // reads live value every frame — no SwiftUI lag
            resW:      Float(sz.width),
            resH:      Float(sz.height),
            cornerR:   47.0 * scale          // iPhone screen corner radius in pixels
        )
        memcpy(uniformsBuffer.contents(), &uni, MemoryLayout<WaveUniforms>.stride)

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer,     offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

// MARK: - UIViewRepresentable

/// Wraps an MTKView running the Aurora wave shader.
/// Pass an `AudioLevelRef` whose `.value` (0–1) the renderer reads every frame.
struct SiriWaveMetalView: UIViewRepresentable {

    /// Live amplitude reference — updated by audio tap, read by renderer at 60 fps.
    var amplitudeRef: AudioLevelRef
    var isPaused:     Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.backgroundColor          = .clear
        view.isOpaque                 = false
        view.colorPixelFormat         = .bgra8Unorm
        view.framebufferOnly          = false
        view.preferredFramesPerSecond = 60

        guard let device = MTLCreateSystemDefaultDevice() else { return view }
        view.device = device

        let renderer = SiriWaveRenderer(device: device)
        renderer?.amplitudeRef = amplitudeRef
        context.coordinator.renderer = renderer
        view.delegate = renderer
        view.isPaused = isPaused

        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        // Swap the ref if it changes (e.g. after VoiceInputService recreated)
        if let renderer = context.coordinator.renderer {
            renderer.amplitudeRef = amplitudeRef
        }
        view.isPaused = isPaused
    }

    final class Coordinator {
        fileprivate var renderer: SiriWaveRenderer?
    }
}
