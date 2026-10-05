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

The manifest of this evaluation: its `type`, `name`, `parent` and `children`, and the registries and declared facts of the composition it is declared under, which are `sources`, `defaultEcosystemSrc`, `systems` and `projects` as given to `mkLib`, plus the registered `libOverlays` and `modules` dictionaries (project entries under `<project>/<name>`, locals winning). Structural, flake-parts and NixOS configurations carry a manifest. Reading it type-checks the manifest; the `flake.modules` and `flake.libOverlays` projections are drawn from it, and flake-parts' `systems` defaults to the manifest's `systems`, the empty list when the composition declares none, so such a flake has no per-system outputs (`modules/flake/core/caisson/systems.nix`).

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

Each entry is finalized when it is read, with the attribute it is declared under as its name and the childless manifest of this evaluation as its parent. An entry of an integration that evaluates a configuration at a system (nixos) reads back as its evaluations by system, `config.caisson.nixos.configurations.laptop.x86_64-linux`, a manifest for every system in force. The names are known without finalizing anything, so `builtins.attrNames config.caisson.structural.configurations` evaluates no configuration.

A configuration declared beneath sees this configuration without the configurations declared beneath it (the childless view). In that view an entry's result is not readable, and reading it fails with a message saying so. A definition that reads an entry is therefore written under `!lib.caisson-core.evalManifest.childless`:

```nix
# an option of this configuration, defined from a configuration beneath it
innerGreeting =
  if lib.caisson-core.evalManifest.childless then
    null
  else
    config.caisson.structural.configurations.inner.value.config.greeting;
```

A module that only declares configurations needs no such test. What the configurations beneath export is passed up without that test, through `caisson.<integration>.exported` below.

An entry that is not a configuration, or is a configuration of another integration, is refused. Structural, flake-parts and nixos configurations can be declared. A configuration of an integration that evaluates a class another integration owns is a configuration of the owner in the tree: `lib.caisson.nixos-minimal.mkConfiguration` returns a nixos configuration, declared under `caisson.nixos.configurations` and published with the others. The constructors of the remaining integrations return an evaluated value. A configuration holds configurations of any integration beneath it.

### `caisson.<integration>.exported`

- **Type:** function from the configurations declared to an attribute set of them
- **Default:** `configurations: configurations`, every configuration declared
- **Source:** `modules/generic/core/caisson/configurations.nix`

Function that selects which of the configurations declared under `caisson.<integration>.configurations` this configuration passes up. What each selected configuration exports (its `outputs.exports`: `lib`, `libOverlays`, `modules`, `pkgOverlays`) is merged into this configuration's `caisson.exports`, beside what the registry selectors here choose. A configuration beneath passes up what lies beneath it in turn, so the exports of a tree of structural configurations reach its top with nothing written:

```nix
{ lib, ... }:
{
  caisson.structural.configurations.impl = lib.caisson.structural.mkConfiguration { };
}
```

The configurations themselves are passed up as well, each with its path, and the top publishes them under the output attribute set their integration declares, named from the paths:

```nix
{ lib, ... }:
{
  caisson.nixos.configurations.laptop = lib.caisson.nixos.mkConfiguration { };
}
```

publishes `nixosConfigurations.laptop` from a flake-parts or structural top. A name that is alone stays bare. Names that collide gain the segments that tell them apart, from the segment nearest the top: `host-1` declared in the structural configurations `a` and `b` is published as `a/host-1` and `b/host-1`, and a configuration with several systems in force as `x86_64-linux/laptop` and `aarch64-linux/laptop`. Configurations that still share a name are refused, with their paths.

`caisson.structural.exported = _: { };` passes up none, and a selector returning a subset passes up those. The merge is made in the evaluation that holds the configurations: it is absent from the childless view, and from an evaluation that carries no manifest.

### `caisson.forChildren.modules`

- **Type:** `attrsOf (attrsOf deferredModule)`, by class and then name
- **Default:** `{ }`
- **Source:** `modules/generic/core/caisson/forChildren.nix`

Modules registered for the configurations beneath this configuration. An entry joins the registry of its class as those configurations see it (`lib.caisson-core.modules.<class>.<name>`), where a configuration selects it with `moduleImports`:

```nix
{ lib, ... }:
{
  caisson.forChildren.modules.nixos.gaming =
    { pkgs, ... }:
    {
      programs.steam.enable = true;
    };

  caisson.nixos.configurations.desktop = lib.caisson.nixos.mkConfiguration {
    moduleImports = modules: [ modules.gaming ];
  };
}
```

A registration joins the registry that the configurations of the class beneath this one select from, including nested ones and ones beneath a configuration of another integration. A configuration imports it when its selection names it. The registry of this configuration is unchanged. An entry under a name the registry already holds replaces it beneath this configuration. Definitions of the same entry from several modules merge.

A configuration with a configuration beneath it is evaluated in both views, since its registrations are read from the childless view.

### `caisson.forChildren.defaultModuleImports`

- **Type:** `attrsOf (functionTo (listOf module))`, by class
- **Default:** `{ }`
- **Source:** `modules/generic/core/caisson/forChildren.nix`

Additions to the default selection of a class for the configurations beneath this configuration: a function of the lib of such a configuration returning registered modules.

```nix
{ ... }:
{
  caisson.forChildren.defaultModuleImports.nixos = lib: [ lib.caisson-core.modules.nixos.gaming ];
}
```

A configuration that passes no `moduleImports` gets every entry named `default` followed by these, those of the levels above it first. A configuration that passes `moduleImports` gets what it selects in place of that default, and one that passes `extraModuleImports` gets what that selects in addition. Definitions from several modules are concatenated.

### `caisson.forChildren.defaultPkgs`

- **Type:** `nullOr (functionTo pkgs)`
- **Default:** `null`
- **Source:** `modules/generic/core/caisson/forChildren.nix`

The package set the configurations beneath this configuration get by default: a function that receives the package sets available to such a configuration, as an attribute set by package config name, and returns the set to run on.

```nix
{ ... }:
{
  caisson.forChildren.defaultPkgs = pkgSets: pkgSets.stable;
}
```

Here the default beneath this configuration is the set of the package config named `stable`. A configuration beneath runs on it unless that configuration, or a configuration between the two, is constructed with `defaultPkgs` or sets this option. This configuration runs on the set it was constructed with. When the option is null, the default beneath is the selection in force at this configuration.

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
