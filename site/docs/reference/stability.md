# Stability

Each Things module has a stability level. The stability level of a module is documented at the top of a module's doc page. If a particular method or event has different stability, it may have a different mark next to its definition.

Stability refers to stability of the interface endpoints from breaking changes, not necessarily stability of the underlying code. In particular, stability does NOT mean that a particular module is free of bugs.

The levels of stability are defined as follows:

## Stable

![Stability - Stable](https://shields.io/badge/stability-stable-green?style=for-the-badge)

Stable modules are safe for use in production/released mods. These modules have a fixed API contract:

- Stable methods will not have their argument types or return types changed.
- Stable interfaces will not have methods removed without significant advanced deprecation notice. (Methods may be added.)
- Stable events will not have fields removed from their parameters object, nor will the type of an existing field change. (Fields may be added.)
- No method or event will be removed from stable without a deprecation, except in an emergency situation.
- Deprecations are extremely unlikely.
- Deprecations will come with significant advanced notice and suggested replacements for functionality.

## Beta

![Stability - Beta](https://shields.io/badge/stability-beta-yellow?style=for-the-badge)

Beta modules are on the path to stability. The concept they express will eventually reach a stable form, but their current API surfaces are in flux.

Using beta modules in your mods is okay as long as you are willing to actively keep up with Things development and update your mods accordingly.

- Beta methods may change argument types or return types
- Beta interfaces may change additively or subtractively, but the general function implemented by a beta method will remain available through other method(s) even if changed.
- Beta events may have their parameter fields changed or be removed, but the general function of the event will remain available through other means.
- Methods may be removed without deprecation notices.

## Experimental

![Stability - Experimental](https://shields.io/badge/stability-experimental-orange?style=for-the-badge)

Experimental modules contain ideas and concepts that may change completely or be rejected altogether before reaching stability.

Using experimental modules is dangerous and only for those who like to live on the edge, as it is possible that you may build on top of an experimental module that will later be deleted without replacement functionality.

- Anything about an experimental module may change arbitrarily without warning.
- This includes deletion of methods, events, interfaces, or the entire module.
