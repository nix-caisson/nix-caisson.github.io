# Ecosystem sources

Each integration takes its ecosystem as an argument, the ecosystem
source, and calls the evaluator inside that source; it pins nothing
itself. A
caisson revision therefore works with any nixpkgs, home-manager, or
colmena revision with a compatible evaluation contract, and two
consumers of that same caisson revision can pin different revisions
of each ecosystem.

## What a source is

An ecosystem is a community library outside of caisson at the center
of an extensible Nix abstraction framework. Most ecosystems are built
on NixOS modules, but some use other abstractions
(a package set, a `lib` ecosystem). The ecosystem source is that
project's source tree or
flake, in whatever shape its evaluator expects. Each integration
documents the shape it takes; in practice:

- `caisson.nixos` takes the NixOS module collection under the `nixos`
  key (it evaluates `nixos/lib/eval-config.nix` from it);
  `caisson.nixos-minimal` takes the same key and evaluates
  `nixos/lib`'s `evalModules` from it.
- `caisson.nixpkgs` takes a nixpkgs source tree under the `nixpkgs`
  key, for the package set and its configuration.
- `caisson.darwin` takes the nix-darwin flake or source tree (it
  evaluates `eval-config.nix` from it).
- `caisson.home-manager` takes a home-manager source tree.
- `caisson.hjem` takes the hjem flake or source tree (it evaluates the
  user module `modules/common/user.nix` from it, with hjem's library
  from `lib.nix`).
- `caisson.caisson-colmena` and `caisson.colmena` take the colmena
  flake: they read the hive schema from its `lib.makeHive` and the
  deployment options from its `nixosModules`.
- `caisson.caisson-disko` and `caisson.disko` take the disko flake or
  source tree: they build disko's type library from its
  `lib/default.nix`, and `caisson.disko` gives its machines the NixOS
  module in its `module.nix`.
- `caisson.terranix` and `caisson.system-manager` take their project's
  flake (they call `lib.terranixConfiguration` and
  `lib.makeSystemConfig` on it). `caisson.system-manager` also takes
  the `nixos` key, for the NixOS module collection it mixes into the
  evaluation.
- `caisson.flake-parts` takes a flake-parts source tree and calls its
  `flake.nix` with the composed library as `nixpkgs-lib`.

## The three parts of a nixpkgs checkout

A nixpkgs checkout holds three separate parts, and each is resolved
from a separate key, with no fallback between keys:

- `nixpkgs-lib`: the library (`lib/`: the module system
  `lib.evalModules`, `lib.types`, `lib.mkOption`, and the rest), which
  the `nixpkgs-lib` entry composes into the lib.
- `nixpkgs`: the package set and its configuration
  (`pkgs/top-level`).
- `nixos`: the NixOS module collection (`nixos/modules`,
  `nixos/lib/eval-config.nix`), read by NixOS configurations and by
  system-manager for its NixOS modules. It is the module collection,
  not the Linux distribution; the distribution is one use of the
  collection.

A key a tree does not declare resolves to the source pinned under
exactly that name in `sources`. A tree that takes several parts from
one checkout names that checkout under each key. Every tree uses
`nixpkgs-lib`; a tree with package sets uses `nixpkgs`; a tree with
NixOS or system-manager configurations uses `nixos`. The parts may
come from different sources on purpose: the nixpkgs.lib mirror
supplies the library, and one revision of the module collection runs
on the library of another revision.

A tree with a single nixpkgs checkout, pinned under the input name
`nixpkgs`, names that checkout under the other two keys with
`defaultEcosystemSrc`:

```nix
caisson.lib.caisson.mkLib {
  inherit sources root;
  defaultEcosystemSrc = sources: {
    nixpkgs-lib = sources.nixpkgs;
    nixos = sources.nixpkgs;
  };
};
```

The `nixpkgs` key needs no entry here: the source pinned under the
input name `nixpkgs` already resolves there, through the exact-name
fallback below.

### The library of a project that other flakes list

We recommend that a project other flakes list in `projects` take its
library from the nixpkgs.lib mirror, a repository that holds only the
`lib/` directory of nixpkgs:

```nix
inputs.nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
```

A flake that lists a project reads the outputs of that project, and
reading them builds the lib of the project. Building that lib fetches
the library source the project pins. The mirror is about 1.4 MB in the
store, and a nixpkgs checkout is about 210 MB. A flake that lists
several projects fetches the library source of each of them, once per
distinct revision.

The mirror follows the `master` branch of nixpkgs and is updated about
once a week. Its revision is therefore rarely the revision of the
nixpkgs a package set comes from. A project that only publishes
modules and overlays runs only its registrations and its top
configuration on its library. The flakes that list it evaluate its
modules and overlays on their own lib, so the difference does not
reach them. A project that also builds packages or configurations runs
them on general utilities and a module system of the mirror revision.

nixpkgs' library holds two kinds of library. The general utilities
(`strings`, `lists`, `attrsets` and the rest) and the module system
(`modules`, `options`, `types`) serve every evaluation, and a tree
supplies them from its `nixpkgs-lib` key. The package-set libraries
describe and build packages:

- `systems` and `platforms`, the platform model;
- `meta`, `licenses`, `sourceTypes`, `maintainers` and `teams`, the
  package metadata;
- `customisation`, which holds `callPackageWith` and `makeOverridable`;
- `derivations`, `fetchers` and `versions`.

Inside a package set, the nixpkgs integration takes the package-set
libraries from the source of that package set, together with the
names nixpkgs publishes from them at the top level of its library,
such as `lib.getExe` and `lib.callPackageWith`. The packages of a set
are written against those libraries at the revision of the set. The
general utilities still come from the mirror, which follows the
unstable branch, so a package set of a stable release meets the
general utilities of a later revision wherever its packages call them. nixpkgs reads `maintainers` and `teams`
from its `maintainers` directory beside `lib/`, so a package set
needs them from the source of the package set in any case.

The module system still comes from `nixpkgs-lib`. A NixOS
configuration whose `nixos` key names a stable release runs that
module collection on the module system of the mirror.

## Which integration uses which ecosystem

One ecosystem may be wrapped by several integrations, each with a
different evaluator over the same source. The name in the second column is
what the integration resolves its source by, in the places listed
below.

| Integration | Ecosystem name | Source shape |
| --- | --- | --- |
| `caisson.flake-parts` | `flake-parts` | flake-parts source tree |
| `caisson.nixpkgs` | `nixpkgs` | nixpkgs source tree (package set and configuration) |
| `caisson.nixos` | `nixos` | nixpkgs source tree (the NixOS module collection) |
| `caisson.nixos-minimal` | `nixos` | nixpkgs source tree (the `nixos` class under the minimal evaluator) |
| `caisson.darwin` | `nix-darwin` | nix-darwin flake or source tree |
| `caisson.home-manager` | `home-manager` | home-manager source tree |
| `caisson.hjem` | `hjem` | hjem flake or source tree |
| `caisson.caisson-colmena` | `colmena` | colmena flake |
| `caisson.colmena` | `colmena` | colmena flake |
| `caisson.caisson-disko` | `disko` | disko flake or source tree |
| `caisson.disko` | `disko` | disko flake or source tree |
| `caisson.terranix` | `terranix` | terranix flake |
| `caisson.system-manager` | `system-manager`, and `nixos` for its NixOS modules | system-manager flake |
| `caisson.treefmt` | `treefmt-nix` | treefmt-nix flake or source tree |
| `caisson.nvf` | `nvf` | nvf flake |
| `caisson.nixvim` | `nixvim` | nixvim flake |
| `caisson.topology` | `nix-topology` | nix-topology flake or source tree |
| `caisson.kubenix` | `kubenix` | kubenix flake or source tree |
| `caisson.nixidy` | `nixidy` | nixidy flake |
| `caisson.structural` | none | no source: the empty integration evaluates caisson's core module alone |

The nixpkgs library that the integrations call is loaded by the
`nixpkgs-lib` integration of caisson, from the source resolved under
the `nixpkgs-lib` key.

## How does caisson get access to ecosystem sources?

A source comes from one of these places, in priority order:

1. **Explicit argument.** `ecosystemSrc` at the call site always
   wins. It is a function of the tree's `sources`, returning the
   source for that call; a value given in place of the function is
   refused. `ecosystemSrc = sources: sources.nixpkgs;` names an input
   called `nixpkgs` explicitly. It replaces the source for that
   evaluation and nothing else: a level cannot set sources for the
   levels beneath it. A package config on a different nixpkgs
   revision writes
   `ecosystemSrc = sources: sources.nixpkgs-stable;`.
2. **Composition default.** `defaultEcosystemSrc` on `mkLib` is a
   function of `sources`, returning the source of each ecosystem by
   its exact key:
   `defaultEcosystemSrc = sources: { nixpkgs-lib = sources.nixpkgs; nixos = sources.nixpkgs; };`.
   An attribute set given in place of the function is refused.
3. **Exact-name source.** As a final fallback, the source named
   exactly like the key (`nixpkgs`, `home-manager`, and the rest) in
   the `sources` passed to `mkLib` is used. For a flake that declares
   that input anyway, this is the common case.

If none of these places can provide a needed ecosystem source,
it triggers an evaluation error.

A NixOS configuration that selects another module collection with
`ecosystemSrc` still runs its evaluation on the library of the tree;
only the source under the `nixos` key changes.

### Where each source came from

The manifest of every configuration records `ecosystems`: for each
part of the stack its evaluation used, which of the three places
supplied the source and which pinned source it is.

```nix
{
  nixpkgs-lib = { from = "defaultEcosystemSrc"; source = "nixpkgs"; };
  nixos = { from = "ecosystemSrc"; source = "nixpkgs"; };
}
```

`from` is `ecosystemSrc`, `defaultEcosystemSrc` or `sources`, in the
order above. `source` is the name of the source among the pinned
sources, where the manifest records its revision under
`sources.<name>.pin`. It is null when a selection builds the value in
another way, such as a directory inside a source. A package config
also lists, under `nixpkgs.libraries`, the names its sets take from
the source of the package set
([`ecosystemAccountOf`](../reference/lib.md#ecosystemaccountof) has the
details).
