# Module Options Reference

This reference documents the caisson framework's module options. All descriptions are sourced from the Nix-native `description` fields in the module code.

For `lib.caisson` functions, see [Library Reference](./lib.md).

## Options

### `caisson.lib.export.enabled`

- **Type:** `bool`
- **Default:** `false`
- **Source:** `modules/generic/core/caisson/lib.nix`

Whether to enable lib export. When enabled, publishes the selection made by `caisson.lib.exported` as `flake.lib`.

### `caisson.lib.exported`

- **Type:** `function -> lazyAttrsOf raw`
- **Default:** `composedLib: composedLib.${name}`, where `name` is the project's name declared on `mkLib` (refused when none is declared)
- **Source:** `modules/generic/core/caisson/lib.nix`

Function that selects which parts of the composed library to publish as the flake's `lib` output. The default exports the namespace named after the project; caisson itself sets `composedLib: { inherit (composedLib) caisson caisson-core; }` so flake-level and composed-level addresses match.

### `caisson.manifest`

- **Type:** `caisson.flake-parts.types.manifest` (read-only)
- **Default:** the composed library's `caisson-core.evalManifest`, or its `caisson-core.libManifest` in an evaluation that carries none
- **Source:** `modules/generic/core/caisson/manifest.nix`

The manifest of this evaluation. A structural configuration carries one (`type`, `name`, `parent`, `children`, and the registries and declared facts of the composition it is declared under); a flake-parts evaluation carries none, and there this is the composition's manifest: `inputs`, `defaultEcosystemSrc`, `systems` and `projects` as given to `mkLib`, plus the registered `libOverlays` and `modules` dictionaries (project entries under `<project>/<name>`, locals winning). Reading it type-checks the manifest; the `flake.modules` and `flake.libOverlays` projections are drawn from it, and flake-parts' `systems` defaults to the manifest's `systems` when the composition declared one (`modules/flake/core/caisson/systems.nix`).

### `caisson.<integration>.configurations`

- **Type:** lazy attribute set of configurations, read back as manifests
- **Default:** `{ }`
- **Source:** `modules/generic/core/caisson/configurations.nix`

The configurations of an integration declared beneath this configuration, by name. The option exists for every integration that owns a module class (`lib.caisson.integrations.names`). An entry takes what that integration's `mkConfiguration` returns, a function of `{ name, parent }`, and reads back as the finished manifest:

```nix
{ config, lib, ... }:
{
  caisson.structural.configurations.inner = lib.caisson.structural.mkConfiguration { };
}
```

Each entry is finalized when it is read, with the attribute it is declared under as its name and the childless manifest of this evaluation as its parent. The names are known without finalizing anything, so `builtins.attrNames config.caisson.structural.configurations` evaluates no configuration.

A configuration declared beneath sees this one without the configurations declared beneath it (the childless view). In that view an entry's result is not readable, and reading it fails with a message saying so. A definition that reads an entry is therefore written under `!lib.caisson-core.evalManifest.childless`:

```nix
caisson.exports =
  if lib.caisson-core.evalManifest.childless then
    { }
  else
    config.caisson.structural.configurations.inner.outputs.exports;
```

An entry that is not a configuration, or is a configuration of another integration, is refused. Structural configurations are the ones that can be declared and can hold others so far: the constructors of the other integrations return an evaluated value, and an evaluation that carries no manifest (a flake-parts one) refuses to finalize an entry.

### `caisson.modules`

- **Type:** `attrsOf (submodule { export.enabled; exported; })`
- **Default:** `{}`
- **Source:** `modules/generic/core/caisson/modules.nix`

Export settings for each registered module class. Each class key defines:

- `export.enabled` (`bool`, default `true`)
- `exported` (`function -> attrsOf deferredModule`, default `modules: { }`)

The selected modules are published under `flake.modules.<class>`. For the `"flake"`
class specifically, the same modules are also mirrored to `flake.flakeModules`.

### `caisson.modules.<class>.export.enabled`

- **Type:** `bool`
- **Default:** `true`
- **Source:** `modules/generic/core/caisson/modules.nix`

Whether to export modules for a given class.

### `caisson.modules.<class>.exported`

- **Type:** `function -> attrsOf deferredModule`
- **Default:** `modules: { }`
- **Source:** `modules/generic/core/caisson/modules.nix`

Function that selects which modules in a class to publish under `flake.modules.<class>`.

### `caisson.libOverlays.export.enabled`

- **Type:** `bool`
- **Default:** `true`
- **Source:** `modules/generic/core/caisson/libOverlays.nix`

Whether to enable lib overlay export. When enabled, publishes the overlays selected by `caisson.libOverlays.exported` under `flake.libOverlays`.

### `caisson.libOverlays.exported`

- **Type:** `function -> attrsOf libOverlay`
- **Default:** `overlays: { }`
- **Source:** `modules/generic/core/caisson/libOverlays.nix`

Function that selects which registered library overlays to export as flake outputs. Receives the set of overlays registered via `mkLib` and returns the subset to publish under `flake.libOverlays`.
