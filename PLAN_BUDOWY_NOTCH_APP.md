# PLAN_BUDOWY_NOTCH_APP.md

> **Cel dokumentu:** dostarczyć agentowi implementacyjnemu kompletnego, kolejnego planu budowy natywnej aplikacji macOS inspirowanej koncepcją NotchNook.
>
> **Tryb pracy:** agent ma realizować plan fazami. Nie wolno przechodzić do następnej fazy, dopóki kryteria akceptacji bieżącej fazy nie są spełnione lub problem nie został jawnie oznaczony jako `BLOCKED` wraz z opisem przyczyny i obejściem.
>
> **Priorytet produktu:** jakość zachowania notcha, window management, animacje, drag-and-drop, focus, Spaces/fullscreen i wielomonitorowość są ważniejsze niż liczba widgetów.

---

# 0. Produkt, który budujemy

Aplikacja jest natywnym utility dla macOS, które wykorzystuje fizyczny notch MacBooka — albo wirtualny handler na ekranach bez wycięcia — jako stały, kontekstowy punkt wejścia do małego panelu systemowego.

W stanie spoczynku aplikacja ma sprawiać wrażenie części sprzętowego notcha. Po interakcji czarna powierzchnia ma płynnie rozszerzać się w dół i na boki, odsłaniając:

1. **Nook** — zestaw widgetów.
2. **Tray** — tymczasową półkę na pliki.
3. **Drop Mode** — kontekstowe strefy drop podczas przeciągania pliku.
4. **Live Activities** — kompaktowe informacje widoczne bez otwierania całego Nooka.

Docelowe widgety:

- Media Player,
- Calendar,
- Shortcuts,
- Mirror / Camera Preview.

Docelowe akcje Tray:

- przechowanie pliku,
- ponowne przeciągnięcie pliku do dowolnej aplikacji,
- usunięcie z Tray,
- czyszczenie całego Tray,
- AirDrop.

Aplikacja ma być niewidoczna w Docku podczas normalnego używania i działać jak narzędzie systemowe działające w tle.

---

# 1. Główne założenia techniczne

## 1.1. Platforma

Przyjąć:

- platforma: **macOS**,
- język: **Swift 6**,
- UI: **SwiftUI + AppKit**,
- minimalny system dla MVP: **macOS 14.6**,
- preferowana architektura concurrency: `async/await`, `actor`, `@MainActor`,
- trwałe ustawienia: `UserDefaults` / `AppStorage`,
- trwałe dane Tray: katalog aplikacji w `Caches` lub `Application Support`,
- testy: XCTest / Swift Testing zależnie od konfiguracji projektu.

Nie budować aplikacji jako czystego SwiftUI. Główna nakładka wymaga świadomego zarządzania `NSPanel`, focus, poziomem okna, Spaces, ekranami i drag-and-drop.

## 1.2. Warstwa AppKit odpowiada za

- `NSPanel` / `NSWindow`,
- pozycjonowanie overlay,
- wykrywanie ekranów `NSScreen`,
- obliczanie fizycznego notcha,
- zachowanie w Spaces,
- zachowanie w fullscreen,
- hit-testing,
- event monitoring,
- drag-and-drop,
- rozpoczęcie drag z Tray,
- integrację AirDrop,
- lifecycle aplikacji,
- menu bar / status item,
- haptics.

## 1.3. Warstwa SwiftUI odpowiada za

- zawartość panelu,
- komponenty UI,
- widgety,
- widok Tray,
- Drop Mode,
- Settings,
- animację zawartości,
- shape/masking,
- design system,
- rendering stanów domenowych.

## 1.4. Zasada architektoniczna

Nie implementować logiki jako:

```swift
if something {
    window.show()
}
if somethingElse {
    window.hide()
}
```

Zamiast tego:

```text
system events
      +
user input
      ↓
NotchStateMachine
      ↓
PresentationState
      ↓
Window geometry + SwiftUI content
```

Jedynym źródłem prawdy dla głównej powierzchni ma być **stan prezentacji**.

---

# 2. Najważniejsze ograniczenia i decyzje

## 2.1. Public API first

Domyślnie używać wyłącznie publicznych API Apple.

Elementy, które mogą wymagać osobnej decyzji dystrybucyjnej:

- globalne pobieranie informacji o aktualnie odtwarzanych mediach,
- sterowanie systemowym Now Playing innych aplikacji,
- enumeracja wszystkich Apple Shortcuts,
- zaawansowane globalne gesty trackpada.

Każdy taki element musi zostać zamknięty za protokołem, żeby możliwa była wymiana implementacji.

Przykład:

```swift
protocol MediaProvider {
    var currentItem: MediaItem? { get }
    var state: PlaybackState { get }

    func refresh() async
    func togglePlayPause() async
    func next() async
    func previous() async
}
```

Nigdy nie wolno wiązać `MediaWidgetView` bezpośrednio z prywatnym API.

## 2.2. Dwa potencjalne warianty dystrybucji

Architektura ma wspierać dwa profile:

### Profile A — App Store Safe

- App Sandbox,
- tylko publiczne API,
- ograniczona integracja z globalnym Now Playing,
- Shortcuts uruchamiane przez oficjalny URL scheme,
- pełna zgodność z App Store Review.

### Profile B — Direct Distribution

- notarized Developer ID application,
- możliwość użycia mechanizmów niedostępnych w sandboxie,
- potencjalnie lepsza integracja globalnych inputów,
- ewentualne prywatne API tylko po jawnej decyzji produktowej.

**MVP należy pisać public-API-first.**

---

# 3. Repozytorium i struktura projektu

Agent ma utworzyć strukturę:

```text
NotchApp/
├── App/
│   ├── NotchApp.swift
│   ├── AppDelegate.swift
│   ├── AppLifecycleCoordinator.swift
│   └── DependencyContainer.swift
│
├── Core/
│   ├── StateMachine/
│   │   ├── NotchState.swift
│   │   ├── NotchEvent.swift
│   │   ├── NotchStateMachine.swift
│   │   └── PresentationPolicy.swift
│   │
│   ├── Display/
│   │   ├── DisplayDescriptor.swift
│   │   ├── DisplayGeometry.swift
│   │   ├── DisplayAnchor.swift
│   │   ├── DisplayManager.swift
│   │   └── NotchGeometryResolver.swift
│   │
│   ├── Window/
│   │   ├── NotchPanel.swift
│   │   ├── NotchWindowController.swift
│   │   ├── WindowGeometryController.swift
│   │   └── WindowLevelPolicy.swift
│   │
│   ├── Input/
│   │   ├── InputMonitor.swift
│   │   ├── PointerMonitor.swift
│   │   ├── GestureMonitor.swift
│   │   └── InteractionZone.swift
│   │
│   └── Logging/
│       ├── AppLogger.swift
│       └── DebugOverlayModel.swift
│
├── Features/
│   ├── Nook/
│   │   ├── NookView.swift
│   │   ├── NookViewModel.swift
│   │   ├── WidgetRegistry.swift
│   │   └── WidgetDescriptor.swift
│   │
│   ├── LiveActivities/
│   │   ├── LiveActivityCoordinator.swift
│   │   ├── LiveActivityView.swift
│   │   └── LiveActivityDescriptor.swift
│   │
│   ├── Tray/
│   │   ├── TrayView.swift
│   │   ├── TrayStore.swift
│   │   ├── TrayItem.swift
│   │   ├── TrayFileStorage.swift
│   │   ├── DragDropCoordinator.swift
│   │   └── AirDropService.swift
│   │
│   ├── Media/
│   │   ├── MediaWidgetView.swift
│   │   ├── MediaWidgetModel.swift
│   │   ├── MediaProvider.swift
│   │   └── Providers/
│   │
│   ├── Calendar/
│   │   ├── CalendarWidgetView.swift
│   │   ├── CalendarService.swift
│   │   └── CalendarModels.swift
│   │
│   ├── Mirror/
│   │   ├── MirrorWidgetView.swift
│   │   ├── CameraService.swift
│   │   └── CameraPreviewRepresentable.swift
│   │
│   ├── Shortcuts/
│   │   ├── ShortcutsWidgetView.swift
│   │   ├── ShortcutDescriptor.swift
│   │   └── ShortcutsService.swift
│   │
│   └── Settings/
│       ├── SettingsRootView.swift
│       ├── GeneralSettingsView.swift
│       ├── GestureSettingsView.swift
│       ├── NookSettingsView.swift
│       ├── TraySettingsView.swift
│       ├── LiveActivitySettingsView.swift
│       └── DisplaySettingsView.swift
│
├── DesignSystem/
│   ├── DesignTokens.swift
│   ├── NotchShape.swift
│   ├── WidgetContainer.swift
│   ├── Typography.swift
│   └── AnimationTokens.swift
│
├── Resources/
│   ├── Assets.xcassets
│   └── Localizable.xcstrings
│
├── Tests/
│   ├── StateMachineTests/
│   ├── GeometryTests/
│   ├── TrayTests/
│   └── ServiceTests/
│
└── README.md
```

