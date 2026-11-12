# FAQ

### What goes wrong without caisson that this fixes?

Caisson addresses major failure patterns seen in poly-flake
setups:

First, input explosion: a flake-parts module that uses `inputs.foo`
works only if every downstream flake also pulls in `foo`.  This ends
up meaning that each level of a dependency tree has to re-mention all
of its transitive dependencies, either directly or in the form of a
bunch of "follow" pins, or else you get an explosion of flake
versions.

Second, collisions: Overlays that write top-level attributes tend to
fight over the same flat namespace.

### Where does a registered file find the dependencies of its flake?

A registered file reads them as `closure-lib.caisson.dependencies.<name>`.
The dependencies are the pinned trees a flake passes to `mkLib`
under their input names, with no `self`, and
`inherit (caisson.lib.caisson.pins.flake inputs) dependencies root;` in
the `mkLib` call passes them. `closure-lib` is a member of the
closure attrset that `mkLibOverlay` and `mkModule` apply to each
registered file as its first argument list, and
`closure-lib.caisson.dependencies` is read from
`closure-lib.caisson-core.libManifest.dependencies`. A file always
reads the dependencies of the flake that registered it. An overlay or
module consumed from another flake sees the dependencies of the flake
it came from, not those of the flake consuming it.
[Closed-over Dependencies](concepts/closed-over-dependencies.md) is the
full convention.

### What happens when two overlays define the same thing?

Composition is done via an ordered pass across the specified overlays,
traversing dependencies in a depth-first, postfix manner. For attrSets
and lists, following the conventions results in a merge. For atomic
attributes, contentions mean that the later overlay's definition
wins. I say "convention" because overlays are actually capable of
addressing their predecessor directly, so they can technically
implement whatever merging logic they deem appropriate.


### Can I adopt this incrementally in an existing flake-parts flake?

Yes. `lib.caisson.flake-parts.mkTopConfiguration` wraps the
`mkFlake` of flake-parts, and plain
flake-parts modules work unchanged. We recommend starting by
composing a library with `lib.caisson.mkLib`. You can hand your
existing top-level module to `mkTopConfiguration` and let the conventions
spread file by file from there.

### What does `lib.caisson.flake-parts.mkModule` do to my module?

A few things:

- applies the closure argument list, so the module can use
  `closure-lib`, including `closure-lib.caisson.dependencies`
- records the file's path as `_file`, for better error messages
- gives path-registered modules a deduplication `key`.

### Do I pin nixpkgs, home-manager, and the rest myself?

Yes, you manage the ecosystem pins in your own flake, which is the
point: a caisson integration is glue over the ecosystem's evaluator,
composing with whatever ecosystem source version you give it, so
caisson imposes no transitive pins and two consumers of the same
caisson revision can run different nixpkgs revisions. Version skew
within your ecosystems lives in your locks, where you can see and
manage it. A flake whose configurations all use the same version of
an ecosystem can set a flake-level default at `mkLib`, a function of `dependencies`
(`defaultEcosystemSrc = dependencies: { nixos = dependencies.nixpkgs; };`). It
is also possible to pass `ecosystemSrc`, also a function of
`dependencies`, explicitly on each caisson call. The explicit argument
wins, and a source named exactly like the key is the final fallback
(handy for leaf nodes).


### What does this cost at evaluation time?

Measurements show: relatively little. The eval-weight harness runs in
CI and holds caisson's overhead (a minimal caisson consumer minus a
raw flake-parts flake) to ceilings on deterministic counters:
thunks, values, allocations, and full nixpkgs, nixpkgs-lib, and
module-system evaluation counts. The overhead is orders of magnitude
below a single nixpkgs evaluation.  [Evaluation
weight](eval-weight.md) documents the harness and the current numbers.

### How mature is this?

Pre-release. At the time of writing, it is used heavily by the author
and by no one else.
