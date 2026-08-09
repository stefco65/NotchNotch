import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Form {
                panelSection
                appearanceSection
                displaysSection
                componentsSection
                shortcutButtonsSection
                applicationSection
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 640, minHeight: 680)
        .onAppear {
            store.refreshInstalledShortcuts()
        }
    }

    private var appearanceSection: some View {
        Section("Wygląd") {
            Toggle(
                "Tęczowa poświata schowanego notcha",
                isOn: Binding(
                    get: { store.rainbowGlowEnabled },
                    set: { store.setRainbowGlowEnabled($0) }
                )
            )

            Text("Poświata pojawia się podczas najechania na schowany notch i obejmuje wyłącznie jego boczne oraz dolną krawędź.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ustawienia NotchNook")
                    .font(.title2.weight(.semibold))
                Text("Dopasuj panel i jego komponenty")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    private var panelSection: some View {
        Section("Rozmiar otwartego notcha") {
            LabeledContent("Szerokość") {
                HStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { store.expandedWidth },
                            set: { newValue in
                                store.setExpandedWidth(newValue)
                            }
                        ),
                        in: store.requiredExpandedWidth...SettingsStore.maximumExpandedWidth,
                        step: 10
                    )
                    .frame(width: 280)
                    Text("\(Int(store.expandedWidth)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .trailing)
                }
            }

            Text("Minimalna szerokość rośnie automatycznie wraz z liczbą i rozmiarem komponentów. Na mniejszych ekranach panel jest ograniczany do dostępnego miejsca.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displaysSection: some View {
        Section("Ekrany") {
            Toggle(
                "Pokazuj notch również na ekranach zewnętrznych",
                isOn: Binding(
                    get: { store.showOnExternalDisplays },
                    set: { store.setShowOnExternalDisplays($0) }
                )
            )

            Text("Notch na głównym ekranie Maca jest zawsze aktywny. Po włączeniu tej opcji osobny notch pojawi się również u góry każdego podłączonego monitora.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var componentsSection: some View {
        Section("Komponenty i podział przestrzeni") {
            ForEach(Array(store.components.enumerated()), id: \.element.id) { index, component in
                componentRow(component, at: index)
            }

            HStack {
                Menu {
                    ForEach(store.availableComponents) { kind in
                        Button {
                            store.add(kind)
                        } label: {
                            Label(kind.title, systemImage: kind.iconName)
                        }
                    }
                } label: {
                    Label("Dodaj komponent", systemImage: "plus")
                }
                .disabled(store.availableComponents.isEmpty)

                Spacer()

                Text("Szerokość i kolejność komponentów można zmieniać wyłącznie tutaj.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func componentRow(
        _ component: PanelComponentConfiguration,
        at index: Int
    ) -> some View {
        HStack(spacing: 12) {
            Label(component.kind.title, systemImage: component.kind.iconName)
                .frame(width: 120, alignment: .leading)

            Slider(
                value: Binding(
                    get: { component.widthWeight },
                    set: { store.setWidthWeight(id: component.id, value: $0) }
                ),
                in: 0.5...3,
                step: 0.05
            )

            Text("\(component.widthWeight, specifier: "%.2f")×")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)

            Button {
                store.move(id: component.id, offset: -1)
            } label: {
                Image(systemName: "arrow.left")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .accessibilityLabel("Przesuń w lewo")

            Button {
                store.move(id: component.id, offset: 1)
            } label: {
                Image(systemName: "arrow.right")
            }
            .buttonStyle(.borderless)
            .disabled(index == store.components.count - 1)
            .accessibilityLabel("Przesuń w prawo")

            Button(role: .destructive) {
                store.remove(id: component.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(store.components.count == 1)
            .accessibilityLabel("Usuń komponent")
        }
    }

    private var shortcutButtonsSection: some View {
        Section("Przyciski z aplikacji Skróty") {
            if store.shortcutButtons.isEmpty {
                Text("Nie dodano jeszcze żadnego przycisku Skrótu.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.shortcutButtons.enumerated()), id: \.element.id) { index, button in
                    shortcutButtonRow(button, at: index)
                }
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach(store.availableShortcutNames, id: \.self) { shortcutName in
                        Button(shortcutName) {
                            store.addShortcutButton(named: shortcutName)
                        }
                    }
                } label: {
                    Label("Dodaj przycisk Skrótu", systemImage: "plus")
                }
                .disabled(store.availableShortcutNames.isEmpty || store.isLoadingShortcuts)

                Button {
                    store.refreshInstalledShortcuts()
                } label: {
                    if store.isLoadingShortcuts {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Odśwież listę", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isLoadingShortcuts)

                Spacer()
            }

            if !store.isLoadingShortcuts && store.installedShortcutNames.isEmpty {
                Text("Nie znaleziono skrótów. Utwórz je najpierw w aplikacji Skróty, a następnie odśwież listę.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Suwak określa względną wysokość przycisku. Strzałki zmieniają jego kolejność w pionowym komponencie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shortcutButtonRow(
        _ button: ShortcutButtonConfiguration,
        at index: Int
    ) -> some View {
        HStack(spacing: 12) {
            Label(button.shortcutName, systemImage: "bolt.fill")
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Slider(
                value: Binding(
                    get: { button.widthWeight },
                    set: { store.setShortcutButtonWidth(id: button.id, value: $0) }
                ),
                in: 0.6...3,
                step: 0.05
            )

            Text("\(button.widthWeight, specifier: "%.2f")×")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)

            Button {
                store.moveShortcutButton(id: button.id, offset: -1)
            } label: {
                Image(systemName: "arrow.left")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .accessibilityLabel("Przesuń przycisk w lewo")

            Button {
                store.moveShortcutButton(id: button.id, offset: 1)
            } label: {
                Image(systemName: "arrow.right")
            }
            .buttonStyle(.borderless)
            .disabled(index == store.shortcutButtons.count - 1)
            .accessibilityLabel("Przesuń przycisk w prawo")

            Button(role: .destructive) {
                store.removeShortcutButton(id: button.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Usuń przycisk Skrótu")
        }
    }

    private var applicationSection: some View {
        Section("Aplikacja") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Zakończ NotchNook")
                        .font(.body.weight(.medium))
                    Text("Zamyka wszystkie notche oraz okno ustawień.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Zakończ aplikację", systemImage: "power")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel("Zakończ aplikację NotchNook")
            }
        }
    }
}
