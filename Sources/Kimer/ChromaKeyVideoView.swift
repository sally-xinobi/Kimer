import SwiftUI
import AVFoundation

struct ChromaKeyVideoView: NSViewRepresentable {

    let videoURL: URL
    let rate: Double

    func makeNSView(context: Context) -> NSView {
        let view = ChromaKeyHostView(frame: .zero)
        view.load(url: videoURL)
        view.setRate(rate)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let host = nsView as? ChromaKeyHostView else { return }
        host.load(url: videoURL)
        host.setRate(rate)
    }
}

/// `AVPlayerLayer`-backed host view. Loops the source video and exposes a
/// playback `rate`. The chroma-key filter chain is wired into the player item
/// so each rendered frame is alpha-keyed before it lands on the layer.
final class ChromaKeyHostView: NSView {

    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var currentURL: URL?
    private var currentRate: Float = 1.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false

        // aspectFit so wide-aspect source video doesn't crop the character.
        // The green letterbox area gets keyed to alpha 0 anyway, so it looks
        // identical to the transparent space outside the video.
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.isOpaque = false
        layer?.addSublayer(playerLayer)
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func load(url: URL) {
        if currentURL == url, player != nil { return }
        currentURL = url
        teardownObserver()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = ChromaKeyComposer.videoComposition(for: asset)

        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        p.actionAtItemEnd = .none
        p.allowsExternalPlayback = false
        p.automaticallyWaitsToMinimizeStalling = false

        playerLayer.player = p
        player = p

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, let p = self.player else { return }
            p.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                p.rate = self.currentRate
            }
        }

        // setting rate > 0 also starts playback
        p.rate = currentRate
    }

    func setRate(_ rate: Double) {
        currentRate = max(0.1, Float(rate))
        if let player {
            player.rate = currentRate
        }
    }

    private func teardownObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    deinit {
        teardownObserver()
    }
}
