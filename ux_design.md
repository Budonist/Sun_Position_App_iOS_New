<screens>

## Architecture notes (binding)
- Add the local Swift Package at /home/ubuntu/sonnenschein/ as a dependency. Import SolarEngine, ShadowEngine and Geodata. Do NOT reimplement any algorithm.
- The bundled geodata (~5-10 MB) is loaded from the app bundle via the Geodata package. Load it once at launch on a background task.
- No network, no account, no persistence. Location permission is requested only when the user taps the location button.

### File layout
- App/
  - SonnenscheinApp.swift: @main entry.
  - RootView.swift: NavigationStack containing MapScreen.
  - AppModel.swift: @Observable state.
- Features/Map/
  - MapScreen.swift
  - MapViewModel.swift
  - LocationProvider.swift: CLLocationManager wrapper.
- Features/SolarResult/
  - SolarResultSheet.swift
  - SolarResultViewModel.swift
  - SolarComputationService.swift: actor wrapping the engines.
  - SolarResultModels.swift
- Features/DayTimeline/
  - DayTimelineView.swift
  - TimelineSegment.swift
- Features/DateTimePicker/
  - DateSelectorView.swift
  - CustomDateSheet.swift
  - TimeSliderView.swift
- DesignSystem/
  - Theme.swift
  - StatusBadge.swift
  - Formatters.swift: de_DE, Europe/Berlin.
- Debug/
  - DebugPanelView.swift
  - DebugInfo.swift
  - All wrapped in #if DEBUG.
- Tests/
  - SolarComputationServiceTests: inside-building, outside-area, night and timeline-merge cases.
  - FormattersTests.

### Computation layer (SolarComputationService, an actor)
- init: loads the Geodata store and spatial index via the package API, off the main thread. Exposes `isReady`.
- `func evaluate(lat: Double, lon: Double, at date: Date) async throws -> PointResult`
  1. Check coverage: is the point inside the PLZ 10961 coverage polygon/bounds supplied by Geodata? If not, throw `.outsideArea`.
  2. Convert to ENU and get the ground elevation. If there is no terrain or building data for the cell, throw `.noData`.
  3. If the point lies inside a building footprint, throw `.insideBuilding`.
  4. Observer = ground + 1.2 m.
  5. Get the sun position from SolarEngine. Elevation <= 0 means `.night`.
  6. Otherwise ray-cast with ShadowEngine toward the sun: hit = `.shadow`, no hit = `.sun`.
  7. Return the status plus DebugInfo.
  - Target: < 200 ms.
- `func analyzeDay(lat: Double, lon: Double, day: Date) async throws -> DayAnalysis`
  1. Get sunrise/sunset from SolarEngine (timezone Europe/Berlin).
  2. Sample every 1 min from sunrise to sunset and run the ray test at each step.
  3. Merge consecutive equal states into segments. Add night segments for 00:00 to sunrise and sunset to 24:00.
  4. Refine each transition by bisection to 10 s precision.
  - Call `Task.checkCancellation()` every 20 samples.
  - Target: < 2 s.
- Models:
  - `PointStatus` enum: sun, shadow, night.
  - `PointResult`: status, sunAzimuth, sunElevation, debug: DebugInfo.
  - `TimelineSegment`: start: Date, end: Date, kind: sun | shadow | night.
  - `DayAnalysis`: sunrise: Date?, sunset: Date?, segments: [TimelineSegment].
  - `ComputationError`: outsideArea, insideBuilding, noData, engineNotReady.
  - `DebugInfo`: lat, lon, groundElevation, solarAzimuth, solarElevation, observerHeight (1.2), checkedBuildingCount, blockingBuildingId: String?, intersectionDistance: Double?, computationMs: Double, dataSource: "Amtliches Berliner LoD2".
  - Map the package's real public API onto these models; field names here are the app-side contract.
- Polar-day/night handling: if sunrise is nil, the whole day is a single night or sun-check segment as the engine reports.

### State (AppModel, @Observable, @MainActor)
- `selectedCoordinate: CLLocationCoordinate2D?`
- `selectedDay: Date`: start of day, Europe/Berlin; default today.
- `selectedTime: Date`: default now, clamped.
- `pointState`: `idle | loading | result(PointResult) | error(ComputationError)`
- `dayState`: `idle | loading | loaded(DayAnalysis) | error`
- `showsLoadingIndicator: Bool`: set true only if a computation exceeds 300 ms. A delayed Task sets it and completion cancels that Task.
- `pointTask` / `dayTask`: Task handles.
  - On a new coordinate or day, cancel both and start new ones.
  - On a slider change, cancel only `pointTask` and start a new one. Debounce 16 ms (one frame), then compute.
  - Results are applied on the main actor only if the request id matches the latest request.