Agent może zmieniać nazwy plików, ale nie powinien łączyć wszystkich odpowiedzialności w kilku dużych klasach.

---

# 4. Faza 0 — techniczny spike przed właściwą implementacją

## Cel

Potwierdzić, że fundament produktu jest wykonalny na docelowym macOS.

## Zadania

### 4.1. Zbudować minimalne `NSPanel`

Panel:

- borderless,
- transparent,
- bez shadow systemowego,
- bez title bar,
- bez traffic lights,
- nie może normalnie aktywować aplikacji,
- ma być pozycjonowany względem górnego środka aktywnego ekranu.

Bazowy kierunek:

```swift
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

Przetestować `styleMask` zawierający:

```swift
.borderless
.nonactivatingPanel
```

Ustawić:

```swift
isOpaque = false
backgroundColor = .clear
hasShadow = false
```

Nie ustalać ostatecznego `window.level` bez testów.

### 4.2. Sprawdzić zachowanie w Spaces

Przetestować kombinację:

```swift
collectionBehavior = [
    .canJoinAllSpaces,
    .fullScreenAuxiliary
]
```

Sprawdzić:

- normalny Desktop,
- przełączanie Space,
- aplikację fullscreen,
- Mission Control,
- Stage Manager,
- drugi monitor.

### 4.3. Sprawdzić focus

Scenariusz:

1. otworzyć Xcode,
2. rozpocząć pisanie,
3. najechać na notch,
4. otworzyć overlay,
5. zamknąć overlay,
6. dalej pisać bez ponownego klikania Xcode.

**Warunek:** overlay nie może niepotrzebnie przejąć focusu.

### 4.4. Sprawdzić geometrię notcha

Odczytać dla każdego `NSScreen`:

```swift
screen.frame
screen.visibleFrame
screen.safeAreaInsets
screen.auxiliaryTopLeftArea
screen.auxiliaryTopRightArea
```

Zapisać dane w debug logu.

Jeżeli:

```text
safeAreaInsets.top > 0
AND
auxiliaryTopLeftArea != nil
AND
auxiliaryTopRightArea != nil
```

ekran traktować jako `physicalNotch`.

Jeżeli nie — `virtualHandler`.

### 4.5. Sprawdzić event monitoring

Zbudować osobny `InputMonitor`.

Najpierw przetestować `NSEvent` global/local monitor dla:

- mouse moved,
- left mouse down,
- scroll wheel,
- swipe.

Jeśli zachowanie na wspieranych wersjach systemu okaże się niestabilne, przygotować drugi backend.

```swift
protocol InputMonitoring {
    func start()
    func stop()
}
```

Implementacje:

```text
NSEventInputMonitor
CGEventInputMonitor    // tylko jeśli potrzebny
```

### 4.6. Sprawdzić drag do panelu

Zarejestrować overlay jako `NSDraggingDestination`.

Potwierdzić, że działa przeciągnięcie z:

- Finder,
- Desktop,
- Safari download,
- Mail attachment.

### 4.7. Wynik spike

Utworzyć:

```text
docs/TECHNICAL_SPIKE.md
```

z tabelą:

| Obszar | Status | Rozwiązanie | Ryzyko |
|---|---|---|---|
| Overlay | PASS/FAIL | ... | ... |
| Fullscreen | PASS/FAIL | ... | ... |
| Spaces | PASS/FAIL | ... | ... |
| Focus | PASS/FAIL | ... | ... |
| Physical notch detection | PASS/FAIL | ... | ... |
| Pointer monitor | PASS/FAIL | ... | ... |
| Gestures | PASS/FAIL | ... | ... |
| Drag destination | PASS/FAIL | ... | ... |

## Kryterium zakończenia Fazy 0

Nie przechodzić dalej, jeśli nie istnieje działający prototyp:

```text
black surface
→ top center
→ opens
→ closes
→ does not steal focus
→ works on at least Desktop + fullscreen
```

---

# 5. Faza 1 — fundament aplikacji

## 5.1. Lifecycle

Zbudować `AppDelegate`.

Odpowiedzialności:

- inicjalizacja dependency container,
- uruchomienie `DisplayManager`,
- utworzenie paneli,
- uruchomienie input monitor,
- obsługa zmian ekranów,
- status item,
- otwarcie Settings,
- Quit.

Preferowany model:

```swift
@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView()
        }
    }
}
```

## 5.2. Brak Dock icon

Docelowo ustawić aplikację jako accessory/background utility.

Dopuszczalne strategie:

- `LSUIElement`,
- lub odpowiednia `activationPolicy`.

Zachować możliwość otwarcia Settings przez status item.

## 5.3. Status item

Dodać minimalne menu:

```text
Open Settings
Enable / Disable Notch
Pause Live Activities
--------------------
Quit
```

Status item nie jest głównym interfejsem produktu.

## 5.4. Dependency container

Nie używać singletonów wszędzie.

```swift
@MainActor
final class DependencyContainer {
    let displayManager: DisplayManager
    let inputMonitor: InputMonitor
    let trayStore: TrayStore
    let mediaProvider: MediaProvider
    let calendarService: CalendarService
    let cameraService: CameraService
    let shortcutsService: ShortcutsService
    let settingsStore: SettingsStore
}
```

## Kryterium akceptacji

Po uruchomieniu:

- brak zwykłego głównego okna,
- status item działa,
- Settings można otworzyć,
- Quit działa,
- dependency container jest inicjalizowany dokładnie raz.

---

# 6. Faza 2 — model ekranów i geometria notcha

To jest jeden z najważniejszych etapów.

## 6.1. `DisplayDescriptor`

```swift
struct DisplayDescriptor: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaInsets: NSEdgeInsets
    let scaleFactor: CGFloat
    let anchor: DisplayAnchor
}
```

## 6.2. `DisplayAnchor`

```swift
enum DisplayAnchor: Equatable {
    case physicalNotch(PhysicalNotchGeometry)
    case virtualHandler(VirtualHandlerGeometry)
}
```

## 6.3. Obliczanie fizycznego notcha

Jeśli istnieją:

```swift
auxiliaryTopLeftArea
auxiliaryTopRightArea
```

obliczyć gap pomiędzy nimi.

Konceptualnie:

```text
LEFT AUX AREA     PHYSICAL NOTCH       RIGHT AUX AREA
████████████      XXXXXXXXXXXXX       █████████████
            ^                   ^
            |                   |
        left.maxX           right.minX
```

Wyznaczyć:

```swift
notchMinX = leftArea.maxX
notchMaxX = rightArea.minX
notchWidth = notchMaxX - notchMinX
```

Punkt centralny:

```swift
centerX = (notchMinX + notchMaxX) / 2
```

Wysokość hardware zone określić na podstawie:

```swift
safeAreaInsets.top
```

Nie hardcodować:

```text
MacBook Pro 14 = X
MacBook Pro 16 = Y
```

## 6.4. Fine tune

W Settings dodać:

```text
Notch width correction: -40 ... +40 pt
Horizontal correction: -20 ... +20 pt
Vertical correction: -10 ... +20 pt
Content top inset: 0 ... 30 pt
```

Wartości mają być `per display`, jeśli to możliwe.

## 6.5. Virtual Handler

Na ekranie bez notcha utworzyć:

```text
width: configurable
height: 8–32 pt
position: top center
```

Tryby:

```text
visible
subtle
transparent-hit-area
disabled
```

## 6.6. DisplayManager

Reagować na:

- podłączenie monitora,
- odłączenie,
- zmianę rozdzielczości,
- zmianę scale factor,
- zmianę primary display.

Nie zakładać, że `NSScreen.main` jest stale tym samym ekranem.

## 6.7. Debug overlay

Dodać flagę developerską:

```text
Show Geometry Debug Overlay
```

Overlay ma rysować:

- `screen.frame`,
- safe area,
- auxiliary left/right,
- computed notch rect,
- hit zone,
- panel rect.

To drastycznie ułatwi debugging.

## Kryteria akceptacji

- prawidłowe wykrywanie notcha bez listy konkretnych modeli,
- virtual handler na monitorze bez notcha,
- poprawne przeliczenie współrzędnych,
- działanie Retina/non-Retina,
- reakcja na hot-plug monitora.

---

# 7. Faza 3 — State Machine

## 7.1. Stany

Zaimplementować minimum:

```swift
enum NotchState: Equatable {
    case idle
    case liveActivity(LiveActivitySnapshot)
    case peek
    case expandedNook
    case expandedTray
    case dragTarget(DragTargetState)
    case temporarilyLocked(LockedState)
}
```

Opcjonalnie:

```swift
case transitioning(from:..., to:...)
```

ale preferowane jest trzymanie transition state w warstwie prezentacji, a nie w domenie.

## 7.2. Eventy

```swift
enum NotchEvent {
    case pointerEntered
    case pointerExited

