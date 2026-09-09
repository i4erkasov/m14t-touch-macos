# Техническое задание: M14t Touch Manager for macOS

## 1. Назначение проекта

Разработать нативное macOS-приложение для Lenovo ThinkVision M14t, которое превращает встроенный touch digitizer монитора из примитивного режима «палец двигает курсор мыши» в более естественное touchscreen-поведение.

В качестве основы использовать существующий open-source проект:

- Repository: `talesmousinho/m14t-touch-macos`
- Language: Swift
- License: MIT
- Current approach: `IOHIDManager` → координаты касания → `CGEvent`
- Current functionality:
  - single-touch;
  - touch → left mouse down;
  - move → left mouse dragged;
  - release → left mouse up;
  - calibration;
  - multi-display mapping;
  - X/Y inversion;
  - persistence of calibration;
  - CLI;
  - LaunchAgent autostart.

Главная идея: **не переписывать HID-часть с нуля**, а отделить её от текущей примитивной mouse-emulation логики и построить поверх неё нормальный gesture/input engine и GUI.

---

# 2. Главные цели

Приложение должно:

1. Автоматически обнаруживать Lenovo ThinkVision M14t.
2. Получать raw touch/pen HID-события.
3. Определять экран, к которому относится touch digitizer.
4. Выполнять удобную GUI-калибровку.
5. Поддерживать touchscreen-like поведение:
   - tap → click;
   - swipe одним пальцем → scroll;
   - long press + move → drag;
   - опционально direct mouse mode;
   - в будущем multi-touch gestures.
6. Работать как обычное macOS `.app`.
7. Иметь menu bar icon.
8. Работать в фоне после входа пользователя в систему.
9. Позволять менять настройки без Terminal.
10. Не требовать kernel extension или System Extension, если это возможно.
11. Использовать публичные macOS API.
12. Сохранять совместимость с Apple Silicon, в первую очередь MacBook Pro M3 Pro.

---

# 3. Не делать проект с нуля

Исходный проект уже решает важные низкоуровневые задачи:

```text
USB HID Digitizer
        ↓
IOHIDManager
        ↓
raw X / Y / TipSwitch
        ↓
CoordinateMapper
        ↓
screen coordinates
```

Эту часть желательно переиспользовать и отрефакторить.

Переписать/расширить нужно в основном часть:

```text
screen coordinates
        ↓
MouseEmitter
```

Она должна превратиться в:

```text
HID input
   ↓
TouchFrame / TouchPoint
   ↓
GestureRecognizer
   ↓
InputAction
   ├── Tap
   ├── Scroll
   ├── Drag
   ├── RightClick
   ├── PointerMove
   └── Future gestures
        ↓
macOS EventEmitter
```

---

# 4. Требования к архитектуре

Предлагаемая структура:

```text
M14tTouch/
├── App/
│   ├── M14tTouchApp.swift
│   ├── AppDelegate.swift
│   ├── MenuBarController.swift
│   └── SettingsWindow.swift
│
├── Core/
│   ├── HID/
│   │   ├── HIDTouchDriver.swift
│   │   ├── HIDDeviceDetector.swift
│   │   ├── HIDUsage.swift
│   │   └── TouchPoint.swift
│   │
│   ├── Display/
│   │   ├── DisplayResolver.swift
│   │   ├── CoordinateMapper.swift
│   │   └── DisplayDescriptor.swift
│   │
│   ├── Calibration/
│   │   ├── Calibration.swift
│   │   ├── CalibrationStore.swift
│   │   └── CalibrationController.swift
│   │
│   ├── Gestures/
│   │   ├── GestureRecognizer.swift
│   │   ├── GestureState.swift
│   │   ├── GestureConfiguration.swift
│   │   └── InputAction.swift
│   │
│   ├── Events/
│   │   ├── EventEmitter.swift
│   │   ├── MouseEventEmitter.swift
│   │   └── ScrollEventEmitter.swift
│   │
│   └── Permissions/
│       └── PermissionsManager.swift
│
├── UI/
│   ├── Status/
│   ├── Settings/
│   ├── Calibration/
│   └── Diagnostics/
│
└── Tests/
```

