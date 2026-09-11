# ТЗ: поддержка стилуса Lenovo ThinkVision M14t на macOS

## 1. Цель

Расширить `M14t Touch Manager` отдельной подсистемой для активного стилуса Lenovo ThinkVision M14t.

Ключевой принцип: **Pen и Finger — разные типы ввода и не должны проходить через один и тот же gesture pipeline.**

Цель Pen-подсистемы:

- корректный hover;
- абсолютное позиционирование на M14t;
- tip contact;
- поддержка физических кнопок стилуса;
- pressure, если он реально доступен и его можно корректно передать приложениям macOS;
- palm rejection;
- отдельные Pen Settings;
- отдельная Pen Calibration при необходимости;
- отсутствие конфликтов с finger touch, cursor hiding и mouse input.

Этот документ дополняет основное ТЗ проекта.

---

## 2. Важное правило: сначала исследование, потом реализация

Агент **не должен предполагать**, что конкретная возможность работает только потому, что:

- она есть на Windows;
- она указана в HID Usage Tables;
- она существует в CoreGraphics/CoreHID API;
- Lenovo заявляет поддержку пера.

Перед реализацией каждой расширенной функции нужно подтвердить две вещи:

1. конкретный M14t + конкретный стилус реально отдают нужные HID-данные на macOS;
2. существует рабочий способ корректно использовать/передать эти данные в macOS.

Особенно это относится к:

- pressure;
- tilt;
- eraser;
- barrel buttons;
- tablet pointer events;
- proximity;
- stylus-specific cursor feedback.

---

## 3. Известный baseline на текущем драйвере

Уже наблюдается:

- M14t виден как `Pen and multitouch sensor`;
- стилус работает в hover: если держать его на расстоянии от M14t и двигать, системная стрелка двигается;
- физического касания для hover не требуется;
- если стрелка до начала работы стилусом находится на дисплее MacBook, текущее поведение может продолжать двигать её на MacBook, хотя стилус находится около M14t;
- на стилусе есть физические кнопки.

Это **не эталон правильного поведения**, а исходная точка для диагностики.

---

## 4. Архитектура

Не делать:

```text
M14t HID
   ↓
общий GestureRecognizer
   ↓
MouseEmitter
```

Должно быть:

```text
M14t HID
   ↓
InputClassifier
   ├── Finger
   │     ↓
   │  TouchGestureEngine
   │
   └── Pen
         ↓
      PenEngine
         ↓
      PenEventBackend
```

Finger pipeline отвечает за:

- tap;
- scroll;
- long press;
- drag;
- multi-touch;
- pinch;
- touch gestures.

Pen pipeline отвечает за:

- hover;
- absolute pointer positioning;
- tip down/up;
- pen movement;
- pressure;
- physical buttons;
- optional tilt/rotation/eraser;
- palm rejection ownership.

**Pen input никогда не должен случайно запускать finger tap/scroll/drag/pinch.**

---

# 5. Обязательный Pen Research Phase

До полноценной реализации Pen агент должен создать диагностический слой.

## 5.1 Какие HID-поля исследовать

Проверить наличие и фактическое поведение:

- X;
- Y;
- Tip Switch;
- In Range / proximity-related signal;
- Tip Pressure;
- Barrel Switch;
- Secondary Barrel Switch;
- Button Switch;
- другие button usages;
- Eraser;
- Contact Identifier;
- device/pointer type;
- Tilt X;
- Tilt Y;
- Azimuth;
- Altitude;
- Rotation/Twist;
- Barrel Pressure;
- Scan Time;
- relevant vendor-specific usages.

Для каждого найденного HID element сохранить/показывать:

```text
usage page
usage
logical min
logical max
physical min/max, если есть
raw value
normalized value
changed/not changed
```

Наличие enum в Apple API не считается доказательством поддержки железом.

---

# 6. Pen Diagnostics

Добавить отдельный diagnostic view.

Пример:

```text
Pen Diagnostics
────────────────────────
Device: ThinkVision M14t
VID: 0x....
PID: 0x....

State
In proximity: YES
Tip touching: NO

Position
Raw X: 18442
Raw Y: 9281
Mapped X: ...
Mapped Y: ...

Pressure
Raw: 2147
Logical range: 0 ... 4095
Normalized: 0.524

Buttons
Button 1: DOWN
Button 2: UP

Tilt X: ...
Tilt Y: ...
Rotation: ...
Eraser: ...

Last changed usage:
Digitizer / Barrel Switch
```

Кнопки:

```text
[ Start Raw Logging ]
[ Stop Logging ]
[ Copy Report ]
[ Export Report ]
```

Высокочастотные HID events не должны заставлять SwiftUI перерисовываться на каждый sample. Diagnostics UI необходимо throttling.

---

# 7. Обязательные ручные hardware tests

## Test A — Hover

1. Поднести стилус к M14t, не касаясь.
2. Медленно двигать по экрану.
3. Удалять от поверхности до прекращения detection.

Определить:

- есть ли отдельный `inRange/proximity`;
- меняются ли X/Y в hover;
- насколько далеко работает hover;
- существует ли явное событие выхода из proximity.

## Test B — Tip

1. Войти в hover.
2. Коснуться экраном кончиком.
3. Поднять.

Зафиксировать:

```text
outOfRange → hover → tipDown → tipUp → hover → outOfRange
```

Проверить наличие отдельного TipSwitch.

## Test C — Pressure

Если pressure найден:

- слабое касание;
- среднее;
- сильное.

Проверить:

- raw range;
- logical range;
- monotonicity;
- jitter;
- dead zone;
- реальное достижение верхней части диапазона.

Не hardcode `4095`.

## Test D — Physical buttons

Для каждой кнопки:

1. нажать в hover;
2. отпустить;
3. нажать при tipDown;
4. удерживать;
5. попробовать комбинации кнопок.

Нужно определить **точный HID usage каждой физической кнопки**.

## Test E — Tilt

Наклонять стилус в разных направлениях.

Если соответствующие values не изменяются — tilt считать unsupported.

## Test F — Eraser

Если конструкция стилуса это допускает — проверить противоположный конец.

Если отдельный eraser usage отсутствует — не заявлять аппаратный eraser.

---

# 8. Pen data model

Предлагаемая модель:

```swift
struct PenSample {
    let timestamp: TimeInterval

    let rawPosition: CGPoint
    let mappedPosition: CGPoint

    let inProximity: Bool
    let tipDown: Bool

    let pressure: Double?
    let buttons: PenButtonState

    let tiltX: Double?
    let tiltY: Double?
    let rotation: Double?

    let eraserActive: Bool?
}
```

Buttons лучше хранить как bitset/OptionSet, а не hardcode `button1/button2` на уровне HID.

Например:

```swift
struct PenButtonState: OptionSet {
    let rawValue: UInt32
}
```

---

# 9. Pen state machine

Минимально:

```swift
enum PenState {
    case outOfRange
    case hovering
    case touching
}
```

Transitions:

```text
outOfRange
   ↓ proximityEntered
hovering
   ↓ tipDown
touching
   ↓ tipUp
hovering
   ↓ proximityExited
outOfRange
```

Button state обрабатывается отдельно.

---

# 10. Главная семантика cursor для Pen

## Pen и Finger должны вести себя по-разному

Для Finger мы можем скрывать системную стрелку, если включена соответствующая Touch-настройка.

Для Pen **стрелка по умолчанию НЕ скрывается**.

Причина: hover — важная часть UX стилуса. Пользователь должен видеть точку наведения до касания экрана.

Default policy:

```text
Finger → cursor policy из Touch Settings
Pen    → cursor visible
Mouse  → normal macOS cursor
```

---

# 11. Исправление текущего hover behavior

Текущее наблюдаемое поведение, при котором stylus hover может продолжить двигать pointer на MacBook display, считается неправильным.

Pen positioning должен быть **absolute**, а не relative.

Не делать:

```text
pen delta
→ current mouse cursor + delta
```

Делать:

```text
raw pen X/Y
→ calibrated normalized coordinates
→ absolute desktop coordinate внутри M14t bounds
```

Пример:

```text
mouse cursor сейчас на MacBook

pen входит в proximity M14t
в точке x=1200, y=400

→ cursor должен перейти в соответствующую точку M14t
```

После этого hover двигает cursor по M14t.

---

# 12. Pen pointer appearance

Отдельная настройка:

```text
Pen Pointer

● System Cursor
○ System Cursor + Highlight
○ Pen Dot
○ Crosshair
```

Не все варианты обязательны в MVP.

## System Cursor

Обязательный fallback и default.

## Highlight

Желательная функция: click-through overlay marker на M14t.

Требования:

- не получает focus;
- не блокирует приложения под ним;
- click-through;
- появляется только при pen proximity;
- исчезает после proximity exit;
- находится на M14t;
- может быть отключён.

Не использовать private API без отдельного решения только ради кастомной картинки указателя.