    case primaryClick
    case secondaryClick

    case swipeDown
    case swipeUp
    case swipeLeft
    case swipeRight

    case dragEntered(DragPayload)
    case dragUpdated(DragLocation)
    case dragExited
    case dropPerformed(DropTarget)

    case mediaBecameActive(MediaItem)
    case mediaChanged(MediaItem)
    case mediaStopped

    case trayChanged
    case openNook
    case openTray
    case close

    case screenChanged(DisplayDescriptor)
    case appWillResignActive
    case appDidBecomeActive

    case settingsChanged
}
```

## 7.3. Priorytety

Przy konfliktach eventów przyjąć:

```text
1. active drag/drop
2. explicit user-opened expanded view
3. pointer peek
4. live activity
5. idle
```

Czyli:

```text
dragTarget > expanded > peek > liveActivity > idle
```

## 7.4. Przykładowe przejścia

```text
idle + pointerEntered
→ peek

peek + dwellTimerFinished
→ expandedNook

peek + pointerExited
→ idle/liveActivity

idle + primaryClick
→ expandedNook

expandedNook + primaryClick on Tray
→ expandedTray

ANY + dragEntered
→ dragTarget

dragTarget + dragExited
→ previousMeaningfulState

dragTarget + dropPerformed(.tray)
→ expandedTray

expandedNook + pointerExited
→ delayed close

expandedNook + close
→ liveActivity if available, otherwise idle
```

## 7.5. Dwell timers

Nigdy nie używać rozsianych `DispatchQueue.asyncAfter`.

Utworzyć:

```swift
protocol InteractionTimer {
    func schedule(_ action: TimerAction, after: Duration)
    func cancel(_ action: TimerAction)
}
```

Przykład:

```text
hoverOpenDelay = 250 ms
closeDelay = 350 ms
dragOpenDelay = 50–100 ms
```

Wartości konfigurowalne.

## 7.6. Determinizm

State machine musi być testowalna bez AppKit.

Test:

```swift
func testDragAlwaysOverridesLiveActivity()
func testPointerExitReturnsToLiveActivity()
func testExplicitOpenDoesNotImmediatelyCloseOnMinorPointerExit()
func testDropIntoTrayOpensTray()
```

## Kryterium akceptacji

Minimum 25 testów state machine, obejmujących wszystkie przejścia krytyczne.

---

# 8. Faza 4 — `NSPanel` i warstwa prezentacji

## 8.1. Jedna powierzchnia

Nie tworzyć osobnego okna dla:

- idle,
- peek,
- expanded Nook,
- Tray,
- Drop Mode.

Każdy ekran powinien mieć jedną główną `NotchPanel`.

Panel zmienia:

- frame,
- maskę,
- zawartość,
- hit zone.

## 8.2. Stany geometryczne

Przyjąć wartości startowe, które potem zostaną dopracowane:

```swift
struct NotchDimensions {
    var collapsedWidth: CGFloat
    var collapsedHeight: CGFloat

    var peekWidth: CGFloat = 280
    var peekHeight: CGFloat = 72

    var expandedWidth: CGFloat = 760
    var expandedHeight: CGFloat = 230

    var trayHeight: CGFloat = 250
}
```

`collapsedWidth` powinno wynikać z hardware notcha.

## 8.3. Anchor

Panel zawsze rośnie względem:

```text
top-center
```

Nie względem zwykłego `frame.origin`.

Funkcja:

```swift
func frame(
    for state: NotchState,
    on display: DisplayDescriptor
) -> CGRect
```

musi zwracać finalny frame dla stanu.

## 8.4. Animacja frame

Animować:

- width,
- height,
- origin.x,
- origin.y.

Top panelu ma pozostać logicznie przyklejony do top edge.

Nie może wyglądać, jakby panel spadał z góry.

## 8.5. Shape

Zbudować `NotchShape`.

Parametry:

```swift
struct NotchShapeMetrics {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var shoulderRadius: CGFloat
    var hardwareBlendWidth: CGFloat
}
```

Shape ma mieć różne parametry dla:

- compact,
- peek,
- expanded.

## 8.6. Background

Domyślnie:

```text
true black / #000000
```

Powód: zlanie z fizycznym wycięciem.

Opcjonalnie:

```text
Translucent expanded background
```

ale collapsed surface pozostawić maksymalnie czarny.

## 8.7. Focus

`NSPanel` nie może stać się key window podczas:

- hover,
- passive live activity,
- drag hover.

Może stać się key wyłącznie wtedy, gdy później zostaną dodane elementy wymagające text input.

## 8.8. Kliknięcia poza panel

W expanded state kliknięcie poza:

- zamyka panel,
- ale nie może „połknąć” kliknięcia przeznaczonego dla aplikacji pod spodem, jeśli można tego uniknąć.

Przetestować zachowanie przed finalną decyzją.

## Kryteria akceptacji

- 60 FPS podczas animacji na typowym Apple Silicon,
- brak migotania,
- brak flash białego tła,
- brak widocznego prostokąta window,
- brak niepotrzebnego focus switch.

---

# 9. Faza 5 — Input i interaction zones

## 9.1. Strefy

Zdefiniować:

```swift
struct InteractionZone {
    let collapsedRect: CGRect
    let hoverRect: CGRect
    let expandedRect: CGRect
    let dragActivationRect: CGRect
}
```

`hoverRect` może być nieznacznie większy niż faktyczny notch.

`dragActivationRect` może być jeszcze większy, aby łatwiej było trafić plikiem.

## 9.2. Hover

Flow:

```text
global pointer moves
→ determine screen
→ determine notch interaction zone
→ pointer entered?
→ emit event
```

Nie polegać wyłącznie na `NSTrackingArea`, jeżeli idle overlay ma ignorować kliknięcia.

## 9.3. Kliknięcie

Kliknięcie w compact notch:

```text
idle/live → expandedNook
expanded → close
```

Kliknięcie w widget nie może triggerować global toggle.

## 9.4. Gesty

MVP gestures:

```text
swipe/scroll down over notch → open
swipe/scroll up over notch → close
horizontal gesture over media → next/previous
```

Nie interpretować każdego `scrollWheel` jako swipe.

Zaimplementować recognizer z:

```text
minimum accumulated delta
maximum duration
direction lock
cooldown
```

Przykładowo:

```text
accumulatedY > threshold
abs(Y) > abs(X) * 1.5
duration < 500 ms
```

Wartości dostroić eksperymentalnie.

## 9.5. Haptics

Dodać `HapticService`.

Feedback tylko dla:

- otwarcia,
- wyboru drop zone,
- udanego drop,
- completion shortcut.

Musi istnieć:

```text
Disable Haptics
```

## Kryteria akceptacji

- hover nie otwiera się przypadkowo podczas zwykłej pracy,
- swipe nie triggeruje dwukrotnie,
- gesty są wyłączalne,
- pointer na innym ekranie aktywuje właściwy display.

---

# 10. Faza 6 — Nook i system widgetów

## 10.1. Nie kodować layoutu na sztywno

Utworzyć:

```swift
protocol NotchWidget {
    var descriptor: WidgetDescriptor { get }
}
```

```swift
struct WidgetDescriptor: Identifiable {
    let id: String
    let kind: WidgetKind
    let minimumWidth: CGFloat
    let preferredWidth: CGFloat
    let maximumWidth: CGFloat
    let priority: Int
    let requiredPermission: PermissionKind?
}
```

## 10.2. Registry

```swift
@MainActor
final class WidgetRegistry: ObservableObject {
    @Published var enabledWidgets: [WidgetDescriptor]
}
```

Settings pozwalają:

- enable/disable,
- kolejność,
- szerokość,
- kompaktowy/duży layout.

## 10.3. Layout

Expanded Nook:

```text
┌───────────────────────────────────────────────────────────┐
│  Nook   Tray                                    settings │
│                                                           │
│  [ MEDIA LARGE ] [ CALENDAR ] [ SHORTCUTS ] [ MIRROR ]  │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