- Next-change text is derived from `DayAnalysis.segments` and `selectedTime`: find the segment containing selectedTime, then:
  - Sun → "Sonne bis HH:mm"
  - Shadow → "Sonne ab HH:mm" (start of the next sun segment), or "Heute keine Sonne mehr" if none follows.
  - Night before sunrise → "Sonnenaufgang um HH:mm"
  - Night after sunset → "Sonnenuntergang war um HH:mm"

---

## 1. MapScreen (root)
**Purpose:** Pick a point and see the result instantly.

**Layout:**
- Full-bleed SwiftUI `Map`, map style `.standard(elevation: .realistic, pointsOfInterest: .excludingAll)`.
- Initial camera: center 52.4935, 13.4040 (Kreuzberg 10961), distance ~2500 m.
- PLZ 10961 coverage outline drawn as a `MapPolyline`: brand colour, 2 pt, 60% opacity. The polygon comes from Geodata.
- **Top floating capsule (DateTimeHeader):**
  - Left: weekday + date, e.g. "Mi., 18. Juni".
  - Right: selected time in monospaced digits, e.g. "14:32", plus a "Jetzt" chip when the selected time is not the current time.
  - Tapping the date part opens DateSelector (inside the sheet, see 2).
- **Bottom-right floating buttons** (44 pt circles, surface colour):
  - `location` symbol: "Mein Standort". Requests when-in-use permission on first tap. Enables `UserAnnotation` and recenters.
  - `scope` symbol: "Auf 10961 zentrieren".

**Interaction:**
- Use `MapReader` + `onTapGesture` → `proxy.convert(point, from: .local)` → set `selectedCoordinate`.
- Show an `Annotation` marker at the coordinate: a 28 pt circle filled with the status colour (sun yellow / shadow slate / night black / neutral gray when loading or error) with a white 2 pt stroke and a status SF Symbol inside.
- The marker scales in from 0.6 → 1.0 with a spring; under Reduce Motion it uses opacity only.
- Long-press is not used.

**Empty state (no point yet):** the sheet shows the hint card (see 2).

**Location denied:** show a non-blocking banner in the sheet: "Standortzugriff ist deaktiviert. Du kannst ihn in den Einstellungen erlauben." with an "Einstellungen" button that opens `UIApplication.openSettingsURLString`.

**Engine still loading at launch:** the sheet shows a ProgressView with "Gebäudedaten werden geladen …". Map taps still place the marker and evaluation runs once the engine is ready.

## 2. SolarResultSheet (persistent bottom sheet)
**Presentation:**
- Attached to MapScreen via `.sheet(isPresented: .constant(true))`.
- `.presentationDetents([.height(140), .medium, .large])`, default .height(140), auto-raised to .medium on the first point selection.
- `.presentationBackgroundInteraction(.enabled(upThrough: .medium))` so the map stays tappable.
- `.interactiveDismissDisabled()`, `.presentationCornerRadius(24)`.
- Has its own NavigationStack only to push DebugPanelView; no other pushes.

**Content (ScrollView, top to bottom):**
1. **StatusBadge (large):**
   - 64 pt symbol tile + title (Title weight).
   - `.sun`: symbol `sun.max.fill` on a sun-yellow tile, title "Direkte Sonne".
   - `.shadow`: symbol `building.2.fill` on a slate tile, title "Gebäudeschatten".
   - `.night`: symbol `moon.stars.fill` on a night tile, title "Nacht – Sonne unter dem Horizont".
   - Subtitle: the next-change text, e.g. "Sonne bis 18:12".
   - VoiceOver combines everything into one element: "Direkte Sonne. Sonne bis 18 Uhr 12."
2. **TimeSliderView:**
   - Label "Uhrzeit" + current value.
   - Slider from sunrise to sunset of selectedDay in 1-min steps. Track tinted with the timeline segments (DayTimelineView rendered behind a transparent Slider).
   - End labels show sunrise (`sunrise` symbol + time) and sunset (`sunset` symbol + time).
   - "Jetzt" button sets now (enabled only when selectedDay is today and now lies between sunrise and sunset; otherwise it sets today+now).
   - Selection haptic only when crossing a sun/shadow boundary.
   - accessibilityValue = "14:32, Direkte Sonne". accessibilityAdjustableAction moves ±15 min.
