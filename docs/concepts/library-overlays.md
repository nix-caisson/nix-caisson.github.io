# Library Overlays

## The Problem People Actually Had

Nix overlays have a reputation problem. Package overlays in nixpkgs caused real pain (attribute collisions, silent shadowing, unpredictable evaluation order), and the community learned to be cautious. That caution has grown into a broader skepticism that prevented the community from really embracing library overlays, out of fear that a worse version of the same problems might occur.

The skepticism is understandable but misdirected. The problems were never inherent to overlays as a mechanism. They came from how overlays were used: global modifications to shared namespaces, no convention for scoping additions, no way to declare dependencies between overlays, and no isolation between unrelated consumers. Fix those problems and overlays become a safe, composable extension mechanism.

caisson fixes those problems for library overlays. The result is something the Nix ecosystem has been missing: composed, layered `lib` extensions that multiple flakes can contribute to without stepping on each other.

## What Makes Overlays Safe

Four properties, applied together, address the collision and ordering risks that gave overlays a bad name:

### Namespacing

Every overlay adds its functions under a dedicated attribute path rather than mixing into the top-level `lib`. A project called `myProject` puts its functions at `lib.myProject.*`:

```nix
overlay = final: prev: {
  myProject = (prev.myProject or {}) // {
    helper = x: x + 1;
  };
};
```

This means two independent projects do not collide unless the project names do: `lib.projectA.helper` and `lib.projectB.helper` coexist without interference, as they would in any language with a module system. caisson's `configInfo.configName` convention helps here: if every project uses its canonical flake name as the namespace, collisions are unlikely in practice. Choose a distinctive name for your flake; generic names like `utils` or `helpers` invite collisions, while project-specific names like `caisson` or `acme-infra` make them vanishingly rare. This is a convention, not an enforcement mechanism: if two upstream flakes happen to choose the same `configName`, their `lib` contributions will merge into the same namespace.

### prev-Based Merging

The `(prev.myProject or {}) // { ... }` pattern ensures that if multiple overlays contribute to the same namespace (e.g., a base overlay and an extension overlay within the same project), their contributions are merged rather than one silently replacing the other. This is the standard Nix overlay contract, and it matters: it means overlays compose additively.

### Input Closure

caisson's `mkLibOverlay` automatically closes over the flake's `inputs` when registering an overlay. This binds each overlay to the specific set of inputs it was written against, rather than relying on the leaf flake to do the right thing. The result is that overlays from different upstream flakes don't interfere with each other's inputs, even when composed into the same final `lib`.

See [Closed Inputs](./closed-inputs.md) for the full mechanism.

### Dependency Tracking

Library overlays sometimes need to call functions defined by other library overlays. Without explicit dependency management, this requires manually ensuring that overlays are applied in the right order, a fragile arrangement that breaks when overlays are reorganized or new ones are added.

caisson solves this. A registered overlay is an `{ imports ? [ ], overlay }` attrset, and `imports` is where its dependencies go. Entries are built overlays; the closure's `mkLibOverlay` member exists exactly so a dependency can be built in place:

```nix
{ mkLibOverlay, ... }:
{
  overlay = final: prev: {
    myProject = (prev.myProject or {}) // {
      fullName = person: "${prev.myProject.greet person} (${person})";
    };
  };
  imports = [ (mkLibOverlay ./greet-overlay.nix) ];
}
```

When `mkExtendedLib` encounters this structure, it recursively applies the `imports` before applying the `overlay` itself. This guarantees that `prev.myProject.greet` exists by the time `fullName` is evaluated, regardless of the order overlays were listed in `libOverlays`.

The resolution is recursive: imported overlays can themselves declare imports, and the framework handles the full dependency graph.

## Package Overlays and Library Overlays

The safety techniques described here (namespacing, input closure, dependency tracking) apply equally to package overlays and library overlays. The underlying mechanism is the same: both are functions of `final: prev:` that extend an attribute set.

caisson provides the tooling for safe library overlays. The same principles apply to package overlays, but package overlay tooling is the domain of `caisson-nixpkgs` (not yet published), which builds on caisson's foundation.

## Tradeoffs

The safety mechanisms described here aren't free. Import chains are
flattened depth-first with duplicates preserved (an overlay's imports
are applied before it, every time it appears) and folded through the
caisson-core, so evaluation cost grows with the number of
overlays and the depth of the dependency graph. One contract worth
knowing: the base library is contributed as an opaque attribute set,
so overriding one of its attributes changes what readers of the
composed library see, without re-tying the base's own internal
references.

For most flakes the overhead is negligible, but it's worth being aware of, especially if you're composing a large number of upstream library overlays. The eval-weight harness (see the guides) is the tool for holding it to a measured ceiling.

## Practical Patterns

### A Simple Library Overlay

The most common case: adding namespaced functions to `lib`.

```nix
# lib-overlays/default/default.nix
{ closure-inputs, ... }:
{
  imports = [ ];
  overlay = final: prev: {
    myProject = (prev.myProject or {}) // {
      greet = name: "Hello, ${name}!";
      double = x: x * 2;
      upstreamVersion = closure-inputs.some-flake.lib.version;
    };
  };
}
```

The closure arg list always comes first: `closure-inputs` here is the
*defining* flake's inputs, so `some-flake` resolves against the inputs
this overlay was written with, no matter which downstream flake
eventually composes it. An overlay that needs nothing from the closure
still takes the arg list, as `{ ... }:`.

Register it in your flake's `mkLib` call:

```nix
libOverlays = mkLibOverlay: {
  default = mkLibOverlay ./lib-overlays/default;
};
```

After composition, `lib.myProject.greet "world"` returns `"Hello, world!"`.

### An Overlay With Dependencies

When one overlay needs functions from another, declare the dependency:

```nix
# lib-overlays/extended/default.nix
{ mkLibOverlay, ... }:
{
  overlay = final: prev: {
    myProject = (prev.myProject or {}) // {
      greetLoud = name: final.toUpper (prev.myProject.greet name);
    };
  };
  imports = [ (mkLibOverlay ../default) ];
}
```

The `imports` list ensures `default` is applied first, so `prev.myProject.greet` is available. Register the extended overlay normally:

```nix
libOverlays = mkLibOverlay: {
  default = mkLibOverlay ./lib-overlays/default;
  extended = mkLibOverlay ./lib-overlays/extended;
};
```

### Common Mistakes to Avoid

- **Top-level additions.** Don't add attributes directly to `lib` (e.g., `{ helper = ...; }`). Always namespace under a project-specific attribute.
- **Forgetting `prev` merge.** Writing `myProject = { helper = ...; }` instead of `myProject = (prev.myProject or {}) // { helper = ...; }` will silently discard any functions added to `myProject` by earlier overlays.
- **Implicit ordering assumptions.** If overlay B uses a function from overlay A, declare the dependency with `{ overlay = ...; imports = [...]; }` rather than hoping the registration order is correct.

## Further Reading

- [How `lib` is composed](../deep-dives/how-lib-is-composed.md): the whole composition pass
- [Closed Inputs](./closed-inputs.md): how inputs are closed over in overlays and modules
- `examples/literate-flake/`: a working example with a custom library overlay
