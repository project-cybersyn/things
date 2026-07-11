---
sidebar_position: 3
---

# Lifecycle

![Stability - Stable](https://shields.io/badge/stability-stable-green?style=for-the-badge)

The lifecycle module encompasses the creation, destruction, voiding, devoiding, and revival of Things.

Things have four lifecycle states:

- **`real`** - The Thing is associated with an actual non-ghost entity.
- **`ghost`** - The Thing is associated with an entity ghost.
- **`void`** - The Thing is not currently associated with an entity, but its state data is being stored and it may later re-appear. (An example of this is a Thing that is somewhere on the undo stack and may be rebuilt if the player performs an undo operation later.)
- **`destroyed`** - The Thing has been completely eliminated and cannot be used for any purpose. Its state is no longer valid.

Via the lifecycle module you can receive events when state changes occur, as well as intervene in the lifecycle when needed.

## Client Methods

## Custom Events
