# How `lib` is composed

A caisson flake's `lib` is canonically built by a call to
`caisson-core.mkLib`. This page traces what happens between that
call and the finished attrset: what goes in, the order things apply,
the rules that decide conflicts, and how to drive the same machinery
without `mkLib` when you want to.

## What goes in

`mkLib` is given a base library and a set of declarations:

- `baseLib`: the library everything else extends, passed as a plain
  value. Nothing is looked up by input name. When you call the
  `caisson-core.mkLib` found inside a composed library, `baseLib`
  defaults to that composition's own base, which is why a typical
  flake passes only the arguments below.
- `libOverlays`: the flake's own overlay registrations, built with
  the input-closed `mkLibOverlay` helper or registered directly when
  already built (another flake's export, for example).
- `modules`: the flake's own class-keyed module registrations.
- `projects`: whole upstream contributions, each carrying exported
  overlays and modules that register under `<project>/<name>`.
- `ecosystems`: declared default ecosystem sources (see
  [Ecosystem sources](../concepts/ecosystem-sources.md)).

Registration and application are separate steps: `libOverlayImports`
selects which of the registered overlays apply to this flake's own
`lib` (default: all of them), and registration also feeds export, so
a flake can register overlays for downstream consumers that it does
not apply to itself.

## The sequence

The selected overlays are applied over the base in one pass, wrapped
by overlays caisson adds itself:

```
baseLib
  -> caisson-core namespace injection
  -> selected overlays (flattened, imports first)
  -> consumed projects' modules
  -> the flake's own module registrations
  -> the manifest
```

The first added overlay injects the machinery and the empty module
registry under `caisson-core`. The last one records the manifest,
the composition's self-description, at
`lib.caisson-core.manifest`. Module registrations apply after every
selected overlay so that a local name always beats a same-named
contribution from an overlay or a consumed project.

Before application, each selected overlay is flattened: a built
overlay is an `{ imports, overlay }` value, and the flattening walks
depth-first with imports before the overlay itself. This guarantees
that anything an overlay depends on has already applied when its
`overlay` function runs, regardless of registration order. Within
`mkLib`, imports guarantee order, not uniqueness: an overlay that two
registrations both import is applied once per appearance, which is
harmless for overlays that follow the merge conventions.

## The fold

Application is the standard Nix overlay contract, folded over the
sequence above. Each `overlay = final: prev: { ... }` receives
`prev`, everything accumulated so far, and `final`, the finished
fixpoint. For an attribute defined by two overlays, the later
definition wins, and `prev` gives it the earlier one to build on,
which is what the `my-flake = (prev.my-flake or { }) // { ... }`
merge convention relies on.

Two consequences of the fixpoint are worth knowing:

- An overlay's output attribute *names* must not depend on `final`; a
  fixpoint whose shape depends on itself diverges.
- The base library is contributed as an opaque value. Overriding one
  of its attributes changes what readers of the composed library see,
  and does not change what the base's own internals call; a function
  patched for everything downstream of the base has to be patched in
  the base source you pass in.

## Composing without mkLib

`mkLib` is a convenience over `caisson-core.compose`, which works on
*entries*, overlay-shaped pieces with identity:

```nix
{
  key = "example.base";   # stable identity: a string, or null
  imports = [ ];          # entries this entry depends on
  overlay = final: prev: { greet = name: "hello, ${name}"; };
}
```

Keys change the rules. A keyed entry applies once no matter how many
entries import it; the first occurrence of a key fixes its position
and the last occurrence supplies its value, so mentioning a key again
replaces that entry wholesale; replacement is the only override
mechanism. An entry with `key = null`
cannot be imported, applies after the whole keyed world in list
order, and can never be replaced by another entry, because
replacement addresses keys and it has none; keyless entries are a
consumer's private patch layer. Import cycles terminate (a key
already on the walk's own path is skipped) and grant the cycle's
members no ordering relative to each other.

Identity is what makes patching a dependency reliable. A polyfill
imports the entry it patches, which guarantees the target is present
and already applied when the polyfill reads `prev`:

```nix
polyfill = {
  key = "example.backport";
  imports = [ base ];
  overlay = final: prev: {
    concatLines = prev.concatLines or (lines: prev.concatStringsSep "\n" lines + "\n");
  };
};
```

The `prev.concatLines or ...` shape adds the function only where the
base does not already provide it, so the same entry composes
correctly over old and new bases.

The exact contract (walk order, replacement slots, metadata) is
specified in
[caisson-core](https://github.com/nix-caisson/caisson-core), where
the code lives.

caisson exports its own contributions in entry form through
`lib.composition.entriesFor`:

```nix
caisson.lib.composition.entriesFor {
  # a directory importable as nixpkgs' lib, e.g. "${nixpkgs}/lib"
  # or "${nixpkgs-lib}/lib" for the nixpkgs.lib mirror
  ecosystemSrc = "${inputs.nixpkgs-lib}/lib";
}
# => { base, caisson-lib,
#      flake-parts, tooling,
#      nixpkgs, nixos, home-manager,
#      colmena, terranix, system-manager }
```

`base` contributes the nixpkgs library the composition builds on;
`caisson-lib` imports it and contributes the `caisson-core`
machinery, the same injection `mkLib` performs; the rest are the
integrations and tooling, each importing `caisson-lib`.

## Where the composed `lib` goes

`mkFlake` passes the composed library to flake-parts as
`specialArgs.lib`, so modules receive it as their ordinary `lib`
argument. `flake.lib` publishes a selection of it when
`caisson.lib.export.enabled` is set; the default selection is the
flake's own namespace only, and that is the convention: exporting
the full composed library would make all of nixpkgs-lib, at your
pin, part of your public contract. Consumers build their own
composed library against their own inputs instead.

## Inspecting the result

```bash
nix repl .
# :p lib.my-flake                     -- your namespaced additions
# :p lib.my-flake.helper 41           -- call a function

nix eval .#lib --apply builtins.attrNames
```
