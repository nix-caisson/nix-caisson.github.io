# Module Classes

## Overview

caisson models modules as class-keyed sets. A class is a string key used to group related modules and control where they are exported in flake outputs.

- Registered modules live under `modules.<class>.<name>`
- Exported modules are published under `flake.modules.<class>.<name>`

This builds on flake-parts' `flake.modules` output, which publishes modules under any class name, and adds closed-inputs module normalization.

## Registering a module

A flake laid out as `modules/<class>/<name>/default.nix` registers its
modules by naming the directory. `lib.caisson.mkModules` reads the
directory into the class-keyed registration, and it reads
`configs/<class>/<name>` the same way:

```nix
modules = lib: lib.caisson.mkModules ./modules;
configs = lib: lib.caisson.mkModules ./configs;
```

The first directory level is the class, whatever its name, and each
entry is registered with `lib.caisson.mkModule`, given the name of
that directory as the class. The integration that evaluates a class
names it in its declaration (the `class` argument of `mkIntegration`),
and caisson keeps no list of classes beside that. The class-free
`generic` group holds modules any class may import; the name comes
from flake-parts, whose export leaves those modules unstamped. An
entry is a directory holding a `default.nix`, a symlink to such a
directory included; anything else in a directory being read is an
error, so a stray file cannot silently vanish from a registry.

A tree with another layout writes the registration by hand, with the
`mkModule` of the integration that owns the class applied to the
module's path:

```nix
modules = lib: {
  flake.default = lib.caisson.flake-parts.mkModule ./modules/flake/default;
  nixos.my-service = lib.caisson.nixos.mkModule ./modules/nixos/my-service;
  homeManager.shell = lib.caisson.home-manager.mkModule ./modules/home-manager/shell;
  hardware.tpmFacts = lib.caisson.mkModule "hardware" ./modules/hardware/tpmFacts;
};
```

Each integration's `mkModule` is `lib.caisson.mkModule` bound to
that integration's class:

```nix
mkModule = class: freeformModule: ...
```

The class-string form is written out for a class no integration
covers.

## Core and default

The entry names `core` and `default` carry meaning in every class,
for every project a composition lists (caisson among them, no
differently):

- `core`: the framework module of the class. An integration forces
  every entry named `core` (`core`, `<project>/core`) into every
  evaluation of its class, before anything the evaluation selects.
  Registering a `core` is the big hammer, for a module the class cannot
  function without; the core module of caisson declares the
  `caisson.*` options every evaluation carries (the manifest, the
  registry selectors, `caisson.exports`).
- `default`: the default default. When an evaluation passes no
  `moduleImports`, every entry named `default` (`default`,
  `<project>/default`) applies; an evaluation that selects by name
  replaces that default with the list it names. The `default` of caisson
  for the `flake` class carries the nixpkgs integration's module
  layer.

The core module of caisson lives as the `generic` entry `core`;
`modules/structural/core` is a symlink to it and `modules/flake/core`
imports it and adds the flake mechanics, so each class that forces it
registers it as `core` in that class.

The class-specific normalizer applies the closure attrset
(`{ closure-inputs, closure-lib, mkModule, ... }`) as the module's first
arg list. The `mkModule` closure member is bound to the same class, so
nested use of `mkModule` stays in that class.

## Registration APIs

The class-keyed registry is in the manifest of the library, and
`lib.caisson.modules` reads it from there. Modules enter the registry
in these ways:

- **Local registration.** The `modules` argument of `mkLib` is a
  function that receives the composed `lib` and returns the class-keyed
  registration. `lib.caisson.mkModules` derives that registration from
  the conventional layout, and helpers such as
  `lib.caisson.flake-parts.mkModule` build entries by hand. This is
  for the flake's modules.
- **Project consumption**, `mkLib`'s `projects` hook: registering a
  whole upstream contribution (`projects.my-dep = inputs.my-dep`)
  places its exported modules in the registry under
  `<project>/<name>` per class, beside its overlays in the overlay
  dictionary. Selection stays per item at each use site, and a
  local registration beats a same-named project entry.

The registry is a shared, class-keyed space per composition. Names
within a class are a flat space: the entries of a project carry its
name as a prefix (`my-flake/my-service`), and short names are for the
registrations made in the `mkLib` call itself. Precedence is
deterministic: those local registrations apply last, so a local entry
wins over a project entry of the same name.

Use class `flake` for flake-parts modules and other class keys for other module ecosystems. The shipped integrations (`caisson.nixos`, `caisson.darwin`, `caisson.home-manager`, `caisson.hjem`, `caisson.terranix`, `caisson.caisson-colmena`, `caisson.colmena`, `caisson.caisson-disko`, `caisson.disko`, `caisson.caisson-facter`, `caisson.facter`, `caisson.system-manager`, `caisson.treefmt`, and `caisson.nixpkgs`) each name their class in their declaration (the class of caisson-colmena is `caisson-colmena`, and the class of caisson-disko is `caisson-disko`; the nodes of a colmena configuration and the machines of a disko configuration are NixOS configurations); see the [library reference](../reference/lib.md).

## Consuming Exported Modules

A downstream flake can import modules published under any class via the upstream flake's `modules` output:

```nix
# In a downstream NixOS configuration:
imports = [ inputs.my-upstream.modules.nixos.myModule ];

# In a downstream home-manager configuration:
imports = [ inputs.my-upstream.modules.homeManager.myModule ];
```

The exported modules have their inputs already closed over, so importing them is possible without threading the upstream's dependencies.

## Export Controls

Per-class export controls live under:

- `caisson.modules.<class>.export.enabled`
- `caisson.modules.<class>.exported`

The exported modules are in the manifest. `mkLib` reads them from
there for each entry of `projects`.

The exported modules are also published under
`flake.modules.<class>.<name>`, for an import by hand.
`caisson.flakeOutputs.modules` selects which exported modules that
output holds, and it defaults to every exported module. A module
that only works inside an evaluation that caisson makes can be
exported and left out of the output:

```nix
caisson.flakeOutputs.modules =
  modules: modules // { nixos = removeAttrs modules.nixos [ "needs-caisson" ]; };
```

For flake-parts compatibility, `flake.flakeModules` mirrors
`flake.modules.flake`, and the `flake` class always exports a `default`
entry (an empty module unless the selection provides it) so
`flakeModules.default` exists for consumers that import it by
convention.

## Relationship to flake-parts

The `flake.modules` output is provided by flake-parts' `modules` extra module. When caisson wires exported modules into `flake.modules.<class>.<name>`, flake-parts stamps each module with `_class` and `_file` metadata. This means exported modules carry their class identity and source location, which module systems can use for diagnostics and class-checking (e.g., preventing a `nixos` module from being accidentally imported into a `homeManager` evaluation).
