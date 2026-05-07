import SwiftUI

/// First-launch picker shown in a real (titled) NSWindow. Each card auto-plays
/// the character's idle video so the user sees what they're choosing. Click a
/// card → `onSelect` fires with the character ID and the host window dismisses.
struct CharacterPickerView: View {

    let library: [CharacterAssets]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Choose your study companion")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Pick a character to start with — you can switch any time from the right-click menu.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(library) { character in
                        CharacterPickerCard(character: character) {
                            onSelect(character.id)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(24)
        .frame(minWidth: 520, idealWidth: 640, minHeight: 260)
    }
}

private struct CharacterPickerCard: View {

    let character: CharacterAssets
    let onTap: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(hovered ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.10))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(hovered ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: hovered ? 2 : 1)
                    ChromaKeyVideoView(videoURL: character.idleURL, rate: 0.9)
                        .frame(width: 124, height: 124)
                }
                .frame(width: 144, height: 144)
                Text(character.displayName)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .scaleEffect(hovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