Структура может быть скорректирована агентом, но необходимо сохранить разделение:

- получение HID;
- mapping;
- calibration;
- gesture recognition;
- генерация событий;
- UI;
- persistence.

`HIDTouchDriver` не должен самостоятельно решать, что движение пальца означает drag или scroll.

---

# 5. Модель touch input

Ввести универсальную модель события.

Пример:

```swift
struct TouchPoint {
    let id: Int
    let position: CGPoint
    let rawPosition: CGPoint
    let isTouching: Bool
    let pressure: Double?
    let timestamp: TimeInterval
}
```

Для multi-touch в будущем желательно сразу предусмотреть frame:

```swift
struct TouchFrame {
    let contacts: [TouchPoint]
    let timestamp: TimeInterval
}
```

Даже если первая версия фактически использует только один контакт.

---

# 6. InputAction

Gesture engine должен выдавать абстрактные действия, а не `CGEvent` напрямую.

Пример:

```swift
enum InputAction {
    case tap(position: CGPoint)
    case pointerMove(position: CGPoint)
    case dragBegin(position: CGPoint)
    case dragMove(position: CGPoint)
    case dragEnd(position: CGPoint)
    case scroll(deltaX: CGFloat, deltaY: CGFloat)
    case rightClick(position: CGPoint)
}
```

Это необходимо для тестируемости и дальнейшего расширения.

---

# 7. Режимы работы

## 7.1 Touchscreen Mode — основной режим

Это режим по умолчанию.

### Tap

Короткое касание без существенного движения:

```text
finger down
small/no movement
finger up
→ click at touch position
```

Курсор не должен обязательно постоянно следовать за пальцем.

Настраиваемые параметры:

- tap movement threshold;
- max tap duration.

Начальные значения можно выбрать разумные и вынести в config.

---

## 7.2 One-finger Scroll

Главная функция первой версии.

Поведение:

```text
finger down
↓
movement exceeds threshold
↓
gesture becomes SCROLL
↓
finger movement converted to scroll events
```

Важно:

- после перехода в `scroll` не генерировать `mouseDragged`;
- gesture lock: если жест распознан как scroll, он остаётся scroll до finger up;
- должна быть настройка направления;
- должна быть настройка sensitivity;
- желательно использовать pixel-based scroll events;
- желательно поддержать smooth scrolling.

Настройки:

```text
Enable one-finger scrolling: ON/OFF
Natural scrolling: ON/OFF
Sensitivity: slider
Scroll activation threshold: configurable
```

### Natural scrolling

По умолчанию поведение должно быть touchscreen-like:

если пользователь двигает палец вверх, контент должен следовать за пальцем так, как ожидается на touch device.

При необходимости направление должно инвертироваться настройкой.

---

# 8. Drag

Нельзя делать любое движение пальца drag, как текущая версия.

Предлагаемая логика:

```text
finger down
↓
hold >= longPressDelay
↓
drag mode activated
↓
movement → mouseDragged
↓
finger up → mouseUp
```

Пример default:

```text
longPressDelay = 400 ms
```

Настройки:

- enable long-press-to-drag;
- delay;
- movement tolerance before activation.

Допускается выбрать более удачный UX после тестирования.

---

# 9. Mouse Mode

Для совместимости оставить отдельный режим:

```text
Touch behavior:
○ Touchscreen
○ Mouse
```

Mouse mode повторяет существующее поведение оригинального проекта:

```text
touch down → leftMouseDown
move → leftMouseDragged
touch up → leftMouseUp
```

Это позволит не потерять существующую функциональность.

---

# 10. Cursor behavior

Для Touchscreen Mode желательно:

- не таскать визуальный mouse cursor постоянно за пальцем;
- на tap генерировать click непосредственно в точке касания;
- при scroll не перемещать cursor без необходимости.

Добавить настройки:

```text
Cursor while touching:
○ Keep current cursor position
○ Move cursor to touch point
```

Опционально позже:

```text
Hide cursor during touch
```

Нельзя использовать приватные API ради сокрытия курсора.

---

# 11. Multi-touch — Phase 2

Не блокировать архитектуру single-touch предположениями.

В будущем:

### Two-finger scroll

```text
2 contacts
parallel movement
→ scroll
```

### Two-finger tap

```text
two short contacts
→ right click
```

### Pinch

Исследовать возможность генерации соответствующего поведения на macOS.

Не обещать системный native touchscreen API, если публичного API для этого нет.

---

# 12. Stylus / Pen — Phase 2/3

M14t имеет HID интерфейс `Pen and multitouch sensor`.

Не смешивать pen input и finger input.

Необходимо сначала создать diagnostic mode, отображающий raw HID usages.

Изучить поддержку:

- tip switch;
- pressure;
- barrel button(s);
- eraser;
- X/Y;
- contact type / digitizer usage.

Предлагаемая модель:

```swift
enum InputDeviceType {
    case finger
    case pen
    case eraser
}
```

Будущая цель:

- stylus move;
- stylus click/draw;
- pressure if possible;
- right-click/button mapping;
- eraser;
- avoid interference between stylus and finger.

Pen не является обязательным для MVP.

---

# 13. GUI

Использовать SwiftUI, AppKit допускается там, где SwiftUI неудобен.

Приложение должно быть прежде всего menu-bar utility.

Пример menu:

```text
M14t Touch
────────────────────────
● ThinkVision M14t connected

Touch
☑ Enable touch

Mode
● Touchscreen
○ Mouse

Calibration…
Settings…
Diagnostics…

☑ Start at Login

Quit
```

---

# 14. Settings window

Пример структуры:

## General

```text
Device
ThinkVision M14t
Status: Connected

Target display
[ ThinkVision M14t ▼ ]

☑ Enable touch
☑ Start at Login
```

## Touch

```text
Mode
● Touchscreen
○ Mouse

Tap
☑ Tap to click

Scrolling
☑ One-finger scroll
☑ Natural scrolling
Sensitivity  [────●────]

Drag
☑ Long press to drag
Delay         [ 400 ms ]
```

## Calibration

```text
Current calibration:
X: min ... max ...
Y: min ... max ...

[ Calibrate ]
[ Reset calibration ]

☐ Invert X
☐ Invert Y
```

## Diagnostics

```text
Device: Lenovo M14t
Vendor ID: ...
Product ID: ...
HID device: Pen and multitouch sensor

Input Monitoring: Granted
Accessibility: Granted

Raw X: ...
Raw Y: ...
TipSwitch: ...
Contact ID: ...

[ Start logging ]
[ Copy diagnostics ]
```

---

# 15. GUI Calibration

CLI-калибровка должна быть заменена нормальной полноэкранной calibration overlay.

При нажатии `Calibrate`:

1. Определить target M14t display.
2. Открыть borderless fullscreen overlay именно на нём.
3. Показать calibration targets последовательно.

Например:

```text
┌─────────────────────────────────────┐
│ ●                                   │
│                                     │
│                                     │
│                                     │
│                                     │
│                         Touch here  │
└─────────────────────────────────────┘
```

Порядок:

1. top-left;
2. top-right;
3. bottom-right;
4. bottom-left;
5. optional center verification.

Каждую точку пользователь должен реально нажать.

Не просто «touch all corners while auto-learning min/max».

Лучше собрать реальные raw координаты каждой calibration point и вычислить mapping.

После calibration:

- показать test screen;
- пользователь двигает пальцем;
- UI показывает marker;
- кнопки `Save` / `Retry`.

Calibration сохраняется per-device/per-display configuration.

---

