import AVFoundation
import CoreImage

enum ChromaKeyComposer {

    /// Builds an `AVVideoComposition` that pipes every video frame of `asset`
    /// through `ChromaKeyKernel`, producing RGBA output where the green
    /// backdrop has been keyed to alpha 0.
    static func videoComposition(for asset: AVAsset) -> AVVideoComposition {
        AVMutableVideoComposition(asset: asset) { request in
            let output = ChromaKeyKernel.shared.apply(to: request.sourceImage)
            request.finish(with: output, context: nil)
        }
    }
}