---

# 13. CursorPolicyController

TouchEngine и PenEngine **не должны независимо вызывать hide/show cursor**.

Добавить централизованный controller.

Например:

```swift
enum PointerOwner {
    case mouse
    case finger
    case pen
}
```

Policy:

```text
mouse
→ cursor visible normally

finger
→ Touch cursor policy

pen
→ force visible / pen feedback enabled
```

Это обязательно, чтобы избежать гонки:

```text
TouchEngine: hide
PenEngine: show
TouchEngine: hide
...
```

---

# 14. Finger → Pen ownership transition

Если пользователь касается экраном пальцем, а затем стилус входит в proximity:

Recommended behavior:

1. корректно cancel текущий finger gesture;
2. закончить synthetic drag, если был;
3. восстановить cursor visibility;
4. `PointerOwner = pen`;
5. включить palm rejection, если он enabled;
6. начать обработку pen hover.

Не должно оставаться:

- mouseDown;
- drag state;
- hidden cursor;
- modifier key down;
- незавершённый gesture.

---

# 15. Palm Rejection

Очень важная функция.

Default, если proximity работает надёжно:

```text
☑ Ignore finger touches while pen is in proximity
```

Логика:

```text
pen proximity entered
→ Finger TouchEngine suspended for NEW contacts

pen proximity exited
→ Finger TouchEngine available again
```

Настройки в будущем:

```text
Ignore finger touches:
● While pen is in proximity
○ Only while pen touches screen
○ Never
```

Если finger contact был проигнорирован во время pen proximity, он не должен внезапно активироваться посреди того же физического касания после ухода стилуса. Нужно дождаться нового finger-down sequence.

---

# 16. Pen Calibration

Сначала проверить, совпадают ли raw X/Y ranges Finger и Pen.

Нельзя предполагать:

```text
TouchCalibration == PenCalibration
```

Если ranges/geometry совпадают — можно reuse общий transform.

Если отличаются — хранить:

```text
TouchCalibration
PenCalibration
```

Pen calibration выполняется через **tipDown**, а не hover.

Процесс:

1. target top-left;
2. target top-right;
3. target bottom-right;
4. target bottom-left;
5. optional center verification.

У каждой точки собрать несколько samples и использовать median/robust average.

После калибровки показать verification overlay.

---

# 17. Pressure

Lenovo заявляет active pen с pressure sensitivity, но приложение должно опираться на реальный HID descriptor конкретного устройства.

Normalization:

```text
(raw - logicalMin) / (logicalMax - logicalMin)
```

с clamp `0...1`.

Не hardcode:

- min = 0;
- max = 4095;
- 4096 possible values;
- pressure always present.

---

# 18. Исследование macOS Pen/Tablet event injection

Перед тем как делать pressure глобально, агент обязан проверить public API path.

Нужно исследовать documented CoreGraphics/AppKit/HID возможности, включая tablet pointer/proximity event types и tablet-related event fields.

Агент не должен заранее считать, что единственный вариант — обычные mouse events.

Создать isolated prototype и проверить:

- можно ли формировать tablet pointer event;
- можно ли задавать pressure;
- видит ли pressure наше тестовое приложение;
- видит ли pressure стороннее pressure-aware приложение;
- работает ли proximity;
- можно ли передать button state;
- возникают ли duplicate mouse/tablet events;
- нужны ли Accessibility permissions;
- какие ограничения есть cross-process.

Только после этого выбирать production backend.

---

# 19. PenEventBackend abstraction

Не связывать PenEngine напрямую с `CGEventCreateMouseEvent`.

```swift
protocol PenEventBackend {
    func handle(_ action: PenAction)
}
```

Варианты:

```text
TabletEventBackend
MouseFallbackBackend
DiagnosticsBackend
TestBackend
```

Research phase определит, какой backend usable.

---

# 20. PenAction

Пример:

```swift
enum PenAction {
    case hover(position: CGPoint)

    case tipDown(
        position: CGPoint,
        pressure: Double?
    )

    case tipMove(
        position: CGPoint,
        pressure: Double?
    )

    case tipUp(position: CGPoint)

    case buttonDown(
        button: PenButton,
        position: CGPoint
    )

    case buttonUp(
        button: PenButton,
        position: CGPoint
    )

    case proximityEntered
    case proximityExited
}
```

Raw HID code не должен генерировать system events напрямую.

---

# 21. Mouse fallback

Если tablet-aware injection не работает или несовместим с конкретным приложением:

```text
hover    → mouseMoved
tipDown  → leftMouseDown
tipMove  → leftMouseDragged
tipUp    → leftMouseUp
button   → configured action
```

Это fallback, а не основное архитектурное предположение.

При fallback cursor всё равно должен absolute-map на M14t.

---

# 22. Pressure test canvas

Добавить встроенный Pen Test Canvas.

Он нужен для проверки pipeline независимо от сторонних приложений.

Canvas должен:

- показывать hover marker;
- рисовать stylus path;
- отображать raw/mapped X/Y;
- показывать TipSwitch;
- показывать pressure;
- менять толщину линии по normalized pressure;
- показывать физические buttons;
- иметь `Clear`.

Если pressure работает в нашем canvas, это **ещё не означает**, что он работает глобально в сторонних приложениях.

---

# 23. Physical Pen Buttons

У стилуса есть кнопки. У них должны быть **отдельные настройки**.

Сначала diagnostics определяет:

- количество реально видимых кнопок;
- usage каждой;
- работают ли они в hover;
- работают ли они при tipDown;
- есть ли комбинации/различия.

Только после этого присвоить semantic names `Button 1`, `Button 2`.

---

# 24. Pen Buttons UI

Пример:

```text
Pen Buttons

Button 1
[ Right Click       ▼ ]

Button 2
[ Eraser            ▼ ]
```

Возможные mappings:

```text
None
Right Click
Middle Click
Double Click
Click and Hold
Eraser
Pan / Scroll
Undo
Redo
Command
Option
Shift
Control
Keyboard Shortcut…
```

Не всё обязательно в MVP.

---

# 25. Default button mappings

Не hardcode до hardware test.

После исследования можно предложить default-кандидат:

```text
кнопка ближе к tip → Right Click
вторая кнопка      → Eraser / configurable
```

Но только после того, как понятно, какая HID button соответствует какой физической кнопке.

---

# 26. Button behavior in hover

Если hardware сообщает button events при hover, нужно поддержать:

```text
pen hovering over object
↓
button mapped to Right Click
↓
right click exactly at current pen position
```

Касание tip не требуется, если hardware позволяет hover button.

---

# 27. Button + Tip conflict resolution

Нельзя допустить одновременно несовместимые actions.

Например:

```text
Button 2 = Eraser
Button 2 held + tipDown
→ erase action
```

Не должно одновременно отправляться:

```text
left click + erase
```

или:

```text
left + right mouse down
```

Нужен explicit `PenActionResolver`/conflict resolver.

---

# 28. Pressure curve settings

Только если pressure реально имеет практический output path.

MVP:

```text
Pressure Curve
● Linear
```

Future:

```text
○ Soft
○ Firm
○ Custom
```

Advanced:

- min activation pressure;
- max saturation;
- curve editor;
- preview canvas.

Не делать мёртвые pressure settings, если pressure невозможно использовать вне diagnostic canvas.

---

# 29. Pen Settings — отдельная вкладка

Пример:

```text
Pen
────────────────────────

Status
● Pen detected
● In proximity

Enable Pen
☑ Enabled

Pointer
[ System Cursor ▼ ]
☑ Show pen highlight

Hover
☑ Move pointer while hovering

Tip
☑ Tip performs primary action

Pressure
Status: Available / Unavailable / Untested
Range: ...
Curve: Linear

Buttons
Button 1 [ Right Click ▼ ]
Button 2 [ Eraser ▼ ]

Palm Rejection
☑ Ignore finger touches while pen is in proximity

Calibration
[ Calibrate Pen ]
[ Reset Pen Calibration ]

[ Open Pen Diagnostics ]
```

---

# 30. Не делать мёртвые настройки

Это важное правило проекта.

UI switch/slider появляется **только когда его значение реально влияет на runtime semantics**.

Примеры:

- не показывать Tilt Settings, пока tilt не обнаружен;
- не показывать Pressure Curve как active control, пока pressure backend не работает;
- не показывать Button 2, если второй button usage реально не найден;
- unsupported capability можно показать как status/info, но не как работающий toggle.

---

# 31. Pen + scrolling

По умолчанию pen movement не является finger scroll.

```text
hover move → pointer hover

tip move → pen stroke / drag / primary pen behavior
```

Но можно дать button mapping:

```text
Button + pen movement → Pan / Scroll
```

Это отдельная Pen-функция и не должна использовать Finger GestureRecognizer.

---

# 32. Pen + touch cursor hiding conflict

Если Finger Touch Mode использует global/private cursor hiding:

```text
finger begins
→ cursor may hide

pen enters proximity
→ cursor MUST be restored immediately
→ pointerOwner = pen
```

Пока pen в proximity, Touch subsystem не имеет права снова скрывать cursor.

После выхода pen:

- не скрывать cursor автоматически;
- Touch policy применяется при следующем новом finger sequence.

---

# 33. Private API policy для Pen

Основное правило проекта остаётся:

- public API first;
- private API только после доказанного ограничения public API и отдельного решения.

Исключение, которое может быть разрешено проектом для **global cursor visibility**, не означает автоматического разрешения private APIs для pen/tablet injection.

Если для pressure/tablet events public API недостаточно, агент должен:

1. описать конкретное ограничение;
2. показать результаты prototype;
3. предложить public fallback;
4. отдельно запросить решение по private API.

---

# 34. macOS compatibility matrix

После prototype проверить минимум:

```text
Application         Hover   Tip   Drag   Pressure   Buttons
──────────────────────────────────────────────────────────
Internal TestCanvas
Finder
Safari/Chrome
Preview/Markup
Freeform
Krita/другая pressure-aware app
```

Не заявлять поддержку стороннего приложения без теста.

---

# 35. Disconnect / reconnect

При disconnect M14t:

- active pen stroke корректно завершить;
- synthetic mouse buttons release;
- synthetic keyboard modifiers release;
- proximity = false;
- button states reset;
- pointer owner reset;
- cursor visibility restored;
- status = disconnected.

После reconnect:

- rediscover HID collections;
- восстановить settings;
- восстановить calibration;
- не требовать restart приложения.

---

# 36. Performance

Pen path должен быть low latency.

Не делать:

```text
HID event
→ MainActor
→ SwiftUI
→ PenEngine
```

Делать:

```text
IOHID callback
↓
Pen processing serial queue / actor
↓
CoordinateMapper
↓
PenEngine
↓
PenEventBackend
```

Diagnostics UI получает throttled snapshot.

---

# 37. Jitter filtering

Hover может дрожать.

Допустим лёгкий filtering:

```text
raw X/Y
↓
small dead-zone
↓
optional EMA/low-pass
↓
mapped coordinate
```

Но нельзя жертвовать заметной latency ради smoothing.

Pen smoothing и Finger smoothing — отдельные параметры/алгоритмы.

---

# 38. Unit tests

Обязательные tests.

## PenState

```text
outOfRange → proximity → hovering
hovering → tipDown → touching
touching → tipUp → hovering
hovering → proximityExit → outOfRange
```

## Absolute mapping

```text
cursor is on MacBook
pen enters M14t proximity
→ mapped result belongs to M14t bounds
```

## Cursor policy

```text
Finger owner + cursor hidden
Pen proximity enters
→ owner = Pen
→ cursor visible
```

## Palm rejection

```text
Pen proximity active
Finger down
→ Finger sequence ignored
```

```text
Finger scroll active
Pen enters proximity
→ Finger sequence cancelled cleanly
```

## Buttons

- down exactly once;
- hold does not repeat click accidentally;
- release cleans state;
- disconnect while held cleans state.

## Pressure

- normalize by descriptor min/max;
- clamp;
- unsupported → nil;
- zero-range descriptor safe;
- pressure itself does not replace TipSwitch if TipSwitch works.

---

# 39. Pen Research report

Research Phase должен закончиться созданием:

```text
M14t_PEN_CAPABILITIES.md
```

Формат:

```text
# Hardware / HID

Hover X/Y: SUPPORTED
TipSwitch: SUPPORTED
Pressure: SUPPORTED / UNSUPPORTED / UNTESTED
Button 1: ...
Button 2: ...
Tilt: ...
Eraser: ...

# Ranges

X: ...
Y: ...
Pressure: ...

# Behavior

Proximity: ...
Buttons in hover: ...
...

# macOS event prototype

Tablet pointer event: WORKS / PARTIAL / FAILED
Pressure received by internal app: ...
Pressure received by external app: ...
Mouse fallback: ...

# Recommended production implementation
...
```

Каждая поддерживаемая capability должна быть подтверждена наблюдением/test log.

---

# 40. Development phases

## Pen v0.1 — Diagnostics

- enumerate pen HID collections;
- distinguish Pen vs Finger;
- raw usages/ranges;
- live diagnostics;
- manual test procedure;
- `docs/M14t_PEN_CAPABILITIES.md`.

Никакой speculative pressure injection.

## Pen v0.2 — Pen Core

