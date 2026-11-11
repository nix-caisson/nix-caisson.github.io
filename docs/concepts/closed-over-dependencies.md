# Closed-over Dependencies

## Overview

Nix flake modules often need access to the defining flake's pinned trees, but `flake-parts` does not provide a built-in mechanism for closing over them. This means every module and library overlay would need those trees threaded explicitly through its call site, a tedious and error-prone pattern.

caisson solves this with an **explicit closure convention**: everything registered through `mkModule` or `mkLibOverlay` takes a closure attrset as its first arg list. The flake's pinned trees are its **dependencies**, the `dependencies` it passed to `mkLib`, and a registered file reads them through the closure's `closure-lib`. Plain modules and already-built overlays are registered directly instead.

## The Problem

In a standard flake-parts setup, accessing inputs from a module requires either:
- Passing them via `specialArgs` (fragile, global)
- Using `config._module.args` (implicit, hard to trace)
- Threading them manually through every import

None of these compose well when modules are re-exported for downstream consumption.

## How caisson Handles It

### mkModule

A flake registers a module with the `mkModule` of the integration that
owns its class (`lib.caisson.nixos.mkModule`,
`lib.caisson.flake-parts.mkModule`, and so on). Each is
`lib.caisson.mkModule`, a function of the class, applied to that
integration's class:

```nix
mkModule = class: freeformModule: ...
caisson.flake-parts.mkModule = mkModule "flake"
```

Everything passed to the class-specific normalizer takes the closure attrset as its first arg list, followed by an ordinary module:

```nix
# Uses closure values
{ closure-lib, mkModule, ... }:
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
| `closure-lib` | The defining flake's composed `lib` (distinct from the `lib` module arg); its registry, `closure-lib.caisson.modules.<class>`, is how a module imports a sibling by name, and `closure-lib.caisson.dependencies.<name>` is how a module reads one of the defining flake's dependencies |
| `mkModule` | A normalizer bound to the same class, for nested composition |

`closure-lib.caisson.dependencies` is read from `closure-lib.caisson-core.libManifest.dependencies`. It holds the defining flake's pinned trees under their names, with no `self`. It is distinct from the flake-parts `inputs` module arg, which belongs to the consuming flake. A module reads a dependency inside its body:

```nix
{ closure-lib, ... }:
{ config, lib, pkgs, ... }:
{
  services.foo.package = closure-lib.caisson.dependencies.foo-flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
}
```

Path modules are wrapped with `_file` for error locations and `key = toString path`, so a file passed through `mkModule` at two sites deduplicates exactly like importing the same path twice.

Passing a non-function (attrset, path to a plain module, `null`) is an error: plain modules are imported or registered directly rather than wrapped in `mkModule`.

### mkLibOverlay

`mkLibOverlay` follows the same convention. A registered overlay takes `{ closure-lib, mkLibOverlay, mkModule, ... }` as its first arg list and returns an `{ imports ? [ ], overlay }` attrset: the `final: prev:` function under `overlay`, and the overlays it depends on under `imports`. `closure-lib` is the composed library of the composition that registered the overlay, bound lazily. Read it inside the `overlay` function: it is not yet available while the overlay is being registered, so `imports` cannot read it. An integration reaches the registry of the composition that registered it through it:

```nix
{ closure-lib, ... }:
{
  imports = [ "some-flake/default" ];
  overlay = final: prev: {
    upstreamVersion = closure-lib.caisson.dependencies.some-flake.lib.version;
  };
}
```

The string names an entry of the registry. `some-flake/default` is the lib overlay `default` that the project `some-flake` exports, which is in the registry when `projects` lists `some-flake`.

## Key Functions

| Function | Purpose |
|---|---|
| `mkModule` | Creates class-specific module normalizers that close over the defining flake's dependencies |
| `mkLibOverlay` | Applies the closure to registered library overlays |
| `mkModules`, `mkLibOverlays` | Derive the registrations from `modules/<class>/<name>` (also `configs/`) and `lib-overlays/<name>`, applying `mkModule` and `mkLibOverlay` |
| `importApply` | Applies static arguments to a module through the import chain |
| `mkLib` | Bootstraps a composed library with closed overlays |
| `caisson.flake-parts.mkTopConfiguration` | Creates flake outputs with closed modules |

## Further Reading

- [How dependencies are closed over](../deep-dives/how-dependencies-are-closed-over.md): the mechanism behind this convention
- [How `lib` is composed](../deep-dives/how-lib-is-composed.md): the whole composition pass
- [Module Classes](./module-classes.md): class-keyed module registration and export
- `examples/literate-flake/`: a working example demonstrating closed-over dependency wiring
