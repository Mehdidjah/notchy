import AppKit
import SwiftUI

/// The note editor: "< Notes" and "Done" on top, the title with six colour dots, a divider,
/// then the body with an optional picture and a character count in the corner.
struct NoteEditorPane: View {
    @ObservedObject var controller: NotesTabController
    @ObservedObject var settings: NotesSettings

    @FocusState private var isBodyFocused: Bool

    private var accent: Color { NoteItem.color(at: controller.colorIndex) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            titleRow
            Divider()
                .background(Color.white.opacity(0.1))
            bodyEditor
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onExitCommand { controller.back() }
        .task(id: controller.editingNoteID) {
            guard controller.isEditingNewNote else { return }
            controller.makeHostWindowKey()
            // Let the text view join the window before it takes focus.
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            isBodyFocused = true
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                controller.back()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                    Text("Notes")
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Notes")

            Spacer()

            Button {
                controller.done()
            } label: {
                Text("Done")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(11)
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 8.5) {
            TextField("Title", text: $controller.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .onSubmit { isBodyFocused = true }

            Spacer()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5.5) {
                    ForEach(NoteItem.palette.indices, id: \.self) { index in
                        Circle()
                            .fill(NoteItem.palette[index])
                            .frame(width: 11, height: 11)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: controller.colorIndex == index ? 2 : 0)
                                    .padding(-2)
                            )
                            .contentShape(Circle())
                            .onTapGesture {
                                withAnimation { controller.colorIndex = index }
                            }
                            .accessibilityElement()
                            .accessibilityLabel(NoteItem.paletteNames[index])
                            .accessibilityAddTraits(controller.colorIndex == index ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 3)
            }
            .frame(maxWidth: 112)
        }
        .padding(.leading, 11)
        .padding(.trailing, 3)
        .padding(.bottom, 5.5)
    }

    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            if controller.content.isEmpty {
                Text("Start typing...")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 7)
                    .padding(.leading, 8.5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $controller.content)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.white)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(5.5)
                .padding(.bottom, 14)
                .padding(.trailing, controller.image != nil ? 75 : 0)
                .focused($isBodyFocused)
                .frame(maxHeight: .infinity)
                .background(Color.white.opacity(0.05))

            if let image = controller.image {
                attachment(image)
            }

            if settings.showsCharacterCount {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(controller.content.count) chars")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(3)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(5.5)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func attachment(_ image: NSImage) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 38.5, height: 38.5)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 5, x: 0, y: 2)

                    Button {
                        withAnimation { controller.setImage(nil) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.9), .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .accessibilityLabel("Remove Picture")
                }
                .padding(8.5)
                .padding(.bottom, 14)
            }
        }
    }
}