- `PenSample`;
- `PenState`;
- `PenAction`;
- input classification;
- tests.

## Pen v0.3 — Correct Hover

- absolute M14t mapping;
- cursor moves to M14t on proximity;
- cursor visible;
- no Finger GestureRecognizer involvement.

## Pen v0.4 — Tip + Buttons

- tip down/move/up;
- physical buttons;
- configurable actions;
- conflict resolver.

## Pen v0.5 — Palm Rejection + Cursor Policy

- centralized `CursorPolicyController`;
- Pen ownership;
- finger cancellation;
- palm rejection.

## Pen v0.6 — Pressure Prototype

- normalize pressure;
- internal test canvas;
- tablet event investigation;
- compatibility matrix.

## Pen v0.7 — Pen Settings

- separate Pen tab;
- pointer feedback;
- buttons;
- calibration;
- diagnostics;
- only live/real settings.

## Pen v1.0

- stable hover;
- tip;
- physical buttons;
- correct M14t absolute mapping;
- cursor remains useful/visible;
- palm rejection;
- calibration;
- reconnect;
- no stuck synthetic state;
- pressure only if verified.

---

# 41. Definition of Done — Pen MVP

Pen MVP считается готовым, когда:

- stylus автоматически определяется;
- Pen и Finger различаются;
- hover работает;
- hover позиционирует pointer именно на M14t;
- положение старой mouse cursor на MacBook не влияет на Pen mapping;
- cursor для Pen остаётся видимым;
- tip работает;
- physical buttons определены и настраиваются;
- finger gestures не запускаются Pen-событиями;
- palm rejection работает при надёжном proximity;
- finger cursor hiding не конфликтует с Pen;
- Pen calibration сохраняется;
- disconnect/reconnect корректны;
- нет stuck mouse buttons/modifiers;
- diagnostics показывает реальный HID state.

Pressure в third-party apps входит в Definition of Done только после подтверждённого рабочего event path.

---

# 42. Вопросы, на которые агент обязан ответить до полноценной Pen implementation

1. Какие точные HID collections принадлежат Pen, а какие Finger?
2. Какие exact usage page/usage используются для X/Y?
3. Есть ли надёжный proximity/inRange signal?
4. Какой raw/logical range у X/Y?
5. Есть ли TipSwitch?
6. Есть ли TipPressure и какой у него реальный range?
7. Сколько физических button usages реально видно?
8. Какая физическая кнопка соответствует какому HID usage?
9. Работают ли кнопки в hover?
10. Есть ли Tilt X/Y?
11. Есть ли Eraser?
12. Совпадают ли Pen и Finger calibration ranges?
13. Можно ли public API средствами сформировать tablet-aware event?
14. Можно ли передать pressure receiving app?
15. Какие приложения реально воспринимают synthetic tablet data?
16. Возникают ли duplicate mouse/tablet events?
17. Какие permissions реально нужны?
18. Какой backend выбрать для production?
19. Какой fallback использовать для non-tablet-aware apps?
20. Как гарантировать отсутствие конфликта Pen vs Finger cursor policies?

---

# 43. Первый prompt для coding agent

> Реализуй только **Pen Research / Diagnostics Phase** из `docs/spec/M14t_Pen_TZ.md`. Не реализовывай speculative pressure injection, tilt behavior, eraser behavior, button mappings или private tablet APIs до получения фактических данных устройства.
>
> Сначала изучи существующий HID код проекта и определи, как сейчас обрабатывается `Pen and multitouch sensor`.
>
> Сохрани существующее Touch поведение.
>
> Отдели Pen-related HID events от Finger events настолько, насколько это необходимо для диагностики. Pen events не должны проходить через Finger GestureRecognizer.
>
> Добавь diagnostics, которые показывают для relevant HID elements: usage page, usage, logical min/max, raw value и изменения значения. Отдельно отобрази X/Y, TipSwitch, proximity/InRange, TipPressure, все button-related usages, Eraser, Tilt/Rotation и Contact ID, если они реально существуют.
>
> После этого попроси пользователя пройти manual tests: hover, tip, pressure, каждая физическая кнопка, tilt и eraser.
>
> На основании фактического лога создай `docs/M14t_PEN_CAPABILITIES.md` с таблицей поддерживаемых/неподдерживаемых/непроверенных возможностей, диапазонами HID значений и рекомендацией следующего шага.
>
> Не считать capability поддерживаемой только потому, что соответствующий HID enum/API существует.
>
> Не начинать production pressure/tablet event injection до завершения capability report.

