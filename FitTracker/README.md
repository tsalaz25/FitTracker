# FitTracker — Repo Details

A personal iOS fitness app combining a macro/micronutrient diary with a
workout planner and live logger. Built for one user, no backend, all data
stored locally on device.

**Requirements:** Xcode 26+, iOS 18+, a physical iPhone, and a free USDA
API key.

---

## 1. API Key Signup and Instructions

FitTracker pulls food data from the **USDA FoodData Central** API. It is
free, public domain, and the only free source with full micronutrient
panels.

### Get your key

1. Go to **https://fdc.nal.usda.gov/api-key-signup**
2. Enter your name and email. No payment, no account.
3. The key arrives by email within seconds.

### Add it to the project

Open `Backend/API.swift` and paste the key between the quotes:

```swift
enum API {
    static let usdaAPIKey = "PASTE_YOUR_KEY_HERE"
}
```

The **enum must be named `API`** — the filename itself doesn't matter,
but every call site references `API.usdaAPIKey`.

### Limits and troubleshooting

| Symptom | Cause |
|---|---|
| `403` / "Bad API key" | Key is wrong, still the placeholder, or has stray spaces |
| `429` / "Rate limited" | Over 1,000 requests/hour — wait an hour |
| "Cannot find 'API' in scope" | `API.swift` not in Target Membership |

If you push this project to GitHub, add `API.swift` to `.gitignore`.
USDA deactivates keys they find published in public repos.

### Exercise data (no key needed)

Exercises come from `Backend/exercises.json`, a bundled copy of the
public-domain `free-exercise-db` (~800 exercises). No network call, no
key, works offline at the gym. If the Exercises tab shows a load error,
select `exercises.json` in Xcode, press **Cmd-Option-1**, and confirm
FitTracker is checked under **Target Membership**.

---

## 2. App Details and Functions

Five tabs. The two halves share only weight entries.

### Diary (nutrition)

- Search the USDA database and log foods to Breakfast / Lunch / Dinner / Snacks
- **Serving sizes** — log "2 × 1 Bar (55g)" instead of raw grams. Grams
  stays the source of truth for nutrition; the label is display only
- Running totals for calories, protein, carbs, and fat
- Collapsible **micronutrient panel** with RDA percentages — 14 vitamins
  and minerals, color-coded (sodium treated as a ceiling, not a goal)
- Arrows page back through previous days
- Foods are cached on first log, so repeat entries need no network call

### Train (live logging)

- **Start Workout** builds a session from today's plan with sets pre-filled
- Tick sets off as you go; a **rest timer** slides up automatically
- Shows your **last performance** per exercise — heaviest set for
  strength, fastest pace for cardio
- Add exercises or sets mid-workout
- **Empty workout** for ad-hoc sessions
- Finishing drops any set you never ticked
- History is tappable — see every set from any past session

### Plan (weekly template)

- Seven days, seeded automatically on first launch (Sunday = Rest)
- Up to **10 exercises per day**, reorderable via Edit
- Each exercise is **Strength** or **Cardio**:
  - **Strength** → sets × reps
  - **Cardio** → reps × time @ pace
- Cardio distance is **derived, never typed** (distance = time ÷ pace).
  A 6 × 3:00 @ 8:30 workout shows "0.35 mi each · 2.12 mi total"
- Cardio mode is auto-selected when you pick a cardio exercise

### Progress

- Log body weight
- Swift Charts line chart of weight over time
- 7-day average weight, weekly workout count, weekly volume

### Exercises

- Browse all ~800 exercises with full instructions
- Filter by **muscle, equipment, category, and level**
- The same filter bar appears in the picker when building plans

### Semantics used throughout

| Term | Meaning |
|---|---|
| **Workout** | The full set of exercises performed in one session |
| **Exercise** | An individual movement within a workout |
| **Macros** | Calories, carbohydrates (incl. fiber, sugars), fats, protein |
| **Micros** | Vitamins and minerals — iron, zinc, choline, B12, etc. |
| **Rep (cardio)** | One interval — a row in the log, same as a set |

### Known limitations

- **Micronutrient coverage is uneven.** Foundation and SR Legacy foods
  have full panels; Branded items often carry only what's on the label.
  A day of mostly packaged food will under-report micros
- **No live heart rate.** `HKWorkoutSession` is watchOS-only, so real-time
  HR would require a watch companion target
