import SwiftUI

struct TaskComponentView: View {
    @ObservedObject var store: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var newTaskTitle = ""
    @State private var editingTaskID: UUID?
    @State private var editingTitle = ""
    @FocusState private var focusedEditingTaskID: UUID?

    var body: some View {
        VStack(spacing: 6) {
            addTaskField

            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(store.items) { item in
                            taskRow(item)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .move(edge: .trailing).combined(with: .opacity)
                                    )
                                )
                        }
                    }
                }
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
        .animation(listAnimation, value: store.items)
    }

    private var addTaskField: some View {
        HStack(spacing: 5) {
            TextField("Dodaj zadanie…", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .onSubmit(addTask)

            Button(action: addTask) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 19, height: 19)
                    .background(Color.purple.opacity(0.72), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Dodaj zadanie")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 27)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))
    }

    private var emptyState: some View {
        Text("Brak zadań")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.36))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func taskRow(_ item: NookTask) -> some View {
        if editingTaskID == item.id {
            editRow(item)
        } else {
            Button {
                withAnimation(listAnimation) {
                    store.complete(id: item.id)
                }
            } label: {
                HStack(spacing: 7) {
                    completionCircle(isCompleted: item.isCompleted)

                    Text(item.title)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(item.isCompleted ? 0.32 : 0.82))
                        .strikethrough(item.isCompleted, color: .white.opacity(0.35))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .background(.white.opacity(item.isCompleted ? 0.025 : 0.045), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.isCompleted)
            .contextMenu {
                Button("Edytuj", systemImage: "pencil") {
                    beginEditing(item)
                }

                Divider()

                Button("Usuń", systemImage: "trash", role: .destructive) {
                    withAnimation(listAnimation) {
                        store.delete(id: item.id)
                    }
                }
            }
            .accessibilityLabel("Oznacz jako wykonane: \(item.title)")
        }
    }

    private func editRow(_ item: NookTask) -> some View {
        HStack(spacing: 4) {
            TextField("Zadanie", text: $editingTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white)
                .focused($focusedEditingTaskID, equals: item.id)
                .onSubmit { saveEditing(item) }
                .onExitCommand(perform: cancelEditing)

            Button {
                saveEditing(item)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(editingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(action: cancelEditing) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 22)
        .background(Color.purple.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
    }

    private func completionCircle(isCompleted: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(isCompleted ? 0 : 0.48), lineWidth: 1.2)
                .background(
                    Circle()
                        .fill(isCompleted ? Color.purple : .clear)
                )

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 13, height: 13)
    }

    private var listAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.28)
    }

    private func addTask() {
        guard store.add(title: newTaskTitle) != nil else { return }
        newTaskTitle = ""
    }

    private func beginEditing(_ item: NookTask) {
        editingTaskID = item.id
        editingTitle = item.title
        DispatchQueue.main.async {
            focusedEditingTaskID = item.id
        }
    }

    private func saveEditing(_ item: NookTask) {
        let normalized = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        store.update(id: item.id, title: normalized)
        cancelEditing()
    }

    private func cancelEditing() {
        focusedEditingTaskID = nil
        editingTaskID = nil
        editingTitle = ""
    }
}
