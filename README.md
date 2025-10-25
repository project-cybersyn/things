# Things

## Quick Links

- [Docs](https://project-cybersyn.github.io/things/)
- [GitHub](https://github.com/project-cybersyn/things)

## Description

**WARNING: THIS MOD IS CURRENTLY IN AN ALPHA STATE. API SURFACES AND EVENT DEFINITIONS ARE UNSTABLE. DO NOT USE IN RELEASE-QUALITY MODS YET. YOU HAVE BEEN WARNED!**

**Things** provides advanced entity management services to other Factorio mods in the form of a high-level abstraction called a `Thing`.

Mod authors register custom entities in `mod-data` to have their lifecycles managed as Things. Once created, Things are manipulated via a documented remote interface, and provide additional custom events for mods to react to.

Here are some things `Thing`s can do:

## Features

### Extended Lifecycle

As opposed to Factorio entities, a `Thing` retains its identity and data throughout a vastly extended lifecycle:

- `Thing`s have unique identifiers to help your mod track them, as well as lifecycle events that trigger when these states change. Unlike `unit_number`s, Thing IDs persist through the entire lifecycle.
- If a `Thing` is built as a ghost, the eventual revived entity is the same `Thing` as the ghost.
- If a `Thing` is killed, the ghost left behind is the same `Thing`.
- If a `Thing` is destroyed as a result of an undo or redo action, undoing or redoing that action later will restore the same `Thing` that was originally present.
- If a `Thing` is modified in a context where Factorio allows undo, the undo will properly undo the modifications made to the `Thing`.

### Parent-Child Relationships

- A `Thing` may register a series of child `Thing`s to be created and managed alongside it.
- Children can be configured to compute and maintain their position and orientation relative to their parents, with full support for in-world and in-blueprint rotation and flipping, where applicable.
- Children and parents receive special events for each other's lifecycle state, making it easy to guarantee that the children come and go with the parent in a correct manner.
- Child/parent relationships are preserved across blueprint and undo operations.

### Comprehensive Support for Blueprinting

- `Thing`s carry arbitrary custom serializable data (a `Tags` structure) which can be set via API and monitored with change events.
- When a `Thing` is lifted into a blueprint, this data is carried along into the blueprint.
- When a blueprint is applied, all of the `Thing`s resulting from the blueprint application will have the same data as the corresponding `Thing`s inside the blueprint.
- This includes all cases involving `Thing`s in the blueprint overlapping pre-existing `Thing`s in the world.

### Entity Graphs

- `Thing`s may be connected to other `Thing`s by directed or undirected graph edges.
- Distinct named graphs can co-exist, each having its own set of edges.
- Connections are preserved in blueprinting, undo, and overlapping.
- Graph edges can store custom edge data (a `Tags` structure) which is serialized with blueprints.

### Synthetic Custom Events

- Through metadata, Things can be instructed to fire custom events of your choice allowing you to respond to Thing lifecycle events.

### ZERO on-tick code

- Things does not make use of any `on_tick` handlers whatsoever.
- This means it will not impact performance outside of monitored construction and lifecycle events.
- This also means Things (and by extension the `Thing`s you make with it) fully works while the game is paused in the editor.

## Credits

The only way to succinctly describe how Things works internally is by saying it warps the laws of Factorio through the use of *incredibly cursed dark magic*. Therefore:

- Special thanks to **protocol_1903** and **boskid** for lending me their subtick-event Time-Turners.
- Special thanks to **Bilka** for adding the spell *blueprintus revelio* to Factorio.
- Special thanks to the following members of Slytherin House for teaching me *rotata kedavra*, which may not be Unforgivable but is definitely very cursed: **boskid**, **protocol_1903**, **PennyJim**
- Special thanks to **hgschmie** and **Telkine2018** for the idea of world keys, which are almost as useful as portkeys.

Thanks also to the following in no particular order:
- justarandomgeek (for FMTK, as well answering a number of my weird questions in modding discord)
- thesixthroc (for helping me find and fix bugs in bplib, the intellectual precursor to this library)

## Contributing

Please use the [GitHub repository](https://github.com/project-cybersyn/things) for questions, bug reports, or pull requests.