Zasady:

- poziomy layout,
- bez przypadkowego overflow,
- jeśli widgetów jest dużo: poziomy scroll,
- pierwsza widoczna sekcja bez scrolla powinna zawierać media + co najmniej jeden dodatkowy widget.

## 10.4. WidgetContainer

Wspólne elementy:

- background,
- border,
- corner radius,
- hover state,
- padding,
- disabled state,
- permission missing state.

## 10.5. Nook / Tray selector

Minimalistyczny.

Nie używać standardowego segmented control 1:1.

Ma wyglądać jak część powierzchni.

## Kryteria akceptacji

- widget można wyłączyć bez zmian kodu layoutu,
- kolejność widgetów jest konfigurowalna,
- brak zależności widget↔window controller.

---

# 11. Faza 7 — File Tray

Jest to funkcja MVP o wysokim priorytecie.

## 11.1. Model

```swift
struct TrayItem: Identifiable, Codable, Equatable {
    let id: UUID
    let originalURL: URL?
    let storedURL: URL
    let displayName: String
    let utiIdentifier: String?
    let fileSize: Int64?
    let addedAt: Date
    let kind: TrayItemKind
}
```

## 11.2. Strategia przechowywania

Dla niezawodności MVP po drop:

1. odczytać URL z drag pasteboard,
2. natychmiast stworzyć wpis,
3. skopiować element do kontrolowanego katalogu aplikacji,
4. Tray używa później `storedURL`,
5. usunięcie z Tray usuwa kopię.

Przykład:

```text
~/Library/Caches/<bundle-id>/Tray/<UUID>/<filename>
```

Powód:

- oryginalny plik może zostać usunięty,
- zamontowany wolumen może zniknąć,
- sandbox/access scope może się skończyć.

Później można dodać tryb `referenceOnly`.

## 11.3. Limity

Settings:

```text
Max Tray storage: 1 GB / 5 GB / 10 GB / unlimited
Auto cleanup: 1 day / 7 days / 30 days / never
```

Domyślnie:

```text
7 days
```

## 11.4. Drag destination

Przy `draggingEntered`:

```text
emit .dragEntered(payload)
→ state = .dragTarget
```

`draggingUpdated`:

- ustalić, czy pointer jest nad Tray czy AirDrop,
- podświetlić dokładnie jeden target.

`performDragOperation`:

- Tray → ingest,
- AirDrop → AirDrop service.

## 11.5. Drop Mode

Normalne widgety znikają.

UI:

```text
┌───────────────────────────────────────────────┐
│                                               │
│   ┌──────────────────┐  ┌──────────────────┐ │
│   │                  │  │                  │ │
│   │    FILES TRAY    │  │     AIRDROP      │ │
│   │                  │  │                  │ │
│   └──────────────────┘  └──────────────────┘ │
│                                               │
└───────────────────────────────────────────────┘
```

Aktywny target:

- powiększenie 1–3%,
- wyższa jasność,
- lekki border,
- haptic po wejściu.

## 11.6. Widok Tray

Każdy element:

- thumbnail,
- nazwa,
- typ,
- file size opcjonalnie,
- remove button,
- drag handle implicit.

## 11.7. Drag OUT

Użytkownik musi móc:

```text
Tray → Mail
Tray → Finder
Tray → Slack
Tray → browser upload
Tray → Xcode
```

Zaimplementować AppKit dragging source.

Weryfikować:

- pojedynczy item,
- wiele itemów,
- folder,
- image,
- PDF,
- ZIP,
- plik > 1 GB.

## 11.8. Thumbnail

Używać systemowych ikon / Quick Look thumbnail generation, jeśli dostępne.

Generowanie thumbnail nie może blokować MainActor.

## 11.9. Atomiczność

Ingest:

```text
copy succeeds
→ add database/model record

copy fails
→ do not add ghost record
```

Usuwanie:

```text
remove UI record
→ delete cache
```

Błędy plikowe logować.

## Kryteria akceptacji

- drop z Finder działa,
- plik pozostaje w Tray po zamknięciu Nooka,
- plik można przeciągnąć do innej aplikacji,
- restart aplikacji odtwarza Tray,
- remove usuwa cache,
- cleanup działa.

---

# 12. Faza 8 — AirDrop

Apple udostępnia systemowy `NSSharingService` dla AirDrop.

## 12.1. Service

```swift
protocol AirDropServicing {
    func send(items: [URL]) async throws
}
```

Implementacja powinna użyć systemowego sharing service AirDrop.

Nie implementować własnego peer-to-peer transferu.

## 12.2. Flow

```text
drag file
→ hover notch
→ Drop Mode
→ AirDrop highlighted
→ drop
→ invoke system AirDrop service
```

## 12.3. Błędy

Obsłużyć:

- brak AirDrop service,
- pusty payload,
- nieobsługiwany typ,
- user cancel.

## Kryterium akceptacji

Drop do AirDrop otwiera natywny systemowy proces bez kopiowania produktu AirDrop wewnątrz aplikacji.

---

# 13. Faza 9 — Live Activities

## 13.1. Model

Nie jest to framework iOS Live Activities.

To wewnętrzna nazwa produktu.

```swift
struct LiveActivitySnapshot: Equatable {
    let primary: LiveActivityContent?
    let secondary: LiveActivityContent?
}
```

## 13.2. Typy

MVP:

```text
media
tray
calendar
```

## 13.3. Placement

Przykład media:

```text
[ artwork ]  [ PHYSICAL NOTCH ]  [ waveform ]
```

Tray:

```text
[ 3 files ]  [ PHYSICAL NOTCH ]  [ + ]
```

Calendar:

```text
[ 14:30 ]  [ PHYSICAL NOTCH ]  [ meeting ]
```

## 13.4. Priority resolver

Jeśli aktywne są jednocześnie:

- media,
- calendar,
- tray,

rozstrzygnąć przez:

```text
user pinned activity
> active media
> active transfer/Tray context
> upcoming calendar
```

## 13.5. Interakcja

Kliknięcie activity:

```text
media → expandedNook focused on Media
tray → expandedTray
calendar → expandedNook focused on Calendar
```

## 13.6. Ustawienia

Per activity:

```text
enabled
left/right visibility
effect
corner radius
show artwork color accents
```

## Kryteria akceptacji

- live activity nie poszerza się przypadkowo,
- po media stop stan wraca poprawnie,
- activity nie blokuje menu bar poza interaction zone.

---

# 14. Faza 10 — Media Player

To obszar o istotnym ryzyku API.

## 14.1. Najpierw SPIKE

Przed implementacją widgetu utworzyć:

```text
docs/MEDIA_INTEGRATION_SPIKE.md
```

Odpowiedzieć:

1. Jak legalnie/publicznie odczytać systemowe Now Playing innych aplikacji na wspieranym macOS?
2. Czy można publicznym API wysłać play/pause/next/previous do aktualnego playera?
3. Jak zachowuje się Apple Music?
4. Jak zachowuje się Spotify?
5. Jak zachowuje się Safari/YouTube?
6. Jakie są różnice App Store vs direct distribution?
7. Jakie permissions są potrzebne?

Apple `MPNowPlayingInfoCenter` służy przede wszystkim do publikowania informacji o mediach odtwarzanych przez własną aplikację, więc nie zakładać, że jest publicznym API do czytania globalnego Now Playing.

## 14.2. Provider abstraction

```swift
protocol MediaProvider: AnyObject {
    var snapshot: MediaSnapshot { get }

    func start() async
    func stop() async

    func togglePlayPause() async throws
    func next() async throws
    func previous() async throws
}
```

Implementacje mogą później obejmować:

```text
PublicMediaProvider
AppleMusicProvider
SpotifyProvider
DirectDistributionMediaProvider
MockMediaProvider
```

## 14.3. Model

