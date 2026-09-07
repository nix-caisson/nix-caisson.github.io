# FAQ

### What goes wrong without caisson that this fixes?

Caisson addresses two major failure patterns seen in poly-flake
setups:

First, input explosion: a flake-parts module that uses `inputs.foo`
works only if every downstream flake also pulls in `foo`.  This ends
up meaning that each level of a dependency tree has to re-mention all
of its transitive dependencies, either directly or in the form of a
bunch of "follow" pins, or else you get an explosion of flake
versions.

Second, collisions: Overlays that write top-level attributes tend to
fight over one flat namespace.

### What is `closure-inputs`, and who sets it?

`closure-inputs` is the `inputs` attrset your flake passes to
`mkLib`, threaded in by the caisson framework: `mkLibOverlay` and
`mkModule` apply it to each registered file as the file's first
argument list. A file always receives the inputs of the flake that
registered it: an overlay or module consumed from another flake sees
the inputs of the flake it came from, not the inputs of the flake
consuming it.
[Closed inputs](concepts/closed-inputs.md) is the full convention.

### What happens when two overlays define the same thing?

Composition is done via an ordered pass across the specified overlays,
traversing dependencies in a depth-first, postfix manner. For attrSets
and lists, following the conventions results in a merge. For atomic
attributes, contentions mean that the later overlay's definition
wins. I say "convention" because overlays are actually capable of
addressing their predecessor directly, so they can technically
implement whatever merging logic they deem appropriate.


### Can I adopt this incrementally in an existing flake-parts flake?

Yes. `mkFlake` wraps flake-parts' own `mkFlake`, and plain
flake-parts modules work unchanged. It is recommended to start by
composing a library with `caisson-core.mkLib`. You can hand your
existing top-level module to `mkFlake` and let the conventions
spread file by file from there.

### What does `mkFlakeModule` do to my module?

A few things:

- applies the closure argument list, so the module can use
  `closure-inputs`
- records the file's path as `_file`, for better error messages
- gives path-registered modules a deduplication `key`.

### Do I pin nixpkgs, home-manager, and the rest myself?

Yes, you manage the ecosystem pins in your own flake, which is the
point: a caisson integration is glue over the ecosystem's evaluator,
composing with whatever ecosystem source version you give it, so
caisson imposes no transitive pins and two consumers of the same
caisson revision can run different nixpkgs revisions. Version skew within your
ecosystems lives in your own locks, where you can see and manage it. A
flake that uses one version of an ecosystem everywhere can set a
flake-level default at `mkLib` (`ecosystems.nixpkgs = inputs.nixpkgs`). But it's
also possible to explicitly pass it on each caisson call. The explicit
argument wins, and an input named exactly like the ecosystem is the
final fallback (handy for leaf nodes).


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
