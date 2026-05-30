import Foundation
import AppKit
import CoreGraphics
import SwiftUI
import ClickInsightCore

struct RenderedHeatmap: Sendable {
    let cgImage: CGImage
    let width: Int
    let height: Int
}

enum HeatmapRenderer {
    static func render(
        points: [HeatPoint],
        screenWidth: Double,
        screenHeight: Double,
        bufferWidth: Int = 1440
    ) async -> RenderedHeatmap? {
        await Task.detached(priority: .userInitiated) {
            renderSync(
                points: points,
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                bufferWidth: bufferWidth
            )
        }.value
    }

    static func renderSync(
        points: [HeatPoint],
        screenWidth: Double,
        screenHeight: Double,
        bufferWidth: Int
    ) -> RenderedHeatmap? {
        guard screenWidth > 0, screenHeight > 0, !points.isEmpty else { return nil }

        let aspect = screenWidth / screenHeight
        let bufW = bufferWidth
        let bufH = max(1, Int((Double(bufW) / aspect).rounded()))

        var grid = [Float](repeating: 0, count: bufW * bufH)
        let sx = Double(bufW) / screenWidth
        let sy = Double(bufH) / screenHeight

        for p in points {
            let gx = Int(p.x * sx)
            let gy = Int(p.y * sy)
            guard gx >= 0, gx < bufW, gy >= 0, gy < bufH else { continue }
            grid[gy * bufW + gx] += Float(p.count)
        }

        // Separable Gaussian — sigma sized to a tight click cluster (~7 screen px).
        let sigma: Float = max(2.5, Float(Double(bufW) / screenWidth * 7))
        let radius = max(2, Int((sigma * 3).rounded(.up)))
        let twoSigSq = 2 * sigma * sigma
        var kernel = [Float](repeating: 0, count: 2 * radius + 1)
        var ksum: Float = 0
        for i in -radius...radius {
            let v = expf(-Float(i * i) / twoSigSq)
            kernel[i + radius] = v
            ksum += v
        }
        for i in 0..<kernel.count { kernel[i] /= ksum }

        var temp = [Float](repeating: 0, count: bufW * bufH)
        for y in 0..<bufH {
            let row = y * bufW
            for x in 0..<bufW {
                var acc: Float = 0
                let kStart = max(-radius, -x)
                let kEnd = min(radius, bufW - 1 - x)
                for k in kStart...kEnd {
                    acc += grid[row + x + k] * kernel[k + radius]
                }
                temp[row + x] = acc
            }
        }

        var blurred = [Float](repeating: 0, count: bufW * bufH)
        for x in 0..<bufW {
            for y in 0..<bufH {
                var acc: Float = 0
                let kStart = max(-radius, -y)
                let kEnd = min(radius, bufH - 1 - y)
                for k in kStart...kEnd {
                    acc += temp[(y + k) * bufW + x] * kernel[k + radius]
                }
                blurred[y * bufW + x] = acc
            }
        }

        // sqrt compression so single isolated clicks remain visible alongside dense clusters.
        var scaled = [Float](repeating: 0, count: blurred.count)
        for i in 0..<blurred.count {
            scaled[i] = sqrtf(max(0, blurred[i]))
        }
        let maxV = scaled.max() ?? 1
        guard maxV > 0 else { return nil }
        let invMax = 1.0 / Double(maxV)

        var pixels = [UInt8](repeating: 0, count: bufW * bufH * 4)
        for i in 0..<scaled.count {
            let t = Double(scaled[i]) * invMax
            let (r, g, b, a) = heatRGBA(t: t)
            let off = i * 4
            pixels[off] = r
            pixels[off + 1] = g
            pixels[off + 2] = b
            pixels[off + 3] = a
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cg = CGImage(
            width: bufW,
            height: bufH,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bufW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }

        return RenderedHeatmap(cgImage: cg, width: bufW, height: bufH)
    }

    // MARK: - Colormap

    private struct Stop {
        let t: Double
        let r: Double
        let g: Double
        let b: Double
    }

    private static let stops: [Stop] = [
        Stop(t: 0.00, r: 0.13, g: 0.30, b: 0.65),
        Stop(t: 0.25, r: 0.17, g: 0.62, b: 0.92),
        Stop(t: 0.50, r: 0.26, g: 0.88, b: 0.71),
        Stop(t: 0.70, r: 0.85, g: 0.95, b: 0.30),
        Stop(t: 0.85, r: 1.00, g: 0.74, b: 0.20),
        Stop(t: 1.00, r: 1.00, g: 0.30, b: 0.32)
    ]

    static func heatColor(_ t: Double) -> Color {
        let (r, g, b) = interpolateRGB(t: clamp(t))
        return Color(red: r, green: g, blue: b)
    }

    private static func heatRGBA(t: Double) -> (UInt8, UInt8, UInt8, UInt8) {
        let cutoff = 0.025
        if t < cutoff { return (0, 0, 0, 0) }
        let (r, g, b) = interpolateRGB(t: t)
        // Alpha ramps from 0.15 at cutoff to 1.0 at t ≈ 0.55, then stays.
        let alpha = min(1.0, max(0.0, (t - cutoff) / 0.5))
        let A = alpha
        return (
            UInt8(max(0, min(255, r * A * 255))),
            UInt8(max(0, min(255, g * A * 255))),
            UInt8(max(0, min(255, b * A * 255))),
            UInt8(max(0, min(255, A * 255)))
        )
    }

    private static func interpolateRGB(t: Double) -> (Double, Double, Double) {
        let tt = clamp(t)
        for i in 1..<stops.count {
            if tt <= stops[i].t {
                let lo = stops[i - 1], hi = stops[i]
                let f = (tt - lo.t) / (hi.t - lo.t)
                return (
                    lo.r + (hi.r - lo.r) * f,
                    lo.g + (hi.g - lo.g) * f,
                    lo.b + (hi.b - lo.b) * f
                )
            }
        }
        let s = stops.last!
        return (s.r, s.g, s.b)
    }

    private static func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
}