```swift
struct MediaItem: Equatable {
    let title: String
    let artist: String?
    let album: String?
    let artwork: NSImage?
    let duration: TimeInterval?
    let elapsed: TimeInterval?
}
```

```swift
enum PlaybackState {
    case playing
    case paused
    case stopped
    case unknown
}
```

## 14.4. Widget UI

Large:

```text
┌─────────────────────────────────────┐
│ ┌─────────┐                         │
│ │ ARTWORK │   Track title           │
│ │         │   Artist                │
│ └─────────┘                         │
│          previous  pause  next      │
│  ━━━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━  │
└─────────────────────────────────────┘
```

## 14.5. Waveform

Nie próbować udawać prawdziwego waveform, jeśli aplikacja nie ma dostępu do audio samples.

Tryby:

```text
true audio visualization     // tylko jeśli legalnie dostępne
animated synthetic waves     // fallback
disabled
```

Nie nazywać syntetycznego efektu „audio spectrum” w kodzie domenowym.

## 14.6. Artwork colors

Opcjonalnie wyciągnąć dominujący kolor z artworku w background task.

Używać tylko jako accent.

Black surface ma pozostać dominujący.

## 14.7. Performance

Artwork cache:

```text
memory cache
max 20–50 images
```

Nie dekodować obrazów na każdym render.

## Kryterium akceptacji

Widget nie jest uznany za zakończony, dopóki provider nie ma jasno opisanego modelu dystrybucji i ograniczeń.

---

# 15. Faza 11 — Calendar

## 15.1. EventKit

Użyć `EKEventStore`.

Widget potrzebuje odczytu eventów, więc poprosić o odpowiedni zakres dostępu dopiero przy pierwszym włączeniu Calendar.

Nie pytać o permission podczas pierwszego startu całej aplikacji.

## 15.2. Permission UX

Widget przed grant:

```text
Calendar
See upcoming events in your Nook.

[Allow Calendar Access]
```

Denied:

```text
Calendar access is disabled.
[Open Settings]
```

## 15.3. Model

```swift
struct CalendarDay: Identifiable {
    let date: Date
    let events: [CalendarEvent]
}
```

```swift
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: NSColor?
}
```

## 15.4. Zakres

Domyślnie:

```text
today - 1 day
today + 3 days
```

Settings:

```text
Days before: 0–7
Days after: 1–14
Visible calendars: multi-select
Show declined: yes/no
Show all-day: yes/no
```

## 15.5. Odświeżanie

Nie query EventKit przy każdym render.

```text
refresh:
- app launch
- calendar changed notification
- day boundary
- widget open if cache older than N minutes
```

## 15.6. UI

Widget ma być glanceable.

Nie robić pełnego month view.

## Kryteria akceptacji

- first-time permission poprawny,
- denied state poprawny,
- eventy aktualizują się bez restartu,
- filtr kalendarzy działa.

---

# 16. Faza 12 — Mirror / Camera

## 16.1. AVFoundation

Użyć:

```text
AVCaptureSession
AVCaptureDevice
AVCaptureDeviceInput
AVCaptureVideoPreviewLayer
```

## 16.2. Zasada prywatności

Sesja nie może działać stale.

Flow:

```text
Mirror becomes visible
→ request permission if needed
→ configure session
→ startRunning

Mirror leaves visible state
→ stopRunning
→ release resources if appropriate
```

## 16.3. Permission

`NSCameraUsageDescription`.

Mikrofon nie jest potrzebny do lustra. Nie prosić o microphone access bez konkretnej funkcji.

## 16.4. Camera chooser

Settings:

```text
Camera:
- Automatic
- FaceTime HD
- Studio Display Camera
- Continuity Camera
...
```

Lista dynamiczna.

## 16.5. UI

Domyślnie:

- mirror horizontally,
- aspect fill,
- rounded corners,
- camera indicator respektowany przez system.

Opcja:

```text
Mirror image: on/off
```

## 16.6. Resource handling

`startRunning` / `stopRunning` wykonywać poza MainActor, jeśli API na to pozwala.

## Kryteria akceptacji

- kamera nie uruchamia się bez pokazania widgetu,
- znika po zamknięciu,
- zmiana kamery działa,
- denial state nie crashuje.

---

# 17. Faza 13 — Shortcuts

## 17.1. Public API route

Do uruchamiania shortcut preferować oficjalny Shortcuts URL scheme.

Model:

```swift
struct ShortcutDescriptor: Identifiable, Codable {
    let id: UUID
    var name: String
    var iconName: String?
    var tint: CodableColor?
}
```

## 17.2. MVP konfiguracji

Nie uzależniać MVP od automatycznego enumerowania całej biblioteki Shortcuts.

Pozwolić użytkownikowi:

```text
Add Shortcut
Name: "Resize Image"
Icon: ...
```

Przy kliknięciu zbudować poprawny URL dla Shortcuts i otworzyć go przez `NSWorkspace`.

## 17.3. Advanced spike

Sprawdzić możliwość oficjalnej enumeracji / command-line integration.

Jeżeli wymaga uruchamiania procesu `shortcuts`, implementować wyłącznie w warstwie:

```swift
protocol ShortcutsDiscoveryService
```

i nie mieszać z UI.

## 17.4. UX

Po kliknięciu:

```text
pressed
→ running indicator
→ external Shortcuts execution
```

Jeśli nie ma możliwości wiarygodnego otrzymania completion callback, nie pokazywać fałszywego „Success”.

## Kryterium akceptacji

Wybrane skróty można skonfigurować i uruchomić bez prywatnych API.

---

# 18. Faza 14 — Settings

## 18.1. Sekcje

```text
General
Appearance
Gestures
Live Activities
Nook
Tray
Displays
Permissions
About
```

## 18.2. General

```text
Launch at Login
Open on Hover
Hover Delay
Close Delay
Disable Haptics
Show Menu Bar Icon
```

Launch at login implementować przez `SMAppService` na wspieranym systemie.

## 18.3. Appearance

```text
Panel width
Panel height
Corner radius
Widget spacing
Translucent expanded surface
Animations: normal / reduced
```

Respektować system:

```text
Reduce Motion
Reduce Transparency
```

## 18.4. Gestures

```text
Swipe down → Open
Swipe up → Close
Horizontal media gestures
Sensitivity
```

## 18.5. Nook

```text
enabled widgets
ordering
preferred sizes
```

## 18.6. Tray

```text
storage limit
cleanup policy
show file names
show thumbnails
```

## 18.7. Displays

Per display:

```text
Enable
Physical/Virtual detected
Width correction
Horizontal correction
Vertical correction
Virtual handler width
Virtual handler height
```

## 18.8. Permissions

Status rows:

```text
Calendar       Allowed / Denied / Not Requested
Camera         Allowed / Denied / Not Requested
Automation     ...
Input          ...
```

Button:

```text
Open System Settings
```

## 18.9. Reset

Dodać:

```text
Reset UI settings
Clear Tray
Reset all settings
```

`Reset all settings` wymaga confirm dialog.

---

# 19. Faza 15 — Launch at Login

Użyć `SMAppService`.

Service abstraction:

```swift
protocol LaunchAtLoginService {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) async throws
}
```

Po zmianie zawsze odczytać rzeczywisty status z systemu.

Nie zakładać, że `register()` == na pewno enabled.

---

# 20. Faza 16 — multi-monitor

## 20.1. Model

`DisplayManager` utrzymuje:

```swift
var displays: [DisplayDescriptor]
var pointerDisplay: DisplayDescriptor?
```

## 20.2. Strategia paneli

Preferowana:

```text
1 NotchPanel per enabled display
```

Zaleta:

- szybkie otwarcie,
- brak teleportowania istniejącego NSWindow pomiędzy Space/display,
- niezależna geometria.

Panele poza aktywnym stanem są collapsed/passive.

## 20.3. Shared state vs per-display state

Globalne:

```text
Tray content
Media content
Calendar content
Settings
```

Per display:

```text
panel state
hover state
geometry
virtual handler settings
last active tab
```

## 20.4. Drag między monitorami

Podczas drag:

```text
pointer crosses display
→ target display becomes active
→ właściwy panel przechodzi do dragTarget
→ poprzedni wraca do stanu bazowego
```

## Kryteria akceptacji

Testować minimum:

```text
MacBook internal + external 4K
external as primary
lid open
different scaling
separate Spaces ON
fullscreen on external
```

---

# 21. Faza 17 — fullscreen, Spaces, Stage Manager

Utworzyć osobny test matrix.

