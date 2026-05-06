import SwiftUI
import AppKit
import AVFoundation
import CoreVideo

/// Per-scene MP4 video clips. Renders each scene at 30fps for its full
/// duration, then writes the frames to an H.264 .mp4 via AVAssetWriter.
///
/// This is the *dynamic* test artifact the user asked for. PNGs at 5 time
/// offsets miss everything that happens between frames; an MP4 lets the user
/// scrub in QuickTime and see the actual animation flow — vertex appearance
/// timing, edge fade transitions, the partition-cut break-open in Ch02.3, the
/// 10-step convergence collapse in Ch04.
@MainActor
enum SceneVideoCapture {

    /// Frames per second for the rendered video. 30 is a good compromise
    /// between scrub fidelity and capture time (60 doubled the runtime
    /// without adding obvious detail to the kind of motion CrisisViz uses).
    static let fps: Int32 = 30

    /// Default duration per scene in seconds. Mirrors the live app's
    /// auto-advance interval so each clip captures one nominal play-through.
    static let durationSeconds: Double = 8.0

    /// Per-scene-address duration overrides — clips for these scenes run
    /// longer so the scripted dramatization plays in full. Mirror this to
    /// `SceneEngine.durationOverrides` so live and capture stay in sync.
    static let durationOverrides: [SceneAddress: Double] = [
        SceneAddress(chapter: 1, scene: 3): 24.0   // Ch1.3 gossip script
    ]

    static func durationFor(_ address: SceneAddress) -> Double {
        durationOverrides[address] ?? durationSeconds
    }

    /// Render dimensions. Even values required by the H.264 encoder.
    static let renderSize = CGSize(width: 1400, height: 900)

    struct ClipResult {
        let chapter: Int
        let scene: Int
        let path: URL
        let framesWritten: Int
        let durationSeconds: Double
        let succeeded: Bool
        let errorDescription: String?
    }

    static func captureAll(dm: DataManager, outputDir: URL) async -> [ClipResult] {
        var results: [ClipResult] = []
        let videoDir = outputDir.appendingPathComponent("video_clips")
        try? FileManager.default.createDirectory(at: videoDir, withIntermediateDirectories: true)

        let engine = SceneEngine()
        for (ci, ch) in AllChapters.list.enumerated() {
            for si in 0..<ch.sceneCount {
                let address = SceneAddress(chapter: ci, scene: si)
                engine.goTo(global: address.globalIndex)
                let safe = chapterDirName(index: ci, title: ch.title)
                let url = videoDir.appendingPathComponent(
                    String(format: "%@_scene%02d.mp4", safe, si)
                )
                try? FileManager.default.removeItem(at: url)
                let result = await renderClip(
                    address: address, dm: dm, engine: engine, to: url
                )
                results.append(result)
                if !result.succeeded {
                    print("⚠ Video capture failed: ch\(ci).\(si) — \(result.errorDescription ?? "?")")
                }
            }
        }
        return results
    }

