# Local testing

Momo's Money uses local Xcode test validation. GitHub Actions is intentionally not required.

## Run from Xcode

1. Open `Budgeting App.xcodeproj`.
2. Select the shared `Budgeting App` scheme.
3. Choose an iOS Simulator.
4. Run **Product > Test** (`⌘U`).

The shared scheme includes the `Budgeting AppTests` unit-test target.

## Run from Terminal

From the repository root:

```bash
bash scripts/test.sh
```

The script prefers an already-booted iOS Simulator and otherwise selects the first available iOS Simulator, then runs:

```bash
xcodebuild -project "Budgeting App.xcodeproj" -scheme "Budgeting App" -destination "platform=iOS Simulator,id=<UDID>" test
```

## Test organization

- `BudgetingAppSmokeTests.swift` is the XCTest entry point exposed by the shared scheme.
- `CuanMarketModelsTests.swift` is the pre-existing standalone regression runner. It is intentionally excluded from the XCTest target for now so its `@main` entry point does not conflict with XCTest. Its cases can be migrated incrementally into XCTest under TIM-89.

A clean checkout should not require editing the Xcode project or scheme before running the shared tests.
