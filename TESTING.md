# Local testing

TIM-88 uses Xcode directly. No bash script or GitHub Actions is required.

## Open the workspace

Open `MomosMoney.xcworkspace` instead of opening the app project by itself. The workspace contains the existing `Budgeting App.xcodeproj` plus an isolated `BudgetingAppTests.xcodeproj`, so the app project is not modified by the test harness.

## Run tests

1. Select the shared `Budgeting AppTests` scheme.
2. Choose any installed iOS Simulator.
3. Run **Product > Test** (`⌘U`).

The initial smoke test verifies that the XCTest target and shared scheme run correctly. TIM-89 can migrate the existing regression cases into XCTest after this harness is validated.