## Scenariusze

### Spaces

- Desktop 1 → Desktop 2,
- overlay visible,
- overlay hidden,
- dragging podczas zmiany Space.

### Fullscreen

- Safari fullscreen,
- Xcode fullscreen,
- YouTube fullscreen,
- presentation fullscreen.

### Stage Manager

- active,
- inactive,
- zmiana active app,
- overlay podczas rearrange.

## Zasady

Overlay nie powinien:

- przenosić usera do innego Space,
- wyciągać fullscreen app z fullscreen,
- aktywować swojej aplikacji bez potrzeby,
- pojawiać się na losowym displayu.

Każdy bug z tej kategorii jest **P0**.

---

# 22. Faza 18 — design system

## 22.1. Tokens

```swift
enum NotchSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}
```

```swift
enum NotchRadius {
    static let widget: CGFloat = 18
    static let expanded: CGFloat = 28
}
```

## 22.2. Kolory

```text
surface.primary      #000000
surface.widget       white 5–8%
surface.widgetHover  white 10–14%

text.primary         white 95–100%
text.secondary       white 60–70%
text.tertiary        white 35–45%
```

Nie używać przypadkowo innych dark gray w każdym komponencie.

## 22.3. Typografia

Preferować systemowe fonty macOS.

Hierarchy:

```text
Widget title
Primary content
Secondary content
Metadata
```

## 22.4. Ikony

SF Symbols, jeśli istnieje odpowiedni symbol.

Nie mieszać pięciu stylów ikon.

## 22.5. Motion

Centralna zasada:

```text
notch morphs, content follows
```

Nie:

```text
window appears + content fades
```

Motion tokens:

```text
peek       ~180 ms
expand     ~280 ms
collapse   ~220 ms
drop mode  ~180 ms
```

Następnie dostroić spring.

## 22.6. Reduced Motion

Jeśli włączone:

- ograniczyć overshoot,
- skrócić travel,
- preferować szybki resize/fade.

---

# 23. Faza 19 — animacje i synchronizacja AppKit ↔ SwiftUI

## Problem

Frame `NSWindow` i layout SwiftUI są dwoma osobnymi systemami animacji.

Jeśli animować je niezależnie, pojawi się:

- tearing,
- lag content,
- niezsynchronizowany corner radius.

## Strategia

Utworzyć jeden `PresentationTransition`.

```swift
struct PresentationTransition {
    let from: PresentationMetrics
    let to: PresentationMetrics
    let duration: TimeInterval
    let curve: TransitionCurve
}
```

`WindowGeometryController` i SwiftUI dostają tę samą transition definition.

## Kolejność

Expand:

```text
1. prepare content
2. begin window frame expansion
3. animate shape
4. reveal secondary content progressively
5. mark transition completed
```

Collapse:

```text
1. hide heavy content
2. reduce content opacity
3. resize surface
4. end in compact/live state
```

Camera powinna zatrzymać session **przed lub w trakcie** collapse, nie kilka sekund później.

---

# 24. Faza 20 — performance

## Budżety

Target:

```text
idle CPU: ~0%
idle GPU: ~0%
memory: rozsądnie < 150 MB w typowym użyciu
animation: 60 fps
pointer monitor: bez polling loop
```

Nie używać:

```text
Timer 60 Hz do sprawdzania mouseLocation
```

Używać event-driven monitoringu.

## Profilowanie

Instruments:

- Time Profiler,
- Allocations,
- Core Animation,
- Energy Log,
- Leaks.

## Szczególnie sprawdzić

- artwork extraction,
- thumbnails,
- EventKit query,
- camera start/stop,
- panel animation,
- global input monitor.

---

# 25. Faza 21 — accessibility

## 25.1. VoiceOver

Każdy control:

- accessibility label,
- accessibility role,
- logical order.

## 25.2. Keyboard

Minimum:

```text
Esc → close
Tab → focus controls if panel explicitly activated
Enter/Space → action
```

Nie wymuszać keyboard focus przy hover.

## 25.3. Reduce Motion

Obsłużyć.

## 25.4. Contrast

Secondary text nie może mieć zbyt małego kontrastu.

---

# 26. Faza 22 — permission strategy

Nigdy nie pytać o wszystkie permissions przy first launch.

Permission jest proszony **just-in-time**.

## Matrix

| Funkcja | Permission |
|---|---|
| Nook UI | none |
| Tray | zależne od modelu sandbox/files |
| Calendar | Calendar |
| Mirror | Camera |
| Media | zależne od providera |
| Shortcuts | możliwe automation/external URL zależnie od implementacji |
| Global input | zależne od wybranego backendu |

## Onboarding

Pierwszy start:

```text
Welcome
→ short explanation
→ enable core notch
→ no permission wall
```

Permission dopiero po wejściu w funkcję.

---

# 27. Faza 23 — persistence

## Ustawienia

`SettingsStore`.

```swift
@MainActor
final class SettingsStore: ObservableObject {
    @Published var openOnHover: Bool
    @Published var hoverDelay: Double
    ...
}
```

## Tray

Metadata:

```text
JSON / lightweight persisted store
```

Nie wdrażać Core Data/SwiftData tylko dla kilku rekordów, jeśli nie daje realnej wartości.

Jeśli wymagania rozrosną się o historię/clipboard, wtedy migracja.

## Wersjonowanie

```swift
struct StoredSettings {
    let schemaVersion: Int
}
```

Od początku przygotować migracje.

---

# 28. Faza 24 — logging i diagnostyka

Użyć `Logger` / OSLog.

Kategorie:

```text
app
window
display
input
state
dragdrop
tray
media
calendar
camera
shortcuts
permissions
```

Przykład:

```text
[state] idle → peek reason=pointerEntered display=1
[state] peek → dragTarget reason=dragEntered items=2
[display] physical notch width=203 topInset=...
```

Nie logować:

- prywatnych nazw wydarzeń kalendarza w release,
- pełnych ścieżek plików użytkownika,
- nazw shortcutów bez potrzeby,
- danych wrażliwych.

## Debug panel

Ukryta opcja:

```text
Copy Diagnostics
```

Powinna kopiować:

- app version,
- macOS version,
- display geometry,
- enabled features,
- current state,
- permission statuses,
- ostatnie błędy techniczne,

ale nie prywatną treść użytkownika.

---

# 29. Faza 25 — testy jednostkowe

## State machine

Obowiązkowe.

## Geometry

Przykładowe fixtures:

```text
14" notched screen
16" notched screen
non-notched external display
Retina external
display left of primary
display above primary
```

Testować wyliczenia bez fizycznego sprzętu.

## Tray

- ingest,
- duplicate names,
- large files,
- deletion,
- restore metadata,
- missing cached file,
- cleanup.

## Calendar

Mock EventKit adapter.

## Camera

Mock authorization + device list.

## Shortcuts

URL builder tests.

---

# 30. Faza 26 — testy manualne

Utworzyć:

```text
QA_MANUAL_CHECKLIST.md
```

## Core

- [ ] click opens.
- [ ] click closes.
- [ ] hover opens if enabled.
- [ ] hover does not open if disabled.
- [ ] swipe opens.
- [ ] swipe closes.
- [ ] Esc closes.
- [ ] active app keeps focus.

## Display

- [ ] internal notch detected.
- [ ] external display gets virtual handler.
- [ ] width tune works.
- [ ] unplug monitor does not crash.
- [ ] change primary monitor works.

## Tray

- [ ] Finder file.
- [ ] Finder folder.
- [ ] Desktop.
- [ ] image from browser.
- [ ] multiple files.
- [ ] drag out.
- [ ] delete.
- [ ] restart persistence.

## Fullscreen

- [ ] Safari.
- [ ] Xcode.
- [ ] video player.
- [ ] multiple Spaces.

## Camera

- [ ] first permission.
- [ ] denied.
- [ ] allowed.
- [ ] switch camera.
- [ ] camera stops after close.

---

# 31. Faza 27 — crash safety

Obsłużyć sytuacje:

- monitor disappears while panel is open,
- file disappears during drag,
- cached file is missing,
- camera disappears,
- permission revoked while app is running,
- calendar store fails,
- shortcut name no longer exists,
- media provider terminates,
- AirDrop service unavailable.

Zasada:

```text
feature failure must not crash core notch
```

---

# 32. Faza 28 — Feature Flags

Od początku:

```swift
struct FeatureFlags {
    var media: Bool
    var calendar: Bool
    var mirror: Bool
    var shortcuts: Bool
    var liveActivities: Bool
    var gestures: Bool
    var multiDisplay: Bool
}
```

Development build może mieć Debug Settings.

Ułatwia odseparowanie błędów.

---

# 33. Kolejność faktycznej implementacji

Agent ma wykonać zadania dokładnie w tej kolejności, chyba że techniczny blocker wymusi zmianę.

## Milestone 1 — Shell

- [ ] utwórz projekt,
- [ ] AppDelegate,
- [ ] status item,
- [ ] Settings shell,
- [ ] dependency container.

**DoD:** aplikacja działa jako utility bez normalnego main window.

---

## Milestone 2 — Physical Notch Geometry

- [ ] DisplayManager,
- [ ] safe area,
- [ ] auxiliary areas,
- [ ] notch rect,
- [ ] virtual handler,
- [ ] geometry debug overlay.

**DoD:** aplikacja poprawnie pokazuje computed anchor na wszystkich podłączonych ekranach.

---

## Milestone 3 — Overlay Prototype

- [ ] NSPanel,
- [ ] borderless,
- [ ] nonactivating,
- [ ] top-center anchoring,
- [ ] black surface,
- [ ] open/close.

**DoD:** czarny panel wizualnie wyrasta z notcha.

---

## Milestone 4 — State Machine

- [ ] states,
- [ ] events,
- [ ] reducers/transitions,
- [ ] timers,
- [ ] tests.

**DoD:** UI nie posiada własnej ad-hoc logiki stanów.

---

## Milestone 5 — Pointer Input

- [ ] mouse tracking,
- [ ] hover,
- [ ] click,
- [ ] close delay,
- [ ] per-display activation.

**DoD:** komfortowy hover bez false positive.

---

## Milestone 6 — Morphing UI

- [ ] collapsed,
- [ ] peek,
- [ ] expanded,
- [ ] custom shape,
- [ ] frame animation,
- [ ] reduced motion.

**DoD:** animacja wygląda jak jedna powierzchnia, nie popup.

---

## Milestone 7 — Tray MVP

- [ ] dragging destination,
- [ ] Drop Mode,
- [ ] ingest,
- [ ] storage,
- [ ] persistence,
- [ ] drag out,
- [ ] remove.

**DoD:** pełny flow `Finder → Notch → Tray → inna aplikacja`.

---

## Milestone 8 — AirDrop

- [ ] system sharing service,
- [ ] target highlight,
- [ ] error handling.

**DoD:** `Finder → Notch → AirDrop`.

---

## Milestone 9 — Nook Widget Framework

- [ ] widget registry,
- [ ] layout,
- [ ] enable/disable,
- [ ] ordering,
- [ ] placeholder widgets.

**DoD:** można dodać nowy widget bez modyfikacji window controller.

---

## Milestone 10 — Calendar

- [ ] EventKit,
- [ ] permission,
- [ ] cache,
- [ ] widget,
- [ ] settings.

---

## Milestone 11 — Mirror

- [ ] AVFoundation,
- [ ] permission,
- [ ] camera preview,
- [ ] lifecycle,
- [ ] camera selector.

---

## Milestone 12 — Shortcuts

- [ ] manual shortcut config,
- [ ] URL scheme execution,
- [ ] widget,
- [ ] error UX.

---

## Milestone 13 — Media Spike + MVP

- [ ] public API research,
- [ ] provider interface,
- [ ] selected provider implementation,
- [ ] widget,
- [ ] live activity.

---

## Milestone 14 — Gestures

- [ ] down/up,
- [ ] horizontal media gestures,
- [ ] sensitivity,
- [ ] haptics.

Dodać dopiero po stabilnym mouse interaction.

---

## Milestone 15 — Live Activities

- [ ] activity model,
- [ ] priority resolver,
- [ ] media activity,
- [ ] Tray activity,
- [ ] Calendar activity,
- [ ] settings.

---

## Milestone 16 — Multi-display hardening

- [ ] per-screen panel,
- [ ] drag cross-display,
- [ ] external primary,
- [ ] Spaces.

---

## Milestone 17 — Polish

- [ ] motion,
- [ ] typography,
- [ ] artwork accents,
- [ ] widget sizing,
- [ ] empty states,
- [ ] permission states.

---

## Milestone 18 — Release hardening

- [ ] crash reporting decision,
- [ ] logging review,
- [ ] notarization,
- [ ] sandbox decision,
- [ ] update mechanism,
- [ ] privacy policy if required,
- [ ] QA matrix.

---

# 34. MVP — zakres obowiązkowy

Pierwsze publicznie używalne MVP powinno zawierać:

```text
✓ physical notch detection
✓ virtual handler
✓ open/close
✓ hover
✓ click
✓ smooth morph animation
✓ Nook shell
✓ Tray
✓ file drag in
✓ file drag out
✓ AirDrop
✓ Settings
✓ multi-display basics
```

Dodatkowo **jeden** widget kontekstowy.

Najbezpieczniejszy pierwszy widget:

```text
Calendar
```

Media nie powinny blokować całego MVP.

---

# 35. Poza MVP

Nie blokować MVP przez:

- perfekcyjny global Media Player,
- 10 widgetów,
- zaawansowane themes,
- plugin SDK,
- cloud sync,
- clipboard history,
- AI,
- weather,
- timers,
- pomodoro,
- notification center replacement.

Te funkcje są drugorzędne.

---

# 36. Potencjalna architektura plugin/widget SDK

Dopiero po stabilizacji:

```swift
protocol NookWidgetPlugin {
    static var identifier: String { get }

    var descriptor: WidgetDescriptor { get }

    @MainActor
    func makeExpandedView() -> AnyView

    @MainActor
    func makeCompactView() -> AnyView?
}
```

Nie budować publicznego plugin runtime w MVP.

Najpierw internal registry.

---

# 37. Najważniejsze ryzyka projektu

## RISK-001 — Fullscreen overlay

**Waga:** P0.

Ryzyko: panel nie pojawia się nad częścią fullscreen apps albo przenosi Space.

Mitigacja:

- spike na początku,
- `.fullScreenAuxiliary`,
- testy wielu aplikacji.

---

## RISK-002 — Focus stealing

**Waga:** P0.

Ryzyko: hover powoduje utratę keyboard focus.

Mitigacja:

- nonactivating `NSPanel`,
- `canBecomeKey = false`,
- oddzielić passive panel od Settings.

---

## RISK-003 — Global gestures

**Waga:** P1.

Ryzyko: nierówne zachowanie API pomiędzy macOS.

Mitigacja:

- input adapter,
- gestures jako etap późniejszy,
- pełny mouse fallback.

---

## RISK-004 — Global Now Playing

**Waga:** P1.

Ryzyko: brak kompletnego publicznego API do odczytu/sterylowania systemowego Now Playing innych aplikacji.

Mitigacja:

- Media Provider abstraction,
- osobny spike,
- nie blokować MVP,
- oddzielić App Store i direct distribution.

---

## RISK-005 — drag/drop z sandbox

**Waga:** P1.

Ryzyko: wygasające access tokens / source URL.

Mitigacja:

- kopiować ingestowane pliki do własnego storage,
- testować sandbox profile wcześnie.

---

## RISK-006 — menu bar interference

**Waga:** P0.

Ryzyko: overlay blokuje normalne elementy menu bar.

Mitigacja:

- minimalny idle hit zone,
- dokładny notch rect,
- ignoresMouseEvents/pointer-monitor strategy,
- per-display calibration.

---

## RISK-007 — high CPU idle

**Waga:** P1.

Ryzyko: polling mouse/animation.

Mitigacja:

- event-driven,
- no continuous timers,
- pause heavy services.

---

# 38. Definition of Done dla całej wersji 1.0

Produkt jest gotowy dopiero, kiedy:

## Core UX

- [ ] użytkownik nie ma wrażenia, że otwiera zwykłe okno,
- [ ] powierzchnia wyrasta z notcha,
- [ ] animacja jest stabilna,
- [ ] panel nie kradnie focusu,
- [ ] nie blokuje menu bar.

## Displays

- [ ] physical notch,
- [ ] external display,
- [ ] multiple monitors,
- [ ] hot plug,
- [ ] different scaling.

## Window management

- [ ] Spaces,
- [ ] fullscreen,
- [ ] Stage Manager,
- [ ] Mission Control.

## Tray

