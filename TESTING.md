# Local testing

Momo's Money uses local Xcode test validation. GitHub Actions is intentionally not required.

## Run from Xcode

1. Pull the latest TIM-88 branch and close/reopen Xcode after the pull.
2. Open `Budgeting App.xcodeproj`.
3. In the scheme selector choose the shared **Budgeting AppTests** scheme.
4. Choose an iOS Simulator.
5. Run **Product > Test** (`⌘U`).

`Budgeting AppTests` is a dedicated shared scheme committed under `Budgeting App.xcodeproj/xcshareddata/xcschemes/`. It builds the Momo's Money app as the test host and runs the `Budgeting AppTests` XCTest bundle.

## Verify Xcode can see the scheme

From the repository root:

```bash
xcodebuild -project "Budgeting App.xcodeproj" -list
```

The `Schemes:` section must include `Budgeting AppTests`. If it does not, confirm the latest branch has been pulled and reopen Xcode.

## Run from Terminal

From the repository root:

```bash
bash scripts/test.sh
```

The script first verifies that `xcodebuild` can see the dedicated shared test scheme. It then prefers an already-booted iOS Simulator and otherwise selects the first available iOS Simulator before running:

```bash
xcodebuild -project "Budgeting App.xcodeproj" -scheme "Budgeting AppTests" -destination "platform=iOS Simulator,id=<UDID>" test
```

## Test organization

- `BudgetingAppSmokeTests.swift` is the XCTest entry point exposed by the shared `Budgeting AppTests` scheme.
- `CuanMarketModelsTests.swift` is the pre-existing standalone regression runner. It is intentionally excluded from the XCTest target for now so its `@main` entry point does not conflict with XCTest. Its cases can be migrated incrementally into XCTest under TIM-89.

A clean checkout should not require editing the Xcode project or creating a scheme before running tests.
