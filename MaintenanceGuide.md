# ThingStruct Maintenance Guide

## Product Authority
- Read `PRD.md` before accepting feature work. It owns the target user, product behavior, P0/P1 boundary, frozen capabilities, and validation criteria.
- `README.md` owns domain models and algorithms; `Design.md` owns UI expression.
- `SystemSurfaces.md` and `weiget.md` describe deferred system-surface work and cannot expand the current product scope.
- Existing code is a technical asset, not evidence that a capability belongs in the active product scope.

## Read Order
- `PRD.md`: product goal, current scope, and requirement admission rules
- `README.md`: domain semantics and invariants
- `Design.md`: P0 experience and UI acceptance flow
- `ThingStruct/CoreShared`: pure rules and shared models
- `ThingStruct/ThingStructStore.swift`: app state, screen queries, user commands
- `ThingStruct/ThingStructApp.swift`: app launch, root UI, quick actions, external routing
- `ThingStructWidgetExtension`: widget rendering and widget-only entry points

## Product Change Gate
- During P0, prioritize empty-data activation, automatic default-day running, `Now`, exception switching, lightweight Today correction, and local persistence.
- Do not expand frozen capabilities merely because their implementation already exists.
- Before accepting a feature, identify the user problem, journey stage, measurable outcome, smallest experiment, and explicit non-goal.
- If a change does not improve the P0 acceptance flow or a PRD metric, keep it out of the active scope.
- Sample data is allowed for previews and tests only; it must not stand in for production onboarding.

## Where Changes Go
- Change planning rules, validation, template logic, or time resolution in `Engine` files.
- Change what a screen needs to render in `ScreenModels` and the presentation helpers.
- Change user-triggered app behavior in `ThingStructStore`.
- Change deep links, quick actions, widget buttons, notifications, or live activity wiring in the app/widget entry files.

## When To Add A File
- Add a new file only when one file is carrying two separate responsibilities.
- Do not create a new file for a tiny helper that is only used by one feature screen or one entry point.
- Prefer adding a `MARK` section and a private helper before splitting a file.

## When To Avoid Abstraction
- Do not add a protocol, factory, manager, or service container unless there is a second real implementation today.
- Prefer a concrete type with explicit parameters over a hidden dependency layer.
- Prefer one obvious write path over multiple convenience entry points.

## Safe Refactor Checklist
- Confirm the change is inside the current PRD scope or is a required regression fix.
- Keep `DayPlanEngine` and `TemplateEngine` pure.
- Keep repository code limited to loading, saving, and atomic document mutation.
- Keep route parsing outside `ThingStructStore`.
- Verify the empty-document path when changing startup, templates, or materialization.
- Run `swift test` after core changes.
- Run an Xcode build after app or widget entry changes.