- [ ] file in,
- [ ] file out,
- [ ] multiple files,
- [ ] persistence,
- [ ] cleanup,
- [ ] AirDrop.

## Widgets

- [ ] Calendar,
- [ ] Mirror,
- [ ] Shortcuts,
- [ ] Media w zakresie zatwierdzonego modelu dystrybucji.

## Settings

- [ ] behavior,
- [ ] displays,
- [ ] gestures,
- [ ] widget order,
- [ ] permissions,
- [ ] Launch at Login.

## Quality

- [ ] no known P0,
- [ ] no known crash P1,
- [ ] idle energy acceptable,
- [ ] launch time acceptable,
- [ ] permission copy reviewed,
- [ ] reduced motion działa.

---

# 39. Reguły pracy dla agenta implementującego

Agent ma przestrzegać poniższych zasad.

## 39.1. Przed każdą fazą

Napisać w logu pracy:

```text
Phase:
Goal:
Files to create/change:
Technical assumptions:
Expected test:
```

## 39.2. Po każdej fazie

Napisać:

```text
Completed:
Tests:
Known issues:
Deviations from plan:
Next phase:
```

## 39.3. Nie robić dużych „mega commitów”

Preferować:

```text
feat(display): add notch geometry resolver
test(display): cover auxiliary area geometry
feat(window): add nonactivating notch panel
feat(state): add presentation state machine
```

## 39.4. Jeśli API jest niepewne

Nie zgadywać.

Utworzyć spike:

```text
docs/SPIKE_<TOPIC>.md
```

z:

- problem,
- Apple API,
- test kodu,
- wynik,
- ograniczenia,
- decyzja.

## 39.5. Nie używać prywatnego API bez oznaczenia

Każdy prywatny framework/API:

```swift
// PRIVATE API — DIRECT DISTRIBUTION ONLY
```

i musi być izolowany za interfejsem.

## 39.6. Nie hardcodować geometrii sprzętu

Zakazane:

```swift
if model == "MacBookPro18,3" {
    notchWidth = ...
}
```

Dozwolone:

```text
NSScreen geometry
+
user calibration
```

## 39.7. Nie łączyć usług systemowych z View

Zakazane:

```swift
struct CalendarWidgetView {
    let eventStore = EKEventStore()
}
```

Poprawnie:

```text
View
→ ViewModel
→ CalendarService
→ EventKit adapter
```

---

# 40. Pierwsze zadanie, które agent ma wykonać

Agent powinien rozpocząć od dokładnie tego:

## Task 001 — `OverlayFeasibilitySpike`

### Cel

Potwierdzić rdzeń produktu na aktualnym macOS.

### Wykonaj

1. Utwórz minimalny macOS project.
2. Dodaj AppDelegate.
3. Usuń normalne main window.
4. Utwórz `NotchPanel`.
5. Ustaw go jako transparentny, borderless i nonactivating.
6. Wyznacz górny środek `NSScreen.main`.
7. Jeśli ekran ma notch, pobierz `safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`.
8. Narysuj czarny prostokąt odpowiadający obliczonemu notchowi.
9. Dodaj temporary button/status menu do przełączania:
   - collapsed,
   - expanded.
10. Animuj `NSPanel` do ok. 760×230 pt i z powrotem.
11. Otwórz Xcode i sprawdź focus.
12. Otwórz Safari fullscreen i sprawdź panel.
13. Przełącz Space.
14. Podłącz monitor zewnętrzny.
15. Zapisz wynik w `docs/TECHNICAL_SPIKE.md`.

### Nie wykonuj jeszcze

- Media,
- Calendar,
- Camera,
- Shortcuts,
- pełnego Tray,
- finalnego designu.

### Task 001 — Definition of Done

```text
PASS:
black top-center surface can expand/collapse
without activating the utility app
on normal desktop and fullscreen.
```

Jeśli ten task nie przejdzie, dalsze tworzenie widgetów jest bezcelowe.

---

# 41. Task 002 — `NotchGeometryEngine`

Po pozytywnym Task 001:

1. Utwórz `DisplayDescriptor`.
2. Utwórz `DisplayAnchor`.
3. Utwórz `NotchGeometryResolver`.
4. Obsłuż physical notch.
5. Obsłuż virtual handler.
6. Dodaj unit tests.
7. Dodaj debug overlay.
8. Dodaj manual calibration.

**DoD:** żadna logika geometryczna nie znajduje się w `NotchWindowController`.

---

# 42. Task 003 — `PresentationStateMachine`

1. Utwórz enum states.
2. Utwórz event model.
3. Utwórz transition reducer.
4. Dodaj interaction timers.
5. Dodaj testy.
6. Podłącz panel tylko jako observer state.

**DoD:** panel nie decyduje sam, czy ma być otwarty.

---

# 43. Task 004 — `PointerDrivenNook`

1. Pointer monitor.
2. Enter/exit.
3. Dwell.
4. Click.
5. Escape.
6. Close delay.
7. Per-display state.

**DoD:** można wygodnie otwierać i zamykać bez focus theft.

---

# 44. Task 005 — `MorphingSurface`

1. Custom shape.
2. Geometry interpolation.
3. Spring animation.
4. Content staging.
5. Reduced Motion.
6. visual polish.

**DoD:** capture video z interakcji powinno wizualnie przypominać „rozciągnięcie notcha”, a nie popup.

---

# 45. Task 006 — `GlobalFileTray`

1. Drag destination.
2. Drag mode.
3. Tray target.
4. File ingest.
5. Persistence.
6. Thumbnails.
7. Drag source.
8. Delete.
9. Cleanup.
10. Multi-item.

**DoD:** pełny file round-trip.

---

# 46. Task 007 — `AirDropTarget`

1. Detect hover target.
2. Use system AirDrop sharing service.
3. Error handling.
4. Haptic.
5. QA.

---

# 47. Task 008 — `WidgetHost`

1. registry,
2. descriptors,
3. ordering,
4. width policy,
5. permission placeholders,
6. settings.

Dopiero po Task 008 dodawać feature widgets.

---

# 48. Task 009+ — kolejność widgetów

Implementować:

```text
1. Calendar
2. Mirror
3. Shortcuts
4. Media
```

Media na końcu z powodu największego ryzyka API.

---

# 49. Technical notes zweryfikowane względem API Apple

Plan zakłada wykorzystanie publicznych mechanizmów dostępnych w AppKit i frameworkach systemowych:

- `NSPanel` jako specjalizowany panel pomocniczy.
- `NSWindow.StyleMask.nonactivatingPanel` do panelu nieaktywującego głównej aplikacji.
- `NSWindow.CollectionBehavior.canJoinAllSpaces`.
- `NSWindow.CollectionBehavior.fullScreenAuxiliary`.
- `NSScreen.safeAreaInsets`.
- `NSScreen.auxiliaryTopLeftArea`.
- `NSScreen.auxiliaryTopRightArea`.
- `NSDraggingDestination` / `NSDraggingInfo` dla drag-and-drop.
- `NSSharingService.Name.sendViaAirDrop` dla AirDrop.
- `SMAppService` dla Launch at Login na współczesnych wersjach macOS.
- EventKit / `EKEventStore` dla Calendar.
- AVFoundation / `AVCaptureSession` dla Mirror.
- Shortcuts URL scheme dla uruchamiania skrótów.

**Ważne:** Apple `MPNowPlayingInfoCenter` nie należy traktować jako publicznego API do odczytywania globalnego Now Playing innych aplikacji; jego dokumentowana rola dotyczy publikowania informacji o mediach odtwarzanych przez własną aplikację. Dlatego global Media Player pozostaje osobnym spike'em architektonicznym.

---

# 50. Ostateczna zasada produktu

Jeśli podczas implementacji trzeba wybrać pomiędzy:

```text
A. dodaniem kolejnego widgetu
B. poprawieniem zachowania notcha
```

zawsze wybrać:

```text
B
```

Rdzeniem aplikacji jest:

```text
physical/virtual screen anchor
        +
nonintrusive overlay
        +
state machine
        +
context-aware interaction
        +
morphing motion
```

Dopiero na tym fundamencie istnieją Media, Calendar, Tray, Mirror i Shortcuts.

Jeśli ten fundament jest przeciętny, aplikacja będzie wyglądała jak zwykły popup pod notchem.

Jeśli fundament jest wykonany bardzo dobrze, nawet sama wersja:

```text
Notch + Tray + Calendar
```

będzie już pełnowartościowym produktem.
