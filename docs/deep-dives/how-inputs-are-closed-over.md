# How inputs are closed over

Every file registered through caisson takes a closure attrset as its
first argument list. This page traces the mechanism behind that
convention: where the closure comes from, when it is applied, what it
contains for each kind of registration, and what it means when a
registered file is evaluated inside another flake's composition.

## The convention

A registered file is a function of two argument lists: the closure
attrset first, then whatever the file ordinarily takes.

```nix
{ closure-inputs, ... }:          # the closure arg list
{ config, lib, pkgs, ... }:      # the ordinary module arg list
{
  services.foo.package = closure-inputs.foo-flake.packages.x86_64-linux.default;
}
```

A file that needs nothing from the closure still takes the arg list
(`{ ... }:`), so every registered file has the same shape and a
reader always knows what the first line is.

## Where the closure comes from

The flake defines the closure by calling `mkLib`:

```nix
lib = caisson.lib.caisson-core.mkLib {
  inherit inputs;
  libOverlays = mkLibOverlay: { ... };
  modules = lib: { ... };
};
```

`mkLib` builds registration helpers closed over the `inputs` it was
given, and hands them to the registration arguments: `libOverlays`
receives the input-closed `mkLibOverlay`, and `modules` receives the
composed `lib`, whose helpers (`lib.caisson.flake-parts.mkModule`,
`lib.caisson.nixos.mkModule`, and the `caisson-core.mkModule` they
are bound from) are closed the same way. There is no
ambient lookup anywhere in this chain: the only `inputs` a
registration can see is the attrset its own flake passed to `mkLib`.

## When the closure is applied

At registration time, not at evaluation time. `mkLibOverlay` and
`mkModule` call the registered function with the closure attrset
immediately and keep the result, so what sits in the registry, and
what the flake exports, is an ordinary overlay or module with the
closure values already baked in.

This timing is what makes export work. A consumer who imports
`my-flake.modules.nixos.my-service` receives a plain NixOS module;
the closure was applied when my-flake registered the file, so the
module references my-flake's inputs without the consumer declaring,
`follows`-pinning, or even knowing about them.

## What the closure contains

The contents differ by registration kind, because the two kinds are
evaluated at different times.

A library overlay's closure contains registration helpers, inputs and
the library of the defining composition:

- `closure-inputs`: the `inputs` of the defining flake.
- `closure-lib`: the composed library of the defining flake, bound
  lazily. Inside the `overlay` function, `final` and `prev` are the
  composition being built, which may belong to a consumer;
  `closure-lib` is the composition of the definer, so an integration
  reaches the registry of the composition that registered it (its
  `core` module, for one) wherever it is composed. It is read inside
  the overlay function or a function the overlay defines, never while
  the overlay is being registered.
- `mkLibOverlay`: the same helper, for building nested overlays.
- `mkModule`: the module normalizer bound to the defining
  composition, so modules contributed by the overlay close over the
  inputs and library of the definer.
- `contributeModules`: merges class-keyed module contributions into
  the registry from inside an overlay. It is threaded through the
  closure rather than read from `final` because the output attribute
  names of an overlay must not depend on `final` (see
  [How `lib` is composed](how-lib-is-composed.md)).

A module's closure contains the definer's finished world:

- `closure-inputs`: the `inputs` of the defining flake.
- `closure-lib`: the composed library of the defining flake. This is
  not the `lib` module argument; see the next section. Its registry,
  `closure-lib.caisson-core.modules.<class>`, is how a module imports
  a sibling by name.
- `mkModule`: a normalizer bound to the same class, so nested module
  composition stays in that class.

Plain values bypass the mechanism: an already-built overlay (another
flake's export) and a plain module are registered directly, because
their closures were applied by whoever built them.

## Two worlds in one file

Inside a registered module, two sets of similar-looking values are in
scope, and they answer different questions:

| Value | Whose world |
|---|---|
| `closure-inputs` | The flake that registered the file |
| `closure-lib` | The flake that registered the file |
| `inputs` module arg | The flake being evaluated |
| `lib` module arg | The flake being evaluated |

While a flake consumes its own registrations the distinction is
invisible, because both worlds are the same flake. It starts to
matter the moment a module is exported: a consumer evaluates the
module inside their own composition, so the ordinary `lib` argument
is the consumer's composed library, while `closure-lib` remains the
definer's. A module that formats a string with a helper from its own
flake's namespace wants `closure-lib`; a module that inspects the
configuration it is being evaluated into wants the ordinary
arguments.

The same split governs version skew. An exported module built against
`closure-inputs.nixpkgs` uses the definer's nixpkgs pin even when the
consumer runs a different one. That skew is a designed property, not
an accident: each flake's files run against the pins that flake
tested with, the pins are visible in each flake's lock, and
nothing forces the fleet to upgrade in lockstep. Where a consumer
does want to override a definer's pin, flake-level `follows` on the
definer's input still works, because `closure-inputs` is the
definer's `inputs` attrset and `follows` rewrites what that attrset
contains.

## importApply

Closure application composes with module `imports` through
`lib.caisson-core.importApply`, which applies static arguments to a
module without losing its file identity: a path is imported and
wrapped with its `_file`, wrapper modules produced by registration
are walked rather than replaced, and the arguments are applied to
the innermost function.

```nix
imports = [
  (closure-lib.caisson-core.importApply ./listener.nix { port = 8080; })
];
```

Here `listener.nix` begins `{ port }:` and receives the arguments as
its first arg list. Wrapping the module in a plain lambda instead
would work, but the module system would see an anonymous function:
error messages would no longer point at the file.

## Seeing it in the example

`examples/literate-flake/` wires all of this in a working flake: its
overlay reads `closure-inputs`, and its modules take the two argument
lists. Step 5 of [Getting started](../getting-started.md) shows the
consuming side, a second flake that imports the exports without
declaring the definer's dependencies.
