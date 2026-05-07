import CoreImage

/// Per-pixel green-screen removal via a `CIColorKernel`.
///
/// The kernel uses "green excess" keying: how much greener a pixel is than its
/// red/blue channels. That's robust to varied lighting and slight tints in the
/// captured backdrop, and avoids the cost of a full HSV conversion.
///
/// Tunables can be adjusted live (mutating instance state); the underlying
/// kernel is compiled once and cached.
final class ChromaKeyKernel {

    static let shared = ChromaKeyKernel()

    /// How much greener than max(R,B) a pixel must be before we start keying.
    /// Raise if a tinted/yellowish character starts becoming transparent.
    var threshold: Float = 0.10

    /// Smoothing band around the threshold. Wider = softer edges, but more haze.
    var softness: Float = 0.18

    /// 0…1 — strength of green-spill suppression on partially keyed pixels.
    /// 1.0 fully clamps the green channel to max(R,B).
    var spill: Float = 1.0

    private let kernel: CIColorKernel?

    private init() {
        // CIKL source. CIColorKernel is per-pixel (no neighbourhood sampling)
        // which is all we need for a chroma key.
        let source = """
        kernel vec4 chromaKey(__sample s, float threshold, float softness, float spill) {
            vec3 rgb = s.rgb;
            float maxRB = max(rgb.r, rgb.b);
            float greenExcess = rgb.g - maxRB;
            float keyAmount = clamp((greenExcess - threshold) / max(softness, 0.0001), 0.0, 1.0);
            float alpha = 1.0 - keyAmount;
            float clampedG = min(rgb.g, maxRB);
            float g = mix(rgb.g, clampedG, spill * keyAmount);
            return vec4(rgb.r * alpha, g * alpha, rgb.b * alpha, alpha);
        }
        """
        kernel = CIColorKernel(source: source)
        if kernel == nil {
            fputs("ChromaKeyKernel: kernel compile failed\n", stderr)
        }
    }

    func apply(to image: CIImage) -> CIImage {
        guard let kernel else { return image }
        let args: [Any] = [image, threshold, softness, spill]
        return kernel.apply(extent: image.extent, arguments: args) ?? image
    }
}
