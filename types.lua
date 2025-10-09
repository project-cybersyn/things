-- Public types and enums for the Things API.

---General statuses of a Thing.
---`real` means the Thing has a valid real entity.
---`ghost` means the Thing has a valid ghost entity.
---`tombstone` means the Thing has no entity, but still exists on the undo stack and could potentially be brought back via undo operations.
---`destroyed` means the Thing is irrevocably gone. Destroyed things will be garbage-collected and cannot be used for any purpose.
---@alias things.Status "real"|"ghost"|"tombstone"|"destroyed"

---Causes of the last status change.
---`created` means the Thing was created from nothing.
---`blueprint` means the Thing changed status due to blueprint application or extraction.
---`undo` means the Thing changed status due to an undo operation.
---`died` means the Thing changed status because its real entity died.
---`revived` means the Thing changed status because its ghost entity was revived into a real entity.
---@alias things.StatusCause "created"|"blueprint"|"undo"|"died"|"revived"

---Registration options for a type of Thing.
---@class (exact) things.ThingRegistration
---@field public virtualize_orientation? boolean If true, the orientation of the Thing will be stored and managed by Things instead of relying on Factorio's built-in entity orientation. This allows for more complex orientation scenarios involving compound entities. (default: false)
---@field public merge_tags_on_overlap? boolean If true, when a Thing is overlapped by a blueprinted thing with tags, the tags will be shallow-merged instead of replaced. (default: false)

---Registration options for a graph of Things.
---@class (exact) things.GraphRegistration
---@field public directed? boolean Whether the graph is directed (default: false).

---Representation of an edge in a graph of Things.
---@class things.GraphEdge
---@field public first int First Thing ID connected to this edge. (In undirected graphs, the lower id.)
---@field public second int Second Thing ID connected to this edge.
---@field public data? Tags Optional user data associated with this edge.

---@class things.NamedGraphEdge: things.GraphEdge
---@field public name string The name of the graph this edge belongs to.

---Event fired when a Thing with a new ID is generated in the world.
---Does not apply to undo, revival, etc of pre-existing Things.
---@class things.EventData.on_initialized
---@field public thing_id int The id of the Thing that was initialized.
---@field public entity LuaEntity? The current entity of the Thing, if it has one.
---@field public status things.Status The current status of the Thing.

---@class things.EventData.on_status_changed
---@field public thing_id int The id of the Thing whose status changed.
---@field public entity LuaEntity? The current entity of the Thing, if it has one.
---@field public new_status things.Status The new status of the Thing.
---@field public old_status things.Status The previous status of the Thing.
---@field public cause things.StatusCause The cause of the status change.

---Event parameters for when Thing tags change. Note that for performance
---reasons, Things does not deep compare tags, so this event may be raised
---in certain cases even when tags haven't meaningfully changed.
---@class things.EventData.on_tags_changed
---@field public thing_id int The id of the Thing whose tags changed.
---@field public entity LuaEntity? The current entity of the Thing, if it has one.
---@field public new_tags Tags The new tags of the Thing.
---@field public previous_tags Tags The previous tags of the Thing.

---@class things.EventData.on_edges_changed
---@field public change "created"|"deleted"|"data_changed"|"status_changed" The type of change that occurred.
---@field public graph_name string The name of the graph whose edges changed.
---@field public nodes {[int]: true} Set of Thing ids whose edges were changed.
---@field public edges things.GraphEdge[] List of edges that were changed.
