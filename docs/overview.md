# Overview

This is the documentation for the framework's design and API.

New here? [Getting started](getting-started.md) walks through a first
flake step by step; [Choosing a flake framework](positioning.md)
places caisson relative to plain flake-parts, flakelight, and
snowfall-lib; the [FAQ](faq.md) answers the questions the concept
pages tend to raise.

**Reference** documents the exported surface: the
[Library](reference/lib.md) functions and the
[Options](reference/options.md).

**Conventions**: [Repository layout](layout.md) describes the
directory conventions the documentation and examples assume.

**Concepts** explain the machinery and the reasoning behind it, in
reading order:

- [Closed inputs](concepts/closed-inputs.md): how modules and library
  overlays close over the defining flake's inputs, and the explicit
  closure convention every registered thing follows.
- [Module classes](concepts/module-classes.md): class-keyed module
  registration and export.
- [Library overlays](concepts/library-overlays.md): namespaced,
  dependency-declaring `lib` composition, and the patterns for writing
  overlays.
- [Ecosystem sources](concepts/ecosystem-sources.md): why
  integrations pin nothing, and the three places a source can come
  from.

**Deep dives**:
[How `lib` is composed](deep-dives/how-lib-is-composed.md) traces a
`mkLib` call from arguments to finished attrset, including the rules
that decide conflicts and composing through caisson-core directly.
[How inputs are closed over](deep-dives/how-inputs-are-closed-over.md)
traces the closure attrset from `mkLib` to a registered file,
including what each kind of registration receives and which values
cross flake boundaries.

**Guides**: [Testing](./testing.md) covers unit and integration testing
(including `callConsumerFlake`), and
[Evaluation weight](eval-weight.md) covers measuring and gating
evaluation cost.

For a complete working flake with commentary, see
`examples/literate-flake/` in the repository. The repository README
covers the quick start.

---

Despite the org name, caisson is an independent project and is not
affiliated with, endorsed by, or sponsored by the NixOS Foundation.
Nix and NixOS are trademarks of the NixOS Foundation.