    private static func renderClip(
        address: SceneAddress, dm: DataManager, engine: SceneEngine, to url: URL
    ) async -> ClipResult {
        // Honor per-scene duration overrides — so the Ch1.3 gossip script
        // gets its full 24 seconds of footage and not a truncated 8s.
        let effectiveDuration = durationFor(address)
        let totalFrames = Int(effectiveDuration * Double(fps))
        let width = Int(renderSize.width)
        let height = Int(renderSize.height)

        // ─── AVAssetWriter setup ──────────────────────────────────────────
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            return ClipResult(chapter: address.chapter, scene: address.scene, path: url,
                              framesWritten: 0, durationSeconds: 0, succeeded: false,
                              errorDescription: "writer init failed: \(error)")
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoMaxKeyFrameIntervalKey: 30
            ] as [String: Any]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: bufferAttrs
        )
        guard writer.canAdd(input) else {
            return ClipResult(chapter: address.chapter, scene: address.scene, path: url,
                              framesWritten: 0, durationSeconds: 0, succeeded: false,
                              errorDescription: "cannot add input")
        }
        writer.add(input)

        guard writer.startWriting() else {
            return ClipResult(chapter: address.chapter, scene: address.scene, path: url,
                              framesWritten: 0, durationSeconds: 0, succeeded: false,
                              errorDescription: "startWriting failed: \(writer.error?.localizedDescription ?? "?")")
        }
        writer.startSession(atSourceTime: .zero)

        // ─── Frame loop ───────────────────────────────────────────────────
        let settings = AppSettings()
        var framesWritten = 0
        for frameIdx in 0..<totalFrames {
            let localTime = Double(frameIdx) / Double(fps)
            let view = SceneRouter(
                address: address, localTime: localTime,
                engine: engine, dm: dm
            )
            .environment(settings)
            .frame(width: renderSize.width, height: renderSize.height)
            .background(.black)

            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(
                width: renderSize.width, height: renderSize.height
            )
            renderer.scale = 1.0

            guard let cgImage = renderer.cgImage else { continue }
            guard let pixelBuffer = makePixelBuffer(from: cgImage,
                                                    width: width, height: height,
                                                    pool: adaptor.pixelBufferPool) else { continue }

            // Block briefly until input is ready, but don't deadlock: we cap
            // the wait by yielding the actor periodically.
            var waited = 0
            while !input.isReadyForMoreMediaData && waited < 200 {
                try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms
                waited += 1
            }
            let presentation = CMTime(value: Int64(frameIdx), timescale: fps)
            if adaptor.append(pixelBuffer, withPresentationTime: presentation) {
                framesWritten += 1
            }
        }

        input.markAsFinished()
        await writer.finishWriting()

        let succeeded = writer.status == .completed
        return ClipResult(
            chapter: address.chapter, scene: address.scene, path: url,
            framesWritten: framesWritten,
            durationSeconds: Double(framesWritten) / Double(fps),
            succeeded: succeeded,
            errorDescription: succeeded ? nil : "writer status=\(writer.status.rawValue) err=\(writer.error?.localizedDescription ?? "?")"
        )
    }

    private static func makePixelBuffer(
        from cgImage: CGImage, width: Int, height: Int,
        pool: CVPixelBufferPool?
    ) -> CVPixelBuffer? {
        var maybe: CVPixelBuffer?
        let status: CVReturn
        if let pool {
            status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybe)
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            status = CVPixelBufferCreate(
                nil, width, height, kCVPixelFormatType_32BGRA,
                attrs as CFDictionary, &maybe
            )
        }
        guard status == kCVReturnSuccess, let buffer = maybe else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let baseAddress = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private static func chapterDirName(index: Int, title: String) -> String {
        let safe = title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "—", with: "-")
            .prefix(25)
        return String(format: "ch%02d_%@", index, String(safe))
    }

    static func writeReport(_ results: [ClipResult], to url: URL) {
        var md = "# CrisisViz Per-Scene Video Clips\n\n"
        md += "Run at: \(Date())\n\n"
        let succeeded = results.filter(\.succeeded).count
        md += "**\(succeeded)/\(results.count) clips written successfully.**\n\n"
        md += "Each MP4 is \(durationSeconds)s at \(fps)fps, capturing one full play-through of the scene.\n"
        md += "Open in QuickTime / VLC and scrub to verify animation continuity, vertex appearance order, edge fade timing.\n\n"
        md += "## Clips\n\n"
        for r in results.sorted(by: { ($0.chapter, $0.scene) < ($1.chapter, $1.scene) }) {
            let mark = r.succeeded ? "✅" : "❌"
            md += "- \(mark) Ch\(r.chapter).\(r.scene) — \(r.framesWritten) frames"
            if r.succeeded {
                md += " — `\(r.path.lastPathComponent)`"
            } else {
                md += " — \(r.errorDescription ?? "?")"
            }
            md += "\n"
        }
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }
}