- `TimeField` commits on blur, not per keystroke — tap away from a field
  for the value to stick
- Data is local only. No cloud sync or backup yet

---

## 3. Files

| Folder | File | Purpose |
|---|---|---|
| AppUI | `FitTrackerApp` | App entry point. Declares the SwiftData `modelContainer` with all 8 model types — a missing type here crashes on launch |
| AppUI | `RootView` | The five-tab `TabView`. Wires each tab to its view |
| AppUI | `DiaryView` | Daily food log. Day navigation, macro totals, micronutrient disclosure, four meal sections |
| AppUI | `FoodSearchView` | USDA search + portion sheet. Handles serving selection, nutrition preview, and food deduplication on save |
| AppUI | `PlanView` | Weekly plan: `PlanWeekView` (seven days), `PlanDayEditor`, `PlanRow` (strength/cardio toggle), and `ExercisePicker` |
| AppUI | `TrainTabView` | Train tab. Today's plan, Start Workout, session history, plus `WorkoutDetailView` for past sessions |
| AppUI | `ActiveWorkoutView` | Live logging screen. Contains `ExerciseBlock` (one exercise) and `SetRow` (one set or interval) |
| AppUI | `ProgressTabView` | Weight entry, Swift Charts trend line, 7-day average, weekly volume |
| AppUI | `ExerciseBrowserView` | Standalone exercise browser. Also defines `FilterBar` and `ExerciseRow`, both reused by `ExercisePicker` |
| Backend | `API` | **Get your own key** https://fdc.nal.usda.gov/api-key-signup — holds `API.usdaAPIKey` and nothing else |
| Backend | `Models` | Nutrition SwiftData models: `Food`, `FoodEntry`, `WeightEntry`, plus `NutrientValue` and `ServingOption` value types |
| Backend | `TrainingModels` | Workout SwiftData models: `PlanDay`, `PlanExercise`, `WorkoutSession`, `PerformedExercise`, `SetLog`. Also `TargetMode` and the `TimeFormat` helpers |
| Backend | `USDAService` | USDA API client. Defines `Nutrient` IDs, handles the two different JSON shapes USDA returns, parses serving sizes |
| Backend | `Exercise` | The `Exercise` struct, `ExerciseFilters`, and `ExerciseCatalog` — an in-memory singleton, not SwiftData, since this data never changes |
| Backend | `exercises.json` | Bundled exercise database (~800 entries, public domain). Must be checked in Target Membership |
| Backend | `Micros` | `MicroTarget` definitions with RDAs, plus the `MicroPanel` view. **Edit `Micros.tracked` to match your own targets** — iron is 8mg vs 18mg by sex |
| Backend | `SharedFields` | Reusable inputs: `TimeField` (mm:ss), `TimeFieldRequired`, `NumberField`, `IntField` |
| Backend | `WorkoutEngine` | Builds sessions from plans, looks up last performance, and defines `RestTimer` |

### Design notes

**Nutrients are stored as a keyed array, not named properties.** `Food`
holds `[NutrientValue]` keyed by USDA nutrient ID rather than 40 fields
like `vitaminB12`. Adding a new micronutrient costs one line in
`Micros.tracked` and nothing else.

**The exercise catalog is not in SwiftData.** It's static data, so it
loads once into a plain array at launch. Search runs in memory — instant,
offline, no database overhead.

**`SetLog` carries both strength and cardio fields as optionals.** That's
why mile-time tracking works without a second parallel model hierarchy.

**`PerformedExercise` stores its own mode.** It doesn't infer
cardio-vs-strength from the catalog, so manually overriding the mode in a
plan behaves correctly.

**Enums are stored as `String` raw values** with a computed wrapper
(`modeRaw` / `mode`). Raw enums inside `@Model` cause predicate problems.

### If the app crashes on launch after a model change

SwiftData can't always migrate schema changes automatically. Delete
FitTracker from your phone (long-press → Remove App → Delete App) and
build fresh. You'll lose logged data.


# UPDATE - Custom Foods Update and API Redesign
 
## Files
 
| File | Action |
|---|---|
| `Backend/Models.swift` | Edited |
| `Backend/USDAService.swift` | Edited |
| `AppUI/FoodSearchView.swift` | Edited |
| `AppUI/CustomFoodEditor.swift` | **New file**  |

 

## Changes
 
### Custom foods
 
