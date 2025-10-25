# Contributing

Everyone is welcome to contribute, and all types of contributions are welcome, including code, documentation, bug reports, and feature requests.

## Design Guidelines

Those contributing code or requesting features should be aware of the following design guidelines:

### DO NOT BREAK USERSPACE

Things is meant to have a stable API, event, and data surface that modders can rely on. Things handles a lot of saved state and, what's more, Things state finds its way into blueprints which are extremely brittle and cannot easily be migrated. Breaking any of Things' state has the potential to cause a massive cascade failure. To that end:

- PRs that modify `storage` without a concurrent migration file that provably works will be rejected on the spot.
- PRs that modify blueprint tag data structures will be flatly rejected unless (1) they are fixing a major bug or adding a major feature AND (2) there is CLEAR documentation, either in the PR's comments or in the associated code, explaining exactly how blueprints with old tag data structures will interoperate correctly while preserving user intent. PRs that break old blueprints are not allowed under any circumstances.
- PRs that modify the parameters or return values of an existing API or event will be rejected. Deprecate instead.
- PRs that deprecate an existing API or event will be rejected unless (1) the given API or event is the cause of a bug or misbehavior and (2) a long-term deprecation and replacement plan is included.
- PRs that remove a API or event will be rejected unless (1) there was a long-term deprecation plan and (2) the duration of that plan has expired.

- PRs that ADD new API without changing existing API behavior in any way are OK.
- PRs that ADD new events without changing existing events behavior in any way are OK.

### Changes MUST be documented comprehensively

- All PRs including bugfixes must include a properly formatted update to `changelog.txt`. (Don't worry about bumping the version)
- PRs that add or change behaviors of API or events MUST include a change to `doc\XXX.md` documenting the change for developers. Undocumented PRs will be rejected on the spot.

### Things is not a kitchen sink.

- Use what's there. If something is possible using existing API surfaces, it's likely we won't add a custom surface just for that thing.
- Enable, don't embrace. We want to provide an API surface for modders to implement ideas, not implement every idea ourselves.
- Maintain scope. Things is about managing entity lifecycles and relationships. If something doesn't fall in that scope, it doesn't belong in Things.

## Other coding guidelines

- Style is deterministically enforced using the StyLua system. A config file is provided and all contributed code must be styled. The easiest way to do this is to set up StyLua to work "on-save" in your IDE.
- Type checking is done by LuaLS+FMTK. All contributed source code must type check. If a line does not type check due to LuaLS jank, leave a "disable" comment and a further comment above the disable comment explaining why the line doesn't need to type-check properly.
