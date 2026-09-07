# Choosing a flake framework

Where caisson sits relative to plain flake-parts, flakelight,
snowfall-lib, and the dendritic pattern, characterized from those
projects' own documentation. The honest summary first: all five
produce working flakes, and the differences are about which
conventions you want enforced by machinery rather than by
discipline.

## Plain flake-parts

flake-parts is a minimal module system mirroring the flake schema:
it splits configuration into modules, handles `perSystem`, and
deliberately avoids broader opinions, positioning itself as "a single
module that other repositories can build upon" with an ecosystem of
independent compatible modules.

caisson is built on flake-parts and keeps all of it. What it adds is
a set of enforced conventions on top: closed inputs (every registered
file takes an explicit closure argument list instead of reaching for
inputs ambiently), namespaced library overlays with declared
dependencies composed by caisson-core, class-keyed
module registration and export, integrations that take their
ecosystems as explicit `ecosystemSrc` arguments, and measured
evaluation-cost gates. Use plain flake-parts when you want the module
system and your own conventions; use caisson when you want these
conventions machine-enforced, particularly across several flakes that
consume each other's libraries and modules.

## flakelight

flakelight is a module-driven framework emphasizing automation:
sensible defaults, automatic import of nix files from a directory,
and auto-generated outputs (packages, overlays, formatters), with the
stance that what can be done automatically, should be.

caisson leans the other way: registration is explicit, namespaces are
explicit, dependencies between overlays are declared, and nothing is
inferred from file layout. If you value minimal ceremony in a single
project, flakelight gets a working flake with fewer lines. If you
value being able to trace any attribute of a composed library to a
declared registration, especially across a fleet of interdependent
flakes, that explicitness is caisson's point.

## snowfall-lib

snowfall-lib generates systems, packages, modules, and shells from
directory-structure conventions: predictable filesystem hierarchies
in exchange for eliminated boilerplate, targeting multi-system NixOS
and nix-darwin setups. Its repository currently describes it as
seeking new maintainers.

The comparison is similar to flakelight but stronger: snowfall infers
the most from layout, caisson infers nothing from layout. caisson's
integrations also differ structurally from a generator: they are thin
adapters over each ecosystem's evaluator, taking the ecosystem as an
explicit source argument and pinning nothing.

## The dendritic pattern

The dendritic pattern is an organizational discipline over
flake-parts rather than a framework: every Nix file except the entry
points is a module of the top-level configuration, each file
implements one feature across all the configurations it touches, and
lower-level modules (NixOS, home-manager, nix-darwin) live as
`deferredModule` values inside the top-level config, merged by name.
Files are commonly auto-imported with import-tree, and cross-cutting
values are read from the shared top-level `config` instead of
`specialArgs` threading.

caisson agrees with more of this than with the generators above:
both build on flake-parts, both eliminate ambient `specialArgs`
plumbing (dendritic through the shared top-level config, caisson
through closed inputs and the composed library), and both group
modules by the module system they belong to (dendritic by option
path, caisson by class key). The differences are scope and
mechanism. Dendritic organizes one repository's configurations by
feature and, with import-tree, derives the import set from the file
tree; caisson registers modules and overlays explicitly and
infers nothing from layout. Dendritic keeps everything inside a
single module evaluation; caisson separates library composition from
module evaluation and adds export machinery so several repositories
can publish and consume each other's overlays and modules. Use
dendritic to structure one flake's configurations by aspect with
almost no machinery; use caisson when the unit of reuse is a
repository and the conventions need to hold across a fleet.

## What is caisson-specific

Independently of the convention trade-offs above, three things are
distinctive here rather than variations on a shared theme:

- **Library composition with identity**
  ([deep dive](deep-dives/how-lib-is-composed.md)): dedup, wholesale
  replacement, and reliable polyfills, implemented in caisson-core, a
  zero-dependency flake usable without caisson.
- **Explicit ecosystem sources**: integrations pin none of their
  ecosystems; the consumer hands each in, so a single caisson
  revision works with any nixpkgs, home-manager, or colmena revision
  with a compatible evaluation contract.
- **Evaluation-weight gates** ([guide](eval-weight.md)): framework
  overhead is measured and held to committed ceilings in CI rather
  than described.

## The relationship to flakes

Flakes do two jobs today: acquisition (fetching, pinning, integrity)
and composition (deciding which copy of each dependency an evaluation
actually uses, via the `follows` pin bucket). caisson separates the
two. Flakes keep acquisition. Composition moves to the evaluation
layer, with real semantics: deduplication is
key identity, override is wholesale replacement of a keyed entry,
local patches are the keyless tail, and ecosystems (nixpkgs,
home-manager, and the rest) are handed in as explicit
`ecosystemSrc` arguments instead of being re-pinned and re-wired
through the input graph.

Everything caisson adds is published through the flake schema's only
freeform slot, the `lib` output: composed libraries, the module
registry, and the manifest (the composition's self-description) all
live there, and the remaining flake outputs (`modules.<class>`,
`libOverlays`, per-system products) are projections from it that keep
the standard schema's addresses. A flake built this way needs only a
small, regular subset of the flake schema; nothing about it requires
upstream changes to evaluate.