# 16. Calibration math

Текущая реализация min/max может использоваться как fallback.

Желательно улучшить модель, чтобы calibration была основана на известных точках экрана:

```text
rawPoint -> expectedScreenPoint
```

Минимальный вариант:

- определить raw min/max из 4 углов;
- учитывать display bounds;
- учитывать invert X/Y.

В будущем можно использовать affine transform, если выяснится, что простой linear mapping недостаточно точный.

Калибровку необходимо покрыть unit tests.

---

# 17. Display detection

Нельзя навсегда предполагать:

```text
displayIndex = 1
```

Нужно:

- перечислять дисплеи;
- позволять выбрать target display;
- сохранять selection;
- при reconnect пытаться сопоставить тот же display;
- корректно учитывать отрицательные координаты macOS desktop space.

Пример реальной конфигурации:

```text
MacBook display:
1800 × 1169 @ (0, 0)

M14t:
1920 × 1080 @ (-1920, -231)
```

Mapping должен корректно работать с таким расположением.

---

# 18. Device detection

По возможности определять M14t по:

- vendor ID;
- product ID;
- HID descriptor;
- product/manufacturer string.

Нельзя полагаться только на строку `"Pen and multitouch sensor"`.

Если точные VID/PID неизвестны, добавить diagnostic tooling для их получения.

Архитектура в будущем должна позволять поддержку других USB touchscreens.

---

# 19. Permissions

Приложению нужны:

### Accessibility

Для отправки synthetic mouse/scroll events.

### Input Monitoring

Для чтения HID input.

GUI должен показывать status:

```text
Accessibility     ✅ Granted
Input Monitoring  ❌ Required
```

И иметь:

```text
[ Open System Settings ]
```

После изменения permissions приложение должно корректно повторно проверить статус.

Не использовать Terminal для нормального пользовательского flow.

---

# 20. Start at Login

Вместо ручного LaunchAgent желательно использовать современный macOS API:

`SMAppService`

если он подходит для deployment target.

Пользователь должен управлять этим через:

```text
☑ Start at Login
```

Не создавать shell scripts/LaunchAgents для обычного GUI flow, если нативный API подходит.

Старый CLI installer можно сохранить для development/debug.

---

# 21. Persistence

Использовать `UserDefaults`, JSON или другой простой способ.

Настройки:

```swift
struct AppSettings {
    var enabled: Bool
    var mode: TouchMode
    var targetDisplay: ...
    var oneFingerScrollEnabled: Bool
    var naturalScroll: Bool
    var scrollSensitivity: Double
    var tapEnabled: Bool
    var tapThreshold: Double
    var longPressDragEnabled: Bool
    var longPressDelay: Double
    var invertX: Bool
    var invertY: Bool
}
```

Calibration лучше хранить отдельно от UI preferences.

---

# 22. Gesture state machine

Нужно сделать explicit state machine.

Пример:

```swift
enum GestureState {
    case idle
    case possibleTap
    case scrolling
    case waitingForLongPress
    case dragging
}
```

Пример алгоритма:

```text
finger down
    ↓
possibleTap
    │
    ├─ release quickly + little movement
    │      → tap
    │
    ├─ movement > scrollThreshold
    │      → scrolling
    │
    └─ time > longPressDelay
           → dragging
```

Конфликт scroll vs drag должен быть решён однозначно.

После того как state перешёл в `scrolling`, он не должен стать `dragging` до следующего touch sequence.

---

# 23. Scroll event generation

Использовать `CGEvent` scroll wheel.

Предпочтительный вариант:

```swift
CGEvent(
    scrollWheelEvent2Source: ...,
    units: .pixel,
    wheelCount: ...,
    wheel1: ...,
    wheel2: ...,
    wheel3: ...
)
```

Проверить знак `deltaY` на реальном устройстве.

Не hardcode направление — использовать `naturalScroll`.

Добавить filtering/smoothing, если raw touch produces jitter.

Например:

