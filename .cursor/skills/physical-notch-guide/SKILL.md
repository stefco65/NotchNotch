---
name: physical-notch-guide
description: >-
  Włącza i wyłącza różową ramkę pomocniczą fizycznego notcha
  (PhysicalNotchGuideController) podczas prac nad geometrią, Music, Dynamic
  Island, hoverem i animacjami. Używaj przy każdej pracy agenta w tym obszarze
  oraz obowiązkowo przed commit, push i pull.
---

# Physical Notch Guide

Przy **każdych pracach agenta** masz włączyć ramkę pomocniczą. Masz jej używać jako faktyczne punktu odniesienia. Przed każdym commit and pull masz wyłączyć tą ramkę.

## Co to jest

Różowa przerywana ramka (`PhysicalNotchGuideController`) pokazuje **rzeczywisty** cutout fizycznego / wirtualnego notcha (`DynamicIslandLayout.physicalNotchFrame`). To jedyne wiarygodne odniesienie przy wyrównywaniu kapsuły, Music, DI i animacji — nie zgaduj „na oko” względem menu bara.

Przełącznik:

```swift
// NotchApp/Core/Window/PhysicalNotchGuideController.swift
@MainActor
enum PhysicalNotchGuideSettings {
    /// Agent: `true` w trakcie pracy; `false` przed commit / push / pull.
    static var isEnabled = false
}
```

## Obowiązkowy workflow

1. **Start pracy** (geometria, Music, DI, hover, layout, QA wizualne):
   - ustaw `PhysicalNotchGuideSettings.isEnabled = true`
   - przebuduj / uruchom app
   - każdą decyzję o krawędziach, overlapie i parkingu DI weryfikuj względem tej ramki

2. **W trakcie pracy**:
   - traktuj ramkę jako ground truth (minX / maxX / wysokość cutoutu)
   - jeśli UI „wygląda OK”, ale mija się z ramką — UI jest złe

3. **Przed każdym commit, push lub pull**:
   - ustaw `PhysicalNotchGuideSettings.isEnabled = false`
   - upewnij się, że ta zmiana wchodzi do commita (albo że flaga już jest `false` w diffie)
   - nigdy nie wypychaj włączonej ramki na remote

## Checklist przed git

```
- [ ] PhysicalNotchGuideSettings.isEnabled == false
- [ ] brak różowej ramki po uruchomieniu app z tej zmiany
- [ ] dopiero potem: commit / push / pull
```
