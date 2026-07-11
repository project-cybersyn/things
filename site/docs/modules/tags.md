---
sidebar_position: 3
---

# Tags

![Stability - Stable](https://shields.io/badge/stability-stable-green?style=for-the-badge)

The Tags module allows the attachment of arbitrary JSON-style key-value pairs to Things. This information is automatically retained when Things are blueprinted or copied, and will be reapplied to new or overlapped objects in the world.

You can also store key-value pairs as transient data, which are attached to the Thing ID itself and are NOT extracted or copied by any player operations.

## Client Methods
Client methods are called using the Things Client.

### tags_v1.get_tag
Get a tag from a Thing.

```lua
---@param thing things.Id Thing ID to query. This function will return `nil` if the Thing does not exist.
---@param tag_name string
---@return AnyBasic? tag_value The value of the tag
local tag_value = things_client.tags_v1.get_tag(thing, tag_name)
```

### tags_v1.get_tags
Get all tags from a Thing.

```lua
---@param thing things.Id Target Thing ID. This function will return `nil` if the Thing does not exist.
---@return Tags? tags The tags of the Thing, or nil if there are no tags.
local tags = things_client.tags_v1.get_tags(thing)
```

### tags_v1.set_tag
Set a tag on a Thing.

```lua
---@param thing things.Id Target Thing ID. This function will do nothing if the Thing does not exist.
---@param tag_name string
---@param tag_value AnyBasic? The value of the tag, or nil to remove the tag.
things_client.tags_v1.set_tag(thing, tag_name, tag_value)
```

### tags_v1.set_tags
Set all tags on a Thing.

```lua
---@param thing things.Id Target Thing ID. This function will do nothing if the Thing does not exist.
---@param tags Tags The new tags for the Thing. This will replace all existing tags on the Thing. An empty table will remove all tags.
things_client.tags_v1.set_tags(thing, tags)
```
### tags_v1.merge_tags
Shallow merge tags into the tags of a Thing. Existing tags with the same key will be overwritten, and new tags will be added. Tags not present in the `tags` parameter will remain unchanged.

```lua
---@param thing things.Id Target Thing ID. This function will do nothing if the Thing does not exist.
---@param tags Tags The tags to merge into the Thing's existing tags.
things_client.tags_v1.merge_tags(thing, tags)
```

### tags_v1.set_transient_data
Attach transient data to a Thing.

```lua
---@param thing things.Id Target Thing ID. This function will do nothing if the Thing does not exist.
---@param key string The key of the transient data.
---@param value (AnyBasic|LuaObject)? The value of the transient data. If `nil`, the transient data will be removed.
things_client.tags_v1.set_transient_data(thing, key, value)
```

### tags_v1.get_transient_data
Get transient data from a Thing.

```lua
---@param thing things.Id Target Thing ID. This function will return `nil` if the Thing does not exist.
---@param key string The key of the transient data.
---@return (AnyBasic|LuaObject)? value The value of the transient data, or nil if it does not exist.
things_client.tags_v1.get_transient_data(thing, key)
```

## Custom Events
Custom events must be mapped in the data phase and bound to a handler.

### on_tags_changed
Raised whenever something sets a Thing's tags.

Note that for performance reasons, Things does not attempt to compare the new tags with the old ones, therefore this event may arise even if no tags have actually changed. Consumers must check as appropriate for their use case.

Things will tell you whether the tags were set by `api` (a consumer called the Things API) or `engine` (a user pasted a blueprint or took another action that was intercepted by the engine and changed the tags)

The type of this event's parameter is `things.EventData.on_tags_changed`:

```lua
---@class (exact) things.EventData.on_tags_changed
---@field public thing things.ThingShortSummary Summary of the Thing whose tags changed.
---@field public new_tags Tags The new tags of the Thing.
---@field public old_tags Tags The previous tags of the Thing.
---@field public cause "api"|"engine" Source of the tag change event.
```
