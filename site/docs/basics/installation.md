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
  "factorio_version": "2.0",
  "dependencies": [ "base >= 2.0.66", "0-things >= 0.1.0" ],
}
```

Once your dependency is set up, you may download and install it in-game through the usual mechanism. You're now ready to begin using Things in your mod.

:::info
Things is a stateful mod with a control phase, and may not be used as standalone code. You must install it as a dependency.
:::

## VSCode IDE Integration

Things is fully typed for use with FMTK + LuaLS. To add integration to your IDE, you can do the following:

1) Download the mod's .ZIP file (or check it out from Github)
2) Extract to a suitable location on your development machine. In the following example we assume you extracted it to `d:/dev/factorio/0-things/`
3) Add the following lines to your VSCode `settings.json`:

```json
{
  "Lua.workspace.library": [
    "d:/dev/factorio/0-things/remote-interface.lua"
  ],
}
```

You should now have IDE typings and completion for remote calls into the `things` interface.
