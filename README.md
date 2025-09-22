# Things

**WARNING: THIS MOD IS A WORK IN PROGRESS. ALL API SURFACES ARE UNSTABLE. DO NOT USE IN PRODUCTION **

**Things** provides advanced entity management services to other Factorio mods in the form of a high-level abstraction called a `Thing`.

As opposed to Factorio entities, a `Thing` retains its identity and data throughout a vastly extended lifecycle:

- Mods can take any entity in the world and make it into a `Thing`.
- If a `Thing` is built as a ghost, the eventual revived entity is the same `Thing` as the ghost.
- If a `Thing` is killed, the ghost left behind is the same `Thing`.
- If a `Thing` is destroyed as a result of an undoable action, undoing will produce the same `Thing`.
- If a `Thing` is picked up from the world into a blueprint, it becomes a `BlueprintThing` carrying all the same data.
- If a blueprint is pasted into the world, all `BlueprintThing`s become new `Thing`s carrying the same data; unless the blueprint would overwrite an existing `Thing`, in which case the data is written into the pre-existing `Thing`.

## Contributing

Please use the [GitHub repository](https://github.com/project-cybersyn/things) for questions, bug reports, or pull requests.

## Usage

Documentation is WIP.
