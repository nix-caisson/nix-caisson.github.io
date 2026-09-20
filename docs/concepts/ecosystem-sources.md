# Ecosystem sources

Integrations do not pin their ecosystems: `caisson.nixos` has no
nixpkgs pin, and `caisson.home-manager` has no home-manager pin. You
pass the ecosystem in, as an argument called the ecosystem source, and
the integration calls the evaluator inside that source. A single
caisson revision therefore works with any nixpkgs, home-manager, or
colmena revision with a compatible evaluation contract, and two
consumers of that same caisson revision can pin different revisions
of each ecosystem.

## What a source is

An ecosystem is a community library outside of caisson at the center
of an extensible Nix abstraction framework. Most ecosystems are built
on NixOS modules, but some use other abstractions
(e.g. package sets, `lib` ecosystems). The ecosystem source is that
project's source tree or
flake, in whatever shape its evaluator expects. Each integration
documents the shape it takes; in practice:

- `caisson.nixos` takes a nixpkgs source tree (it evaluates
  `nixos/lib/eval-config.nix` from it).
- `caisson.home-manager` takes a home-manager source tree.
- `caisson.colmena`, `caisson.terranix`, and
  `caisson.system-manager` take their project's flake (they call
  `lib.makeHive`, `lib.terranixConfiguration`, and
  `lib.makeSystemConfig` on it).
- `caisson.flake-parts` takes a flake-parts source tree and calls its
  `flake.nix` with the composed library as `nixpkgs-lib`.

## Which integration uses which ecosystem

One ecosystem may be wrapped by several integrations, each with its
own evaluator over the same source. The name in the second column is
what the integration resolves its source by, in the three places
listed below.

| Integration | Ecosystem name | Source shape |
| --- | --- | --- |
| `caisson.flake-parts` | `flake-parts` | flake-parts source tree |
| `caisson.nixpkgs` | `nixpkgs` | nixpkgs source tree (per package set, as `pkgFunction`) |
| `caisson.nixos` | `nixpkgs` | nixpkgs source tree |
| `caisson.home-manager` | `home-manager` | home-manager source tree |
| `caisson.colmena` | `colmena` | colmena flake |
| `caisson.terranix` | `terranix` | terranix flake |
| `caisson.system-manager` | `system-manager` | system-manager flake |

The nixpkgs library that every composed lib is built over is resolved
separately by caisson-core, under the name `nixpkgs-lib`, falling back
to `nixpkgs`.

## How does caisson get access to ecosystem sources?

A source comes from one of three places, in priority order:

1. **Explicit argument.** `ecosystemSrc = inputs.nixpkgs` at the
   call site always wins.
2. **Composition default.** `defaultEcosystemSrc.nixpkgs = inputs.nixpkgs`
   in the `mkLib` call declares the composition's default for that name.
3. **Exact-name input.** As a final fallback, the entry named exactly
   like the ecosystem (`nixpkgs`, `home-manager`, ...) in the `inputs`
   passed to `mkLib` is used. For a flake that declares that input
   anyway, this is the common case.

If none of the three places can provide a needed ecosystem source,
it triggers an evaluation error.