`CustomFoodEditor` builds a food from a nutrition label. The important
design decision: **the form asks for values per serving**, because that's
what labels print. It converts to per-100g on save, since that's how the
rest of the app stores nutrition. You never do the math.
 
Enter the serving name ("1 bar") and its weight (55 g), then the label
values. Vitamins and minerals are optional and collapsed by default.
 
Custom foods are permanent, reusable, and editable. They behave exactly
like USDA foods everywhere else in the app.
 
### Recents and favorites
 
The search sheet now opens showing **Favorites** and **Recent** before you
type anything. Every logged food records `lastUsed` and `useCount`, so
within a week or two your usual meals are one tap away with no search and
no network call.
 
Swipe right on any food to favorite it.
 
### Better USDA search
 
Three changes, all local:
 
1. **Results are re-ranked.** Exact name matches first, then Foundation
   and SR Legacy above Branded, and shorter names above long descriptive
   ones. USDA's own ordering buries plain ingredients under branded
   products.
2. **Calories show inline** in the result list, so you can tell entries
   apart without tapping each one.
3. **`requireAllWords`** is on, which removes most irrelevant matches.
Searching your saved foods happens simultaneously and appears above the
database results.

# UPDATE - Macro Goals

## Files

| File | Action |
|---|---|
| `Backend/MacroGoals.swift` | **New file** |
| `AppUI/FitTrackerApp.swift` | Edited — adds `MacroGoal.self` to the container |
| `AppUI/DiaryView.swift` | Edited |
| `AppUI/ProgressTabView.swift` | Edited |


---

## How it works

### Setting goals

Progress tab → **Macro Goals** → tap any weekday. Enter carbs, protein,
and fat in grams. Calories compute automatically:

```
cals = (carbs + protein) × 4 + fat × 9
```

Examples:
- Monday at 330C / 200P / 55F gives 2,615 kcal. 
- Tuesday at 270C / 200P / 65F gives 2,465 kcal.

Each day also shows the macro split as a percentage bar

**Copy to all days** overwrites all seven with the current day's numbers —
handy for setting a baseline, then adjusting your training days up.

### Other Datials

The goal for the displayed day's weekday loads automatically, exactly like
the workout plan does. The header shows calories consumed, calories
remaining, and a progress bar per macro with grams left.

Going over turns the number orange rather than red — over is information,
not failure.

Paging back to a previous day loads *that day's*
weekday goal, not today's. Reviewing last Sunday compares against Sunday's
target.

### In Progress

- **Macro Goals** row shows today's target at a glance
- **Days on target** counts how many of the last 7 logged days landed
  within 10% of goal
- **Calories vs Goal** chart shows the last 14 logged days as bars, with a
  tick mark for each day's goal. Bars turn orange when over.

---

## One thing to expect

Your logged calories will not exactly equal
`(carbs + protein) × 4 + fat × 9`.

The 4/4/9 formula is a rounded convention. USDA reports measured calorie
values that account for fiber being partly indigestible, alcohol, and
food-specific factors. A day that hits macros perfectly might log 2,580
kcal against a 2,615 goal.


# UPDATE - Refined Exercise DB

## Files

| File | Action |
|---|---|
| `Backend/exercises.json` | Edited |
| `Backend/Exercise.swift` | Edited |
| `AppUI/ExerciseBrowserView.swift` | Edited |


### Changes

Existing plans store `exerciseID` strings from the old database
(`"Barbell_Bench_Press"`). The new IDs are slugs
(`"barbell-bench-press"`), so old plan entries won't match the catalog.

**873 exercises → 163.** Curated for Bodybuilding and General
Training. Everything you'd actually program is here.

**Plain gym names.** "Incline Dumbbell Press", "Romanian Deadlift",
"Lat Pulldown". No underscores, No descriptions-
`level`, `force`, `mechanic`, and `instructions` are gone. 

**New Schema.** Each exercise has:

```json
{
  "id": "incline-dumbbell-press",
  "name": "Incline Dumbbell Press",
  "muscle": "Chest",
  "equipment": "Dumbbell",
  "kind": "compound",
  "secondary": ["Shoulders", "Triceps"],
  "unilateral": false
}
```

**Grouped browsing.** Exercises are sectioned by Muscle in training
order (Chest → Back → Shoulders → Arms → Legs → Abs → Cardio), not
alphabetically across the whole list. 

**`unilateral` flag** marks per-side exercises (Bulgarian split squats,
single-arm rows). Not used for logic, may add ` per side ` logging