```text
raw delta
↓
dead zone
↓
sensitivity
↓
optional low-pass smoothing
↓
CGEvent scroll
```

Не добавлять сложную momentum physics в MVP.

---

# 24. Performance

Touch processing должен:

- не блокировать main UI thread;
- иметь низкую latency;
- не создавать отдельный object/event allocation без необходимости;
- не опрашивать устройство polling-циклом, если IOHID callbacks достаточно.

UI updates для diagnostics должны throttled, чтобы high-frequency HID events не перегружали SwiftUI.

---

# 25. Thread safety

HID callbacks могут выполняться не на main queue.

Необходимо явно определить threading model.

Например:

```text
HID callback queue
    ↓
TouchEngine serial queue
    ↓
GestureRecognizer
    ↓
EventEmitter
```

UI state публиковать на MainActor.

---

# 26. Logging

Добавить logging levels:

```text
error
warning
info
debug
trace
```

В production не логировать каждый touch point по умолчанию.

Diagnostics mode может включать raw event logging.

Не сохранять бесконечно растущий лог.

---

# 27. Testing

Минимально обязательные unit tests:

### CoordinateMapper

- all corners;
- center;
- negative display origin;
- clamping;
- invert X;
- invert Y;
- non-1920x1080 display.

### GestureRecognizer

Tap:

```text
down → up
=> tap
```

Small jitter:

```text
down → tiny move → up
=> tap
```

Scroll:

```text
down → move past threshold
=> scroll
```

Gesture lock:

```text
scroll started
→ long press timeout
=> still scroll, not drag
```

Drag:

```text
down → wait longPressDelay → move
=> dragBegin + dragMove
```

Release drag:

```text
dragging → up
=> dragEnd
```

### Settings

- persistence;
- default values.

### Calibration

- save/load;
- reset;
- raw→display mapping.

---

# 28. MVP / Version plan

## v0.1 — Refactoring

Цель: не менять поведение, но подготовить архитектуру.

- fork/import current repository;
- сохранить исходный touch → mouse mode;
- вынести HID reading;
- вынести gesture layer;
- вынести event emitter;
- unit tests;
- сохранить CLI для debug.

Definition of Done:

```text
Поведение текущего драйвера не сломано.
Architecture позволяет добавить новый touchscreen mode.
swift test проходит.
```

---

## v0.2 — Touchscreen scrolling

- tap → click;
- one-finger scroll;
- long press → drag;
- gesture state machine;
- natural scroll;
- configurable sensitivity;
- mouse mode remains available.

Definition of Done:

В Safari/Chrome:

- короткий tap нажимает link/button;
- vertical swipe скроллит страницу;
- text не выделяется во время обычного scroll;
- cursor не таскается за пальцем во время scrolling;
- long press + move может drag элемент.

---

## v0.3 — macOS GUI

- SwiftUI app;
- menu bar;
- settings window;
- enable/disable;
- mode;
- scrolling settings;
- display selection;
- permission status.

---

## v0.4 — GUI Calibration

- fullscreen calibration overlay;
- four calibration points;
- save/retry;
- reset;
- visual verification.

---

## v0.5 — Background operation

- Start at Login;
- reconnect M14t without restarting application;
- gracefully handle unplug/replug;
- no Terminal dependency;
- notifications/status.

---

## v0.6 — Diagnostics + stability

- device info;
- VID/PID;
- raw HID viewer;
- logs;
- crash/error handling;
- settings migration.

---

## v1.0

Definition of Done:

- standalone `.app`;
- stable on Apple Silicon;
- M14t reconnect works;
- touchscreen mode usable daily;
- GUI calibration;
- one-finger scrolling;
- tap;
- drag;
- mouse compatibility mode;
- persistent settings;
- starts at login;
- no Terminal required after installation.

---

# 29. Phase 2

После стабильного v1.0:

