# Module Classes

## Overview

caisson models modules as class-keyed sets. A class is a string key used to group related modules and control where they are exported in flake outputs.

- Registered modules live under `modules.<class>.<name>`
- Exported modules are published under `flake.modules.<class>.<name>`

This builds on flake-parts' `flake.modules` output, which publishes modules under any class name, and adds closed-inputs module normalization.

## Registering a module

A tree laid out as `modules/<class>/<name>/default.nix` registers its
modules by naming the directory: `caisson-core.mkModules` reads it
into the class-keyed registration, applying
`lib.caisson-core.mkModule <class>` to each entry, and the same
reader serves `configs/<class>/<name>`:

```nix
modules = core.mkModules ./modules;
configs = core.mkModules ./configs;
```

The first directory level is the class, whatever its name, so a class
no integration covers (`hardware`, the way ch-hardware defines one for
its capture modules) and the class-free `generic` group (a module any
class may import; the name comes from flake-parts, whose export
leaves those modules unstamped) read the same way. An entry is a
directory holding a `default.nix`, a symlink to one included;
anything else in a directory being read is an error, so a stray file
cannot silently vanish from a registry.

A tree with another layout writes the registration by hand, with the
`mkModule` of the integration that owns the class applied to the
module's path:

```nix
modules = lib: {
  flake.default = lib.caisson.flake-parts.mkModule ./modules/flake/default;
  nixos.my-service = lib.caisson.nixos.mkModule ./modules/nixos/my-service;
  homeManager.shell = lib.caisson.home-manager.mkModule ./modules/home-manager/shell;
  hardware.tpmFacts = lib.caisson-core.mkModule "hardware" ./modules/hardware/tpmFacts;
};
```

Each integration's `mkModule` is `lib.caisson-core.mkModule` bound to
that integration's class:

```nix
mkModule = class: freeformModule: ...
```

The class-string form is written out for a class no integration
covers.

## Core and default

Two entry names carry meaning in every class, for every project a
composition lists (caisson among them, no differently):

- `core`: the framework module of the class. An integration forces
  every entry named `core` (`core`, `<project>/core`) into every
  evaluation of its class, before anything the evaluation selects.
  Registering one is the big hammer, for a module the class cannot
  function without; the core module of caisson declares the
  `caisson.*` options every evaluation carries (the manifest, the
  registry selectors, `caisson.exports`).
- `default`: the default default. When an evaluation passes no
  `moduleImports`, every entry named `default` (`default`,
  `<project>/default`) applies; an evaluation that selects by name
  replaces that default with its own list. The `default` of caisson
  for the `flake` class carries the nixpkgs integration's module
  layer.

The core module of caisson lives once, as the `generic` entry `core`;
`modules/structural/core` is a symlink to it and `modules/flake/core`
imports it and adds the flake mechanics, so each class that forces it
registers it under its own name.

The class-specific normalizer applies the closure attrset
(`{ closure-inputs, closure-lib, mkModule, ... }`) as the module's first
arg list. The `mkModule` closure member is bound to the same class, so
nested use of `mkModule` stays in that class.

## Registration APIs

Modules enter the class-keyed registry (`lib.caisson-core.modules`)
in three ways:

- **Local registration**, `mkLib`'s `modules` hook: a function
  `lib: { ... }` receiving the composed `lib` (whose helpers, like
  `lib.caisson.flake-parts.mkModule`, build the entries) and returning the
  class-keyed registration, which `caisson-core.mkModules` derives
  from the conventional layout. This is for the flake's own modules.
- **Overlay contribution**, for modules contributed by a library
  overlay: the overlay closure contains `mkModule` and
  `contributeModules`, and the overlay merges its entries into the
  registry:

  ```nix
  { mkModule, contributeModules, ... }:
  {
    imports = [ ];
    overlay =
      final: prev:
      contributeModules prev {
        nixos."my-flake/my-service" = mkModule "nixos" ./modules/my-service.nix;
      }
      // {
        my-flake = (prev.my-flake or { }) // { ... };
      };
  }
  ```

  `mkModule` here is bound to the defining flake's composition, so the
  contributed module closes over the definer's inputs and library, not
  the consumer's. A consumer who registers the exported overlay gets
  its library namespace and its modules together, transitively through
  the overlay's `imports` chain; no re-registration is involved.
- **Project consumption**, `mkLib`'s `projects` hook: registering a
  whole upstream contribution (`projects.my-dep = inputs.my-dep`)
  places its exported modules in the registry under
  `<project>/<name>` per class, beside its overlays in the overlay
  dictionary. Selection stays per item at each use site, and a
  local registration beats a same-named project entry.

The registry is a shared, class-keyed space per composition, so two
rules keep multiple contributors coherent. Names within a class are a
single flat space: qualify contributed names with your project prefix
(`my-flake/my-service`), the same discipline as top-level library
namespaces; short names are for the registrations made in the `mkLib`
call itself. And precedence is deterministic: those local
registrations apply last, so a local entry always wins over a
same-named contribution.

Use class `flake` for flake-parts modules and other class keys for other module ecosystems. The shipped integrations (`caisson.nixos`, `caisson.home-manager`, `caisson.terranix`, `caisson.colmena`, `caisson.system-manager`, and `caisson.nixpkgs`) each register their own class this way (colmena's class is `colmena`; its nodes are NixOS configurations); see the [library reference](../reference/lib.md).

## Consuming Exported Modules

A downstream flake can import modules published under any class via the upstream flake's `modules` output:

```nix
# In a downstream NixOS configuration:
imports = [ inputs.my-upstream.modules.nixos.myModule ];

# In a downstream home-manager configuration:
imports = [ inputs.my-upstream.modules.homeManager.myModule ];
```

The exported modules have their inputs already closed over, so importing one is possible without threading the upstream's dependencies.

## Export Controls

Per-class export controls live under:

- `caisson.modules.<class>.export.enabled`
- `caisson.modules.<class>.exported`

For flake-parts compatibility, `flake.flakeModules` mirrors
`flake.modules.flake`, and the `flake` class always exports a `default`
entry (an empty module unless the selection provides one) so
`flakeModules.default` exists for consumers that import it by
convention.

## Relationship to flake-parts

The `flake.modules` output is provided by flake-parts' `modules` extra module. When caisson wires exported modules into `flake.modules.<class>.<name>`, flake-parts stamps each module with `_class` and `_file` metadata. This means exported modules carry their class identity and source location, which module systems can use for diagnostics and class-checking (e.g., preventing a `nixos` module from being accidentally imported into a `homeManager` evaluation).
