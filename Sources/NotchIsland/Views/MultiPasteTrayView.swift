import SwiftUI

struct MultiPasteTrayView: View {
    @ObservedObject var model: NotchViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Label("\(model.selectedClips.count) selected", systemImage: "square.stack.3d.up.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(model.selectedClips.enumerated()), id: \.element.id) { index, clip in
                            trayItem(clip, index: index)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                Button("Clear") { model.clearSelection() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 8) {
                Picker("Separator", selection: $model.multiPasteSeparator) {
                    ForEach(MultiPasteSeparator.allCases) { separator in
                        Text(separator.displayName).tag(separator)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                Picker("Output", selection: $model.multiPasteOutputFormat) {
                    ForEach(MultiPasteOutputFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 112)

                if model.multiPasteSeparator == .custom {
                    TextField("Custom separator", text: $model.customSeparator)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(width: 130, height: 28)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                Button {
                    model.startQueueMode()
                } label: {
                    Label("Queue", systemImage: "arrow.down.to.line.compact")
                }
                .buttonStyle(TrayButtonStyle(isPrimary: false))

                Button {
                    model.pasteSelectedCombined()
                } label: {
                    Label("Paste combined", systemImage: "arrow.down.doc.fill")
                }
                .buttonStyle(TrayButtonStyle(isPrimary: true))
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.055))
        .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.08)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Multi-Paste Tray")
    }

    private func trayItem(_ clip: Clip, index: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .frame(width: 18, height: 18)
                .background(.white.opacity(0.13), in: Circle())
            Text(clip.title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 94, alignment: .leading)
            Button {
                model.removeFromSelection(clip)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .frame(height: 28)
        .foregroundStyle(.white.opacity(0.75))
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .draggable(clip.id.uuidString)
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first, let draggedID = UUID(uuidString: value) else { return false }
            model.moveSelection(draggedID, before: clip.id)
            return true
        }
    }
}

private struct TrayButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(isPrimary ? .black : .white.opacity(0.78))
            .background(
                isPrimary ? Color.white : Color.white.opacity(configuration.isPressed ? 0.16 : 0.09),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
