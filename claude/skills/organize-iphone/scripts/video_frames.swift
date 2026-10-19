// Extract JPEG frames from a screen recording: swift video_frames.swift <video> <out-dir> [seconds-between-frames]
import AVFoundation
import AppKit

let args = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let out = args[2]
let step = args.count > 3 ? Double(args[3])! : 0.75
let duration = CMTimeGetSeconds(asset.duration)
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero
gen.maximumSize = CGSize(width: 0, height: 1400)
var t = 0.0, i = 0
while t < duration {
    if let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil),
       let jpg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
        try! jpg.write(to: URL(fileURLWithPath: String(format: "%@/f%03d.jpg", out, i)))
        i += 1
    }
    t += step
}
print("\(i) frames from \(Int(duration))s of video")
