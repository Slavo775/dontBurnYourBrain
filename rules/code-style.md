# Code style

Swift 6, SwiftUI and SwiftData as this project writes them. The architecture rules and the data model rules are in `CLAUDE.md` and are not repeated here. This file says how to apply them.

The compiler runs in Swift 6 mode with warnings as errors, SwiftFormat owns the formatting (`.swiftformat`), and SwiftLint runs strict (`.swiftlint.yml`). Never silence a warning or a lint rule to get through the check. If a rule is wrong, say so in your report.

## Naming and comments

- Follow the Swift API Design Guidelines. Judge a name where it is used, not where it is declared. Clear beats short.
- Name by role, not by type: `supplier`, not `widgetFactory`. Leave out words that only repeat the type.
- Types and protocols are `UpperCamelCase`, everything else `lowerCamelCase`. A protocol that names an ability ends in `-able`, `-ible` or `-ing`.
- A method without side effects reads as a noun phrase (`distance(to:)`). One with side effects reads as a verb (`append(_:)`). Pairs: `sort()` changes, `sorted()` returns.
- Every `public` declaration in `DontBurnCore` has a `///` comment that starts with a one-sentence summary. If the summary is hard to write, the design is probably wrong.
- Other comments say why, never what. No commented-out code.

## Where logic lives

- A rule, a calculation or a state change belongs in `DontBurnCore`. It imports no SwiftUI and no AppKit.
- A view reads state and sends the user's intent on. If a view needs an `if` that is about the business and not about layout, the rule moves to `DontBurnCore`.
- A Mac-only service sits in `Apps/Mac` behind a small protocol, with one adapter per agent tool and per terminal. When its part is not set up, not installed or not permitted, the service says so, and the interface leaves that part out. Nothing else breaks and nothing nags.
- Time is passed in, as a `Date` or a clock. `DontBurnCore` never calls `Date()`, `Date.now` or a clock's `now`, and never sleeps. When a rule depends on the calendar or the time zone, those are passed in too.
- The version, the bundle identifier and the app's name are never written in code. See [releases.md](releases.md).

## Errors

- Each area has its own error enum. An error says what failed in words the caller can act on.
- No `try!`, no force unwrap, no `as!`, and no `fatalError` in product code.
- Never an empty `catch`. `try?` only where failing is truly fine, with a comment that says why.
- Plain `throws` is the default. Typed throws (`throws(SomeError)`) only where callers handle every case.
- What the user reads about an error comes from the string catalog. What goes to the log follows the log rule in [safety-and-privacy.md](safety-and-privacy.md).

## Concurrency

- Types that drive the interface are `@MainActor`, marked on the type.
- `async` does not mean "in the background". Heavy work leaves the main actor on purpose, in a `nonisolated` function marked `@concurrent`.
- An `actor` protects shared state that changes. No actor without state, and no type that mixes isolation between its members.
- Prefer structured concurrency: `async let`, task groups, and the `.task` modifier in views. A bare `Task { }` needs a reason, and `Task.detached` needs a comment.
- A long loop checks for cancellation.
- Never block to wait for async work: no `DispatchSemaphore`, no `DispatchGroup.wait()`, no sleeping.
- Global and static state is a `let` constant or belongs to an actor.
- `@unchecked Sendable`, `nonisolated(unsafe)` and `@preconcurrency` each need a comment that says why it is safe. The Reviewer checks every one.

## SwiftUI

- State lives in `@Observable` classes. `@State` holds what only one view owns, `@Environment` what many share, `@Bindable` makes bindings. No `ObservableObject`, `@Published` or `@StateObject`.
- Keep views small. Pull a part out when it has a name of its own.
- Every view has a `#Preview` with the sample data: Acme, Globex and Personal.
- **Text comes from the string catalog**, `Localizable.xcstrings`. Never join translated pieces with `+`. Use interpolation, and the catalog's plural forms. `DontBurnCore` returns values, and the view turns them into text.
- Colours, sizes and type follow `docs/spec/design.md`: system materials, semantic colours and system text styles first. A workspace colour is stored as its palette key, never as a hex value.
- Every control has an accessibility label. A button that shows only an icon gets one by hand.

## SwiftData

- The model rules in `CLAUDE.md` apply to every model from the first version.
- Models live in `DontBurnCore`. The store's place on disk comes only from `StoreLocation`, never from the default.
- Tests and previews use a store in memory.
- A card that changes the data model is marked "schema change". See [releases.md](releases.md).

## Availability and dependencies

- The app targets macOS 26 and iOS 26. No `#available` branches for older systems, and no deprecated API. Never work around a deprecation warning.
- A new dependency needs the owner's yes on the card, with its license and the reason.

## Known traps

- **A window of a menu bar app opens behind other apps**, and the Settings window hides when the app loses focus. An app without a Dock icon is not brought forward by itself. Bring the app forward when it opens a window, and check this by hand in every card that adds one.
- **`JSONEncoder` with `.iso8601` dates drops fractions of a second.** Anything that compares times written that way needs a strategy that keeps them.
