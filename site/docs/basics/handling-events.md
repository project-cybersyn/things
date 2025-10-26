---
sidebar_position: 3
---

# Handling Events

:::info
This is a continuation from the previous tutorial. Code examples will assume you're following along.
:::

## Factorio Events

Where possible, Things tries to cooperate fully with Factorio's existing APIs. Therefore, when a Factorio event is sufficient to handle your mod's needs, you should use it. In the course of handling these events, it may become necessary to retrieve a Thing that you created before. We'll use the [`things.get`](../reference/remote-interface#get) remote API to do that.

Create a `control.lua` in your `my-mod` folder and add the following code:

```lua
script.on_event(
  defines.events.on_selected_entity_changed,
  ---@param event EventData.on_selected_entity_changed
  function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local selected = player.selected
    if not selected then return end

    -- Using the Things API, retrieve the Thing the user has selected.
    local _, thing = remote.call("things", "get", selected)

    if thing.name == "my-mod-thing" then
      game.print("Selected my new Thing with Thing ID" .. thing.id)
    end
  end
)
```

Launch the game and build your new Thing. Now, whenever you mouse over it, you should get a nice message.

:::info
The [things.get API](../reference/remote-interface#get) returns a [things.ThingSummary object](../reference/types/#thingsthingsummary) which is the primary data type returned by all API calls when describing Things.
:::

## Synthetic Events

In some cases, Factorio's events are not consistent with Thing lifecycle. (Or even worse, nonexistent, wrongly ordered, or misbehaving.) Things provides a number of synthetic events that are useful in handling these cases.

### Data Phase

In order to handle these events, we must first tell Things which synthetic events we are interested in, along with creating Factorio custom events for Things to generate. This is done in our `data.lua`:

```lua
---@type things.ThingRegistration
local my_thing_registration = {
  name = "my-mod-thing",
  intercept_construction = true,
  -- highlight-start
  -- Inform Things to fire the "my-mod-on_initialized" CustomEventPrototype when on_initialized happens
  custom_events = {
    on_initialized = "my-mod-on_initialized"
  }
  -- highlight-end
}

data.raw["mod-data"]["things-names"].data["my-mod-thing"] = my_thing_registration

-- highlight-start
-- Create the Factorio CustomEventPrototype we've asked Things to send us.
-- (If you don't do this, the game will crash when Things tries to raise the event.)
data:extend({
  { type = "custom-event", name = "my-mod-on_initialized" }
})
-- highlight-end
```

The new code is telling Things that whenever an [`on_initialized`](../reference/events#on_initialized) event happens regarding our Thing, the Factorio custom event named `my-mod-on_initialized` should be raised.

:::warning
You must be sure that the custom event prototype name you provide exists (usually by creating it yourself in the data phase.) If you do not, the game will crash when Things tries to fire the event.
:::

### Control Phase

We can now add some code to our `control.lua` to handle the custom event:

```lua
script.on_event("my-mod-on_initialized",
  ---@param event things.EventData.on_initialized
  function(ev)
    game.print("My thing was initialized with id" .. ev.id)
  end
)
```

Things custom events always receive a single typed argument depending on the type of event. Here, since this is an [`on_initialized event`](../reference/events#on_initialized), it receives an object of type [`things.EventData.on_initialized`](../reference/events#on_initialized) as its argument.

## Test in-game

1) Load up your mod in a test game.
2) Build your new Thing. Watch what happens.
3) Destroy your Thing and then undo the destruction. Watch what doesn't happen.

Synthetic events can respond to Thing lifecycle in a way that is not possible with ordinary Factorio events.

## Summary

We've now seen how to handle both Factorio and custom events that reference our newly created Thing.

:::info
Things can generate many useful synthetic events. The full list is available in the [Events reference](../reference/events)
:::
