# Things

**WARNING: THIS MOD IS CURRENTLY IN AN ALPHA STATE. API SURFACES ARE UNSTABLE/MISSING AND THERE ARE KNOWN BROKEN EDGE CASES. DO NOT USE IN PRODUCTION YET. YOU HAVE BEEN WARNED!**

**Things** provides advanced entity management services to other Factorio mods in the form of a high-level abstraction called a `Thing`.

Mod authors register their custom entities in `mod-data`, and any time a registered entity is created, it becomes a new Thing. Once created, Things are manipulated via a documented remote interface, and provide additional custom events for mods to react to.

Here are some things you stand to gain by using `Thing`s:

## Extended Lifecycle

As opposed to Factorio entities, a `Thing` retains its identity and data throughout a vastly extended lifecycle:

- If a `Thing` is built as a ghost, the eventual revived entity is the same `Thing` as the ghost.
- If a `Thing` is killed, the ghost left behind is the same `Thing`.
- If a `Thing` is destroyed as a result of an undoable action, undoing that action later will restore the same `Thing` that was originally present.
- `Thing`s have unique identifiers to help your mod track them, as well as lifecycle events that trigger when these states change.

## Comprehensive Support for Blueprinting

- `Thing`s carry arbitrary custom serializable data (a `Tags` structure) which can be set via API and monitored with change events.
- When a `Thing` is lifted into a blueprint, this data is carried along into the blueprint.
- When a blueprint is applied, all of the `Thing`s resulting from the blueprint application will have the same data as the corresponding `Thing`s inside the blueprint.
- This includes all cases involving `Thing`s in the blueprint overlapping pre-existing `Thing`s in the world.
- Unlike Factorio's native tags, which only work via ghosts, this mechanism works in cheat mode, editor mode, paused, and other situations where no ghost intermediary is present.

## Parent-Child Relationships

## Entity Graphs

## Contributing

Please use the [GitHub repository](https://github.com/project-cybersyn/things) for questions, bug reports, or pull requests.

## Usage

Documentation is WIP.