3. **DayTimelineView (section "Tagesverlauf")** — see 3.
4. **Sun windows list:**
   - Rows for each sun segment: `sun.max` + "09:41 – 12:03" + duration "2 Std. 22 Min.".
   - Shadow segments shown as secondary rows with `building.2`.
   - Footer total: "Insgesamt 6 Std. 10 Min. Sonne".
   - If there are no sun segments: "An diesem Tag erreicht kein direktes Sonnenlicht diesen Punkt."
5. **DateSelectorView** — see 4.
6. **Attribution:**
   - Caption "Datenquelle: Amtliches Berliner LoD2 · Geoportal Berlin" + `info.circle`.
   - Caption "Beobachterhöhe 1,2 m über Boden".
7. **Debug row (#if DEBUG only):** "Debug-Informationen" → push DebugPanelView.

**Collapsed detent (.height(140)):** shows only a compact StatusBadge (32 pt tile + title + next-change text). With no point selected it shows the hint instead.

**States:**
- **Hint / empty (no point):** `hand.tap` symbol, "Tippe auf die Karte", secondary text "Wähle einen Ort in 10961 und sieh sofort, ob dort die Sonne scheint."
- **Loading:** content stays at the previous values with reduced opacity. A small ProgressView next to the title appears only if `showsLoadingIndicator`. Never show skeleton flashes for fast results.
- **Errors:** replace the StatusBadge with an info card (symbol + text, warning tint). Timeline, slider and list are hidden. Date selector stays visible.
  - insideBuilding: `building.fill` + "Dieser Punkt befindet sich innerhalb eines Gebäudes."
  - outsideArea: `mappin.slash` + "Außerhalb des unterstützten Gebiets." + secondary "Unterstützt wird derzeit nur das Gebiet der PLZ 10961." + button "Auf 10961 zentrieren".
  - noData: `questionmark.square.dashed` + "Für diesen Punkt liegen keine Gebäudedaten vor."
  - engine/unknown failure: `exclamationmark.triangle` + "Berechnung fehlgeschlagen." + "Erneut versuchen" button, which reruns both tasks.
- **Night (selected time outside sunrise–sunset):** the night StatusBadge is a valid result, not an error. The slider is clamped, so night appears when the date is changed and the time stays before/after the day window, or when "Jetzt" is at night. In that case show the selected time as the actual current time and display the night state.

## 3. DayTimelineView
- Horizontal capsule bar, height 20 pt, radius 6, full width.
- Spans 00:00–24:00 compressed: night segments shown at a fixed 8% width each side; sunrise→sunset fills the rest proportionally.
- Segment colours: sun = #F2B705, shadow = #4A5361, night = #121417.
- A 2 pt white needle with dark outline marks selectedTime.
- Time labels below: sunrise, 12:00 or solar noon, sunset, plus each transition time if there is ≥ 36 pt of space (otherwise skipped). Caption, monospaced digits.
- Legend row: three swatches "Sonne", "Schatten", "Nacht". Colour is never the only cue: legend + list.
- Tapping a segment sets selectedTime to that segment's midpoint.
- VoiceOver: the bar is one element with a summary label, e.g. "Tagesverlauf: Sonne 09:41 bis 12:03, Schatten 12:03 bis 15:37, Sonne 15:37 bis 18:12."
- Loading: the bar shows a neutral #E6E1D6 fill.

## 4. DateSelectorView + CustomDateSheet
- Segmented Picker with options "Heute" | "Morgen" | "Datum wählen".
- When a custom date is active, the third segment shows that date, e.g. "3. März".
- "Datum wählen" opens CustomDateSheet: its own NavigationStack, title "Datum wählen", `DatePicker(.graphical)` in de_DE, no range limit (past and future), toolbar "Fertig" / "Abbrechen", `.presentationDetents([.medium, .large])`.
- On date change:
  - Keep the same clock time, clamped into the new sunrise–sunset window.
  - Recompute the day analysis and the point.

## 5. DebugPanelView (#if DEBUG, pushed inside the sheet's NavigationStack)
- Grouped List titled "Debug" showing the DebugInfo fields:
  - Breite/Länge (6 decimals)
  - Geländehöhe (m)
  - Sonnenazimut (°)
  - Sonnenhöhe (°)
  - Beobachterhöhe (1,2 m)
  - Geprüfte Gebäude (count)
  - Blockierendes Gebäude (id or "–")
  - Schnittdistanz (m or "–")
  - Rechenzeit (ms, 1 decimal)
  - Datenquelle
- Also shows the timing of the last day analysis.
- Values are monospaced and selectable via `.textSelection(.enabled)`.
- Toolbar "Kopieren" copies all values to UIPasteboard.
- Optional `@AppStorage("debugOverlay")` toggle "Kompakt-Overlay auf Karte" shows a small monospaced box (azimuth, elevation, ms) top-left on the map.
</screens>

<navigation>
- No authentication; a single flow.
- RootView: NavigationStack { MapScreen } with a hidden navigation bar.
- SolarResultSheet is permanently presented over MapScreen. It has its own NavigationStack used only for push → DebugPanelView (DEBUG builds only; back pops).
- CustomDateSheet is presented from SolarResultSheet as a nested sheet with its own NavigationStack. "Fertig" applies and dismisses; "Abbrechen" dismisses.
- Map tap updates `selectedCoordinate`; the sheet content reacts to state. Nothing is pushed.
- The location permission prompt appears only on tapping "Mein Standort".
- No tabs, no other screens.
</navigation>

<design_direction>
**Audience and moment**
- Kreuzberg residents, café-goers and balcony gardeners checking "Is there sun at that spot, and until when?"
- Used outdoors, in daylight, often briefly.
- Feeling: bright, calm, precise and trustworthy, like a good weather app with an official-data backbone.

**First screen**
- The map of 10961 with the sheet collapsed.
- A returning user taps once and gets the answer at a glance: a big status line plus "Sonne bis 18:12".
- A first-time user sees the hint "Tippe auf die Karte". The first tap is the first success.

**References**
- Apple Weather: big glanceable status, timeline bar.
- Apple Maps: persistent detent sheet over the map.
- Sun Seeker / SunCalc: sun-window precision with time labels.

**Appearance**
- Light by default (outdoor daylight readability).
- Also support Dark Mode with adaptive colours, because maps get used at night.

**Palette (light / dark)**
- background: #FAF7F0 / #121417
- surface: #FFFFFF / #1E2126
- primary text: #1C1E21 / #F2F0EB
- secondary text: #5E6470 / #A5ABB5
- brand sun yellow: #F2B705. Used for fills only, never as text on light backgrounds; text/symbols on yellow use #1C1E21.
- accent shadow slate: #4A5361 (with white symbol)
- night: #121417 (in dark mode with a #3A3F48 border)
- warning/info card tint: #B5541B on #FBEFE6

**Typography (SF Pro)**
- display: 34 bold, status title in the large badge
- title: 22 semibold
- headline: 17 semibold
- body: 17 regular
- caption: 13 regular
- All times use `.monospacedDigit()`.
- Everything uses Dynamic Type text styles. At accessibility sizes the badge stacks vertically.

**Shape and depth**
- Radii: sheet 24, cards 16, symbol tiles 14, chips/capsules full.
- Flat grouped sections inside the sheet separated by 1 pt hairlines (#E6E1D6 / #2C3036).
- The only shadows are on the floating map controls and header capsule: y 2, blur 8, 12% black.

**Imagery**
- None beyond SF Symbols and the map.

**Components**
- Primary button: filled #1C1E21 with light text, 50 pt height, radius 14.
- Secondary button: bordered with a hairline, primary text.
- Chips ("Jetzt"): capsule, sun-yellow fill, dark text.
- List rows: 44 pt minimum height, symbol + text + trailing value.
- Info/error card: tinted background, symbol, text, optional button.
- Loading: inline small ProgressView only after 300 ms.
- Empty state: hint card.

**Theme file**
- DesignSystem/Theme.swift defines `Theme.Colors` (adaptive via `Color(light:dark:)` helper using UIColor traits), `Theme.Fonts`, `Theme.Spacing` (8 pt grid: 4, 8, 16, 24, 32), `Theme.Radius`, a `PrimaryButtonStyle`/`SecondaryButtonStyle` pair, `StatusBadge`, `InfoCard`.
- No literal colours or fonts in feature views.

**Localization**
- All strings in German via a String Catalog (de as development language).
- DateFormatter/Date.FormatStyle uses locale de_DE and timeZone Europe/Berlin regardless of the device timezone.
- Duration formatting: "2 Std. 22 Min.".

**Accessibility**
- Contrast ≥ 4.5:1 (dark text on yellow).
- Every status is shown as symbol + text.
- Touch targets are 44 pt.
- Map marker accessibilityLabel: "Gewählter Punkt, Direkte Sonne".
</design_direction>

<animation_and_motion>
- Status change: badge tile colour and symbol cross-fade (0.2 s) with `.contentTransition(.symbolEffect(.replace))`.
- Marker drop: spring scale.
- Timeline needle follows the slider with no animation lag.
- Haptics:
  - `.selection` when the slider crosses a sun/shadow boundary.
  - `.light` impact on marker placement.
- Reduce Motion: replace scale/spring with opacity fades and disable symbol effects.
- No decorative motion.
</animation_and_motion>