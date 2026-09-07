# Closed Inputs

## Overview

Nix flake modules often need access to the defining flake's `inputs`, but `flake-parts` does not provide a built-in mechanism for closing over them. This means every module and library overlay would need inputs threaded explicitly through its call site, a tedious and error-prone pattern.

caisson solves this with an **explicit closure convention**: everything registered through `mkModule` or `mkLibOverlay` takes a closure attrset as its first arg list. Plain modules and already-built overlays are registered directly instead.

## The Problem

In a standard flake-parts setup, accessing inputs from a module requires either:
- Passing them via `specialArgs` (fragile, global)
- Using `config._module.args` (implicit, hard to trace)
- Threading them manually through every import

None of these compose well when modules are re-exported for downstream consumption.

## How caisson Handles It

### mkModule

`mkModule` is a factory:

```nix
mkModule = class: freeformModule: ...
```

You first choose a module class, then use the returned class-specific normalizer. For flake-parts modules:

```nix
mkFlakeModule = mkModule "flake"
```

Everything passed to the class-specific normalizer takes the closure attrset as its first arg list, followed by an ordinary module:

```nix
# Uses closure values
{ closure-inputs, closure-lib, mkModule, ... }:
{ config, lib, ... }:
{ ... }

# Ignores the closure but still takes the arg list
{ ... }:
{ config, lib, ... }:
{ ... }
```

The closure attrset contains:

| Key | Value |
|---|---|
| `closure-inputs` | The defining flake's `inputs` (distinct from the flake-parts `inputs` module arg, which belongs to the consuming flake) |
| `closure-lib` | The defining flake's composed `lib` (distinct from the `lib` module arg) |
| `closure-self-modules` | The defining flake's registered modules in the same class |
| `mkModule` | A normalizer bound to the same class, for nested composition |

Path modules are wrapped with `_file` for error locations and `key = toString path`, so a file passed through `mkModule` at two sites deduplicates exactly like importing the same path twice.

Passing a non-function (attrset, path to a plain module, `null`) is an error: plain modules are imported or registered directly rather than wrapped in `mkModule`.

### mkLibOverlay

`mkLibOverlay` follows the same convention. A registered overlay takes `{ closure-inputs, mkLibOverlay, ... }` as its first arg list and returns an `{ imports ? [ ], overlay }` attrset: the `final: prev:` function under `overlay`, and the overlays it depends on under `imports`:

```nix
{ closure-inputs, ... }:
{
  imports = [ closure-inputs.some-flake.libOverlays.default ];
  overlay = final: prev: { ... };
}
```

Already-built overlays (for example another flake's exported `libOverlays.default`) are registered directly rather than wrapped in `mkLibOverlay`.

## Key Functions

| Function | Purpose |
|---|---|
| `mkModule` | Creates class-specific module normalizers with closed inputs |
| `mkLibOverlay` | Applies the closure to registered library overlays |
| `importApply` | Applies static arguments to a module through the import chain |
| `mkLib` | Bootstraps a composed library with closed overlays |
| `mkFlake` | Creates flake outputs with closed modules |

## Further Reading

- [How inputs are closed over](../deep-dives/how-inputs-are-closed-over.md): the mechanism behind this convention
- [How `lib` is composed](../deep-dives/how-lib-is-composed.md): the whole composition pass
- [Module Classes](./module-classes.md): class-keyed module registration and export
- `examples/literate-flake/`: a working example demonstrating closed input wiring
