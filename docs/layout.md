# Repository Layout

caisson mandates nothing about layout beyond the repository being a
flake: registration takes paths, and any arrangement evaluates. We
recommend the conventions below because they have proven to work for
us, they resolve ambiguity about where a thing belongs, and they make
it easier for someone new to a repository to come up to speed. This
repository and its integrations use them, and the documentation and
the `examples/literate-flake` example assume them.

## flake.nix

Wiring only: `mkLib` and `mkFlake`. The substance lives in the
directories below.

## configs/

```
configs/<class>/<config>/
```

Configurations, grouped by module class and named for **what they
configure**. A flake-parts config configures the flake itself, so there
is typically exactly one, named after the flake (this repository uses
`configs/flake-parts/caisson/`) or `default`. In other classes,
a config is named for the thing it describes: a machine, a home, a
deployment.

## lib-overlays/

```
lib-overlays/<overlay>/
```

Library overlays by overlay name; most flakes start with a single
overlay called `default`. Each is a file taking the closure arg list
and returning `{ imports ? [ ], overlay }`; see
[Library Overlays](concepts/library-overlays.md).

## modules/

```
modules/<class>/<module>/default.nix
modules/<class>/<module>/<flake-name>/*.nix
```

Reusable modules, keyed first by module class (directory names use the
ecosystem's name: `flake-parts`, `nixos`, `home-manager`), then by the
module's own name; the conventional exported module is
`modules/<class>/default/`. `default.nix` is the module's entry point,
and its implementation files sit under a directory named for the
defining flake, grouped by the option namespace they declare, in this
repository, `modules/flake-parts/default/caisson/lib.nix` declares the
`caisson.lib.*` options.

## pkgs/

```
pkgs/<package>/            # or, in flakes with many packages:
pkgs/<flake-name>/<package>/
```

Package definitions. How package sets and package overlays are composed
and surfaced as outputs is the domain of `caisson-nixpkgs` (in active
use, not yet published); until its documentation is available, `pkgs/`
is best read as the conventional home for package expressions.

## Package overlays

Package overlays follow the same safety ideas as library overlays
(namespacing, input closure) but their tooling belongs to
`caisson-nixpkgs`, not to caisson itself. See
[Library Overlays](concepts/library-overlays.md) for the
shared principles.

## tests/

```
tests/unit/           # pure evaluation tests, wired into checks
tests/integration/    # nested flakes that consume this flake
tests/dependencies/   # a small flake whose lock pins test-only inputs
```

Unit tests are pure Nix expressions evaluated as a check. Integration
tests are nested flakes that take the project as an input and assert
that composition behaves as documented: consumption tested from the
outside, the way a consumer would experience it. `tests/dependencies/`
is a lock-bearing flake that pins inputs used only by the test and
formatter machinery, so the main `flake.lock` stays free of
test-only pins (it feeds the checks partition via
`partitionExtraInputs`). The [Testing](./testing.md) page covers how the
nested flakes are evaluated.

## Other directories

`examples/` (worked examples; `examples/literate-flake/` here) and
`docs/` (these pages) appear where a repository has use for them.