- two-finger scroll;
- two-finger tap → right click;
- better multi-contact tracking;
- pen support;
- pressure support;
- stylus buttons;
- eraser;
- additional touchscreen models.

---

# 30. UX acceptance tests

## Browser scrolling

Открыть длинную страницу в Safari или Chrome.

Expected:

```text
finger swipe vertically
→ page scrolls smoothly
→ no text selection
→ no accidental drag
```

---

## Tap

Нажать кнопку или ссылку.

Expected:

```text
short tap
→ exactly one click
```

Не должно быть double click или drag.

---

## Scroll followed by tap

```text
scroll page
release finger
tap button
```

Expected:

- scroll ends cleanly;
- next tap becomes click;
- gesture state does not leak.

---

## Multi-display

M14t расположен слева от MacBook.

Expected:

- touch always affects M14t coordinates;
- no jump to built-in display;
- negative desktop coordinates handled correctly.

---

## Disconnect/reconnect

1. App running.
2. Unplug M14t.
3. Reconnect.

Expected:

- app does not crash;
- status changes to Disconnected;
- device reconnects automatically;
- old calibration restored.

---

# 31. Non-goals для первой версии

Не делать в MVP:

- kernel extension;
- custom USB driver;
- private macOS APIs;
- App Store release;
- Windows/Linux support;
- complex gesture engine comparable to trackpad;
- handwriting recognition;
- virtual keyboard;
- advanced pen pressure curves;
- custom inertia physics;
- support every generic touchscreen.

---

# 32. Coding requirements

- Swift.
- Prefer modern Swift compatible with current stable Xcode.
- Deployment target: macOS 13+ unless a newer API provides major advantage.
- SwiftUI for UI.
- AppKit/CoreGraphics/IOKit where required.
- Avoid third-party dependencies unless there is a strong reason.
- Keep Core logic testable without attached hardware.
- No giant god classes.
- No UI logic inside HID callbacks.
- No CGEvent generation inside gesture recognition.
- No hardcoded display index.
- No hardcoded raw M14t calibration values.

---

# 33. Agent workflow

При работе AI coding agent должен:

1. Сначала изучить существующий repository.
2. Не переписывать рабочую HID implementation без причины.
3. Перед крупным refactor описать план.
4. Делать изменения маленькими commit-sized этапами.
5. После каждого этапа запускать:

```bash
swift test
swift build
```

6. Не менять несколько независимых подсистем одновременно.
7. Для неизвестных HID usages сначала добавить diagnostics, а не угадывать.
8. Не использовать private macOS API без отдельного обсуждения.
9. Любые предположения о gesture semantics подтверждать тестами.
10. Сохранять working mouse mode как fallback.

---

# 34. Первый этап для агента

Первое задание агенту:

> Изучи текущий `m14t-touch-macos`. Не добавляй GUI и новые gestures сразу. Сначала подготовь архитектурный refactor так, чтобы HID input был отделён от gesture interpretation и event emission.
>
> Сохрани полностью текущее поведение как `Mouse Mode`.
>
> Введи модели `TouchPoint`, `TouchFrame`, `InputAction`, протокол/компонент `GestureRecognizer` и `EventEmitter`.
>
> После refactor текущий CLI должен продолжить работать так же, как до refactor.
>
> Добавь unit tests для нового gesture/input слоя.
>
> После выполнения покажи diff/список изменённых файлов и объясни новую data flow architecture.

---

# 35. Важная продуктовая идея

Проект не должен пытаться сделать из macOS систему с native touchscreen API, которого приложения ожидают как на Windows/iPadOS.

Цель — создать **качественный translation layer**:

```text
physical finger gestures
        ↓
gesture recognition
        ↓
best matching public macOS input events
```

То есть добиться естественного UX через:

- click;
- scroll;
- drag;
- right click;
- другие доступные public events.

Главный критерий качества:

> Пользователь должен воспринимать M14t как сенсорный экран, а не как огромный абсолютный touchpad, который просто двигает стрелку мыши.
