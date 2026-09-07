# Module Classes

## Overview

caisson models modules as class-keyed sets. A class is a string key used to group related modules and control where they are exported in flake outputs.

- Registered modules live under `modules.<class>.<name>`
- Exported modules are published under `flake.modules.<class>.<name>`

This builds on flake-parts' generic `flake.modules` support while adding closed-inputs module normalization.

## mkModule Factory

`lib.caisson-core.mkModule` is class-parameterized:

```nix
mkModule = class: freeformModule: ...
```

Example:

```nix
modules = {
  flake = {
    default = lib.caisson.mkFlakeModule ./modules/flake-parts/default;
  };

  generic = {
    helper = lib.caisson-core.mkModule "generic" ./modules/generic/helper;
  };
};
```

The returned class-specific normalizer applies the closure attrset
(`{ closure-inputs, closure-lib, mkModule, ... }`) as the module's first
arg list. The `mkModule` closure member is bound to the same class, so
nested use of `mkModule` stays in that class.

## Registration APIs

Modules enter the class-keyed registry (`lib.caisson-core.modules`)
in three ways:

- **Local registration**, `mkLib`'s `modules` hook: a function
  `lib: { ... }` receiving the composed `lib` (whose helpers, like
  `lib.caisson.mkFlakeModule`, build the entries) and returning the
  class-keyed registration. This is for the flake's own modules.
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
namespaces; short names are for the composing flake's own
registrations. And precedence is deterministic: the composing flake's
local registrations apply last, so a local entry always wins over a
same-named contribution.

Use class `flake` for flake-parts modules and other class keys for other module ecosystems. The shipped integrations (`caisson.nixos`, `caisson.home-manager`, `caisson.terranix`, `caisson.colmena`, `caisson.system-manager`, and `caisson.nixpkgs`) each register their own class this way; see the [library reference](../reference/lib.md).

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
