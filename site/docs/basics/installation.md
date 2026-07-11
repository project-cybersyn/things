---
sidebar_position: 1
---

# Installation

## Adding a Dependency

Things is installed by adding `0-things` as a **required** dependency in your mod's `info.json` file. Here is an example of setting up a mod to depend on Things:

```json
{
  "name": "ribbon-cables",
  "version": "0.1.0",
  "title": "Ribbon Cables",
  "author": "The LORD thy GOD",
  "contact": "https://github.com/wcjohnson/ribbon-cables",
  "homepage": "https://github.com/wcjohnson/ribbon-cables",
  "description": "Multiplex many circuit network connections onto a single compact cable.",
  "factorio_version": "2.1",
  "dependencies": [ "base >= 2.1.7", "0-things >= 0.1.0" ],
}
```

Once your dependency is set up, you may download and install it in-game through the usual mechanism. You're now ready to begin using Things in your mod.

:::info
Things is a stateful mod with a control phase, and may not be used as standalone code. You must install it as a dependency.
:::

## VSCode IDE Integration

Things is fully typed for use with FMTK + EmmyLua. You must use the EmmyLua language server; the legacy luals language server will not work with Things' types.

To add integration to your IDE, you can do the following:

1) Download the mod's .ZIP file (or check it out from Github)
2) Extract to a suitable location on your development machine. In the following example we assume you extracted it to `d:\dev\factorio\0-things\`
3) Create a file called `.emmyrc.json` at your IDE project root. Paste in the following content:

```json
{
  "workspace": {
    "library": [
      "d:\\dev\\factorio\\0-things\\client"
    ]
  }
}
```

You should now have IDE typings and completion for Things.

## Things Client

The docs and tutorials on this site will often refer to the Things Client. This is a Lua module that you should `require` inside your mod in order to make use of Things:

```lua
-- data.lua OR control.lua

---@diagnostic disable-next-line: unresolved-require
local things_client = require("__0-things__.client.client") --[[@as things.client]]
```

The associated type-checking comments will ensure you have proper typing (if you performed the steps above) and suppress a spurious warning.

Going forward, most documents on this site will assume you have already performed this `require` step.
