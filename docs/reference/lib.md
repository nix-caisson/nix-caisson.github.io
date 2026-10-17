# Library Reference

A composed library carries the framework namespaces `lib.caisson-core`
and `lib.caisson`. `lib.caisson-core` holds the machinery, injected by
`mkLib` itself (its code lives in
[caisson-core](https://github.com/nix-caisson/caisson-core), which
caisson pins internally). `lib.caisson`
holds the integrations and the pkgs-dependent tooling, contributed by
the overlays this flake exports. The `lib` output of the caisson flake
is its composed library, so both namespaces are in it
(`caisson.lib.caisson-core`, `caisson.lib.caisson`).

Type notation used below:

- `lib`: a composed nixpkgs-style library attrset
- `module`: a module for some module class's module system
- `overlayFn`: `final: prev: attrs`, the standard overlay function
- `libOverlay`: `{ imports : listOf libOverlay; overlay : overlayFn }`,
  the built overlay produced by `mkLibOverlay` (both keys always present)
- `path` arguments are imported before the rules below apply

## The caisson-core namespace

- **Source:** caisson-core's `lib/default.nix` (the `compose`
  primitive, and the composition of the entries below) and
  `lib-overlays/<name>/default.nix` (`compose`, `resolve`,
  `lifecycle`, `readers`, `lists`, `attrsets`, `strings`,
  `functions`). caisson-core is a composition of those entries.
  `mkLib` composes them into the library it builds under the keys
  `caisson-core/<name>`, and an entry registered under the same key
  replaces the entry of that key.

### `mkLib`

```
mkLib :
  { sources           : attrs                              # the tree's pinned sources, as a pin reader returns them
  , root              ? null : root                        # the tree's identity; null for a composition that is not a top
  , name              ? null : str                         # the project's name, also the namespace it contributes
  , modules           ? (lib: { })
                      : lib -> attrsOf (attrsOf module)    # class -> name -> module
  , configs           ? (lib: { })
                      : lib -> attrsOf (attrsOf module)    # class -> name -> configuration
  , libOverlays       ? (lib: { })
                      : lib -> attrsOf libOverlay          # given the core lib
  , libOverlayImports ? (lib: <every project and local registration>)
                      : lib -> listOf libOverlay           # given the core lib
  , extraLibOverlayImports ? (lib: [ ])
                      : lib -> listOf libOverlay           # given the core lib
  , pkgOverlays       ? (lib: { })
                      : lib -> attrsOf pkgOverlay          # given the bootstrap lib
  , pkgSets           ? (lib: { })
                      : lib -> attrsOf configuration       # package configs by name, given the registered lib
  , defaultEcosystemSrc ? { } : attrs                      # the tree's default source per ecosystem, by exact name;
                                                           # nixpkgs supplies the nixpkgs-lib part unless nixpkgs-lib is declared separately
  , systems           ? null : listOf str                  # the platforms the tree builds on
  , projects          ? { } : attrs                        # consumed upstream contributions, by project name
  } -> lib
```

Builds a composed library over the seed, the empty attribute set: the
`caisson-core` entry (registered under that name, so a registration
under the same name replaces it), the selected registered overlays,
then the synthetic overlays: the local module registrations (so local
names win over overlay-borne contributions) and the manifest. In a
flake that uses caisson, the selected overlays include the
`nixpkgs-lib` entry, which is the `lib` of nixpkgs loaded from the
source that `defaultEcosystemSrc` declares. The caisson integration
overlays import it. Every source arrives as an argument or a
declaration; the exact-name fallback over `sources` applies to
ecosystem resolution only (see
[Ecosystem sources](../concepts/ecosystem-sources.md)).

The library is built in stages, each a new fixpoint over the
seed with a manifest in `lib.caisson-core.libManifest`. Each stage
exists because some argument is a function of it:

- The **core lib** holds the `caisson-core` entries and nothing else,
  with the lib overlay registry grafted onto its manifest.
  `libOverlayImports` receives it.
- The **bootstrap lib** adds the selection, and with it the
  `nixpkgs-lib` entry and every integration namespace. `modules` and
  `configs` receive it; its manifest has no `modules`,
  `moduleProjects`, `configs`, `pkgOverlays` or `pkgSets`.
- The **registered lib** is the same entries with the module
  registrations, the configurations and the package overlay registry
  grafted on. `pkgSets` receives it, since a package config selects
  from those registries; its manifest has no `pkgSets`. It is built
  only when a package config is read.
- The **full lib** adds `pkgSets`. `mkLib` returns it.

The core, bootstrap and registered manifests have `childless = true`.
A registration made at an earlier stage still closes over the full
lib. The constructors the earlier libs hold (`mkModule`,
the integrations' `mkModule`, `mkLibOverlay`, `mkPkgOverlay`) give the
entry the full lib as `closure-lib`. The manifest of that lib holds
the registry the entry joins, which `closure-lib.caisson.modules.<class>`
reads, so a module imports a sibling by name. A registration under a
`caisson-core/<name>` key replaces that entry from the bootstrap stage
on; the core lib keeps the original.

`sources` and `root` come from a pin reader (see `pins` below); at a
flake top, `inherit (caisson-core.lib.caisson-core.pins.flake inputs)
sources root;`. The registered overlays and modules close over
`sources` as `closure-inputs`, so the closure holds the pinned trees
under their input names and no `self`. The signature is the pattern
of `mkLib`, with no `...`: a missing or unexpected argument, a
leftover `inputs` included, is Nix's error at the call site,
naming `mkLib` and pointing at the pattern.

- `modules` receives the bootstrap lib and returns the class-keyed
  registration, built with the
  integrations' `mkModule` helpers (`lib.caisson.nixos.mkModule`,
  `lib.caisson.flake-parts.mkModule`, and so on).
  `lib.caisson-core.mkModule "<class>"` is for a class no integration
  covers. `lib: lib.caisson-core.mkModules ./modules` reads the
  conventional layout.
- `configs` receives the bootstrap lib the same way and returns the
  configurations of the tree, keyed by module class then name, the
  layout `configs/<class>/<name>` on disk (colmena's class is
  `caisson-colmena`); `lib: lib.caisson-core.mkModules ./configs` reads that
  layout. They come back in the manifest, which
  `lib.caisson.configs.<class>.<name>` reads, so a top and a
  configuration that evaluates another beneath itself reach them by
  name rather than by a path out of their directory.
- `libOverlays` receives the core lib and returns the registered
  overlays. An entry is made with `lib.caisson-core.mkLibOverlay`,
  which closes it over the sources of the composition;
  `lib: lib.caisson-core.mkLibOverlays ./lib-overlays` reads the
  layout.
- `pkgOverlays` receives the bootstrap lib and returns the registered
  package overlays. An entry is made with
  `lib.caisson-core.mkPkgOverlay`;
  `lib: lib.caisson-core.mkPkgOverlays ./pkg-overlays` reads the
  layout (see `pkgOverlays` below).
  These four arguments take exactly the function shape shown; passing
  anything else is an error.
- `pkgSets` receives the registered lib and returns the package
  configs of the tree by name, each a configuration an integration's
  constructor built:
  `pkgSets = lib: lib.caisson.nixpkgs.mkConfigurations { };` declares
  a package config for every configuration in `configs/nixpkgsConfig`
  (see `caisson.nixpkgs` below). `mkLib` finalizes each with the name
  it is declared under and the registered manifest as its parent, and
  records them in the manifest's `pkgSets`; the flake reads its
  package sets from there.
- `libOverlayImports` selects which registered overlays apply to the
  `lib` of this flake. It receives the core lib and names entries from
  the `libOverlays` registry described below.
  `libOverlayImports = lib: [ lib.caisson.libOverlays.my-overlay ];`
  selects the entry registered as `my-overlay`. The default selects
  the project and local registrations, and a selection given here
  replaces it.
- `extraLibOverlayImports` has the same form and adds to the
  selection, whichever it is: a flake that names a further entry with
  it keeps the default.
  Registration also feeds export, so what is registered and what is
  selected can differ.
- `defaultEcosystemSrc` declares the tree's default source per
  ecosystem (`{ nixpkgs = inputs.nixpkgs; ... }`), keyed by the exact
  names the integrations resolve. mkLib captures them into the
  manifest and reads the `nixpkgs-lib` source from them (the
  `nixpkgs-lib` name, else `nixpkgs`); the integrations interpret the
  rest.
- `projects` consumes whole upstream contributions
  (`{ my-dep = inputs.my-dep; }`). A project contributes the
  dictionaries `libOverlays`, `pkgOverlays` and class-keyed `modules`.
  For a flake built with caisson, mkLib reads these dictionaries from
  the manifest of the flake, at `lib.caisson-core.evalManifest` in the
  `lib` output, where they are under `outputs.exports`. mkLib ignores
  the other outputs of that flake. A value with no manifest is read as
  an attribute set that holds these dictionaries itself.
  A project's overlays and package overlays join
  their registries and its modules join the class registry under
  `<project>/<name>`, so the existing selections keep per-item
  choice: `libOverlayImports` decides which overlays apply, the
  registry selection at each use site decides which modules load, and
  a local registration beats a same-named project entry. Registering
  a single overlay by hand is the way to cherry-pick or rename it.

### `mkModules`, `mkLibOverlays`, `mkPkgOverlays`

```
mkModules     : path -> attrsOf (attrsOf module)   # <dir>/<class>/<name>/default.nix
mkLibOverlays : path -> attrsOf libOverlay         # <dir>/<name>/default.nix
mkPkgOverlays : path -> attrsOf pkgOverlay         # <dir>/<name>/default.nix
```

The directory readers. A reader belongs to the lib it is read from:
it takes a directory and returns the registrations, built with the
entry constructors of that lib. Each registry
function of `mkLib` receives a lib, so a tree with the conventional
layout takes the reader from it and names the directory:

```nix
modules = lib: lib.caisson-core.mkModules ./modules;
configs = lib: lib.caisson-core.mkModules ./configs;
libOverlays = lib: lib.caisson-core.mkLibOverlays ./lib-overlays;
pkgOverlays = lib: lib.caisson-core.mkPkgOverlays ./pkg-overlays;
```

The readers are the registered entry `caisson-core/readers`, so a
composition that registers another entry under that name reads its
directories with that entry.

`mkModules` reads the first directory level as the class, whatever
its name, and registers each entry directory through `mkModule` of
the lib, given the name of that directory as the class. caisson keeps
no list of classes: the integration that evaluates a class names it
in its declaration. `mkLibOverlays` applies `mkLibOverlay`, and
`mkPkgOverlays` applies `mkPkgOverlay`. An entry is
a directory holding a `default.nix`, a symlink to such a directory
included; anything else in a directory being read is an error, so a
stray file cannot silently vanish from a registry. A tree with another
layout writes the registration by hand.

### `pkgOverlays`, `mkPkgOverlay`, `pkgOverlaysFor`

```
mkPkgOverlay   : freeformOverlay -> pkgOverlay
pkgOverlay     : { key; imports : listOf pkgOverlay; overlay : final -> prev -> attrs; origin; project; }
pkgOverlaysFor : listOf pkgOverlay -> listOf (final -> prev -> attrs)
```

The package overlay registry, recorded as
`caisson-core.libManifest.pkgOverlays`. An entry has the lib overlay
entry's shape with a nixpkgs overlay under `overlay`: a file handed to
`mkPkgOverlay` takes the closure
`{ closure-inputs, closure-lib, mkPkgOverlay, ... }` and returns
`{ imports ? [ ], overlay }`. An entry imports a sibling from the
registry of the composition that registered it,
`closure-lib.caisson-core.libManifest.pkgOverlays.<name>`:

```nix
# pkg-overlays/default/default.nix
{ closure-lib, ... }:
{
  imports = [ closure-lib.caisson-core.libManifest.pkgOverlays.extra ];
  overlay = final: prev: { my-project = prev.callPackage ./my-package.nix { }; };
}
```

Every registered entry carries its registry name as `key`, the file
it was read from as `origin` (null for an entry built from a
function), and `project`: null for a local registration, the
contributing project's name for an entry from `projects`, so the
local entries alone are a filter on that field. A project's entries
join under `<project>/<name>`; a key the project registered itself (a key
without a `/`) becomes `<project>/<key>` in its imports too, so an
import still meets its sibling, and a key naming another project's
entry (a key with a `/`) is kept, so two projects importing the same
entry import one entry.

`pkgOverlaysFor` turns a selection, a list of registry entries, into
the list of nixpkgs overlays a package set applies: each entry after
the entries it imports, each key once where it first occurs. One key
reached through two paths is one entry when both carry the same
origin; two entries with different origins under one key are refused.
By convention the entries named `default` (`default`,
`<project>/default`) are the default selection, as for modules; the
layer that builds package sets applies it. caisson-core applies
nothing itself.

### `mkLibOverlay`

```
mkLibOverlay : freeformOverlay -> libOverlay

freeformOverlay = path | (closure -> { imports ? listOf libOverlay
                                     ; overlay : overlayFn })
closure = { closure-inputs     : attrs    # the defining composition's pinned sources
          ; closure-lib        : lib      # the defining composition's lib, lazily bound
          ; mkLibOverlay       : freeformOverlay -> libOverlay
          ; mkModule           : string -> freeformModule -> module
          }
```

Applies the closure attrset to an overlay given as a function or a path
to it, and normalizes the result: the built `libOverlay` always carries
both keys, with `imports` defaulted to `[ ]`. Already-built overlays are
registered directly rather than wrapped.

The closure's `closure-lib` is the composed library of the composition
that registered the overlay, bound lazily: read it inside the
`overlay` function or a function it defines, never while the overlay
is being registered. An integration reaches the registry of its
composition through it (`closure-lib.caisson.modules.<class>`),
wherever it is later composed. The closure's `mkModule` is bound to
the defining composition, so modules an overlay makes close over the
definer's inputs and library. A lib overlay does not add to the
registry; see [Module classes](../concepts/module-classes.md) for the
ways modules enter it.

### `mkModule`

```
mkModule : string -> freeformModule -> module

freeformModule = path | (closure -> module)
closure = { closure-inputs        : attrs    # the defining flake's pinned sources
          ; closure-lib           : lib      # the defining flake's composed lib
          ; mkModule              : freeformModule -> module   # bound to the class
          }
```

Factory for class-specific module normalizers. Given a class name, returns a normalizer that applies the closure attrset to a module given as a function or a path to it; the module takes the closure as its first arg list (`{ ... }:` when unused). Plain modules are imported/registered directly rather than wrapped. Path modules gain `_file` and a path-based dedup `key`.

The `mkModule` closure member is bound to the same class, so nested module composition stays in that class. A module imports a sibling by name through `closure-lib.caisson.modules.<class>.<name>`, the registry of the composition that registered it.

### `modules`

```
modules : attrsOf (attrsOf module)    # class -> name -> module
```

The class-keyed module registry of this composition: the registrations
of the flake merged with every consumed project's entries
(`<project>/<name>`), locals winning on name conflicts. It is read
from the manifest of the library (`caisson-core.libManifest.modules`).
Integration adapters read their class from here
(`lib.caisson.modules.<class>`): every entry named `core` (`core`,
`<project>/core`) is the framework module of the class, forced into
every evaluation, and every entry named `default` is the default
default, what an evaluation gets when it passes no `moduleImports`.

### `manifest`

```
manifest : { _type : "caisson-manifest"; type : "lib";
             name ? str;
             entries : listOf { key : str; opaque : bool; };
             history : listOf event;
             sources : attrs; root : nullOr root;
             modules : attrsOf (attrsOf module);
             configs : attrsOf (attrsOf module);
             libOverlays : attrsOf libOverlay;
             pkgOverlays : attrsOf pkgOverlay;
             defaultEcosystemSrc : attrs; systems : nullOr (listOf str);
             projects : attrs;
             childless : bool; inputs : list; parent : nullOr manifest;
             ancestors : listOf manifest; nearest : attrsOf manifest;
             children : attrs }
```

The composition's self-description, injected as its final overlay.
`name` is the `name` argument, and is absent when the
composition declares none. `entries` lists the lib overlay selection
in composition order, caisson-core's forced entries first. An entry
is `opaque` when its key names no registry entry, as with an overlay
imported by value; a keyless entry gets a synthesized `keyless/<n>`
key. The lib `mkLib` returns is the full lib of a root declaration,
so `childless` is false, `parent` is null, and `ancestors`, `inputs`,
`nearest` and `children` are empty. The manifests of the core,
bootstrap and registered libs have `childless = true`, and the core
manifest lists only the `caisson-core` entries in `entries`.
`pkgSets` holds the package configs declared in the `pkgSets`
argument, each the manifest its configuration returned, with the
registered manifest as its `parent`.
`sources`, `root`, `defaultEcosystemSrc`, `systems`,
`projects` and `configs` are the `mkLib` arguments as given, except
that a directory reader's pin files are stated relative to the root
when the directory lies in the root's tree (`pin.dir` is kept
otherwise); `libOverlays`, `modules` and `pkgOverlays` are the
registered dictionaries, so consumed projects' entries appear under
`<project>/<name>` beside
the local registrations, with a local winning a name collision. Each
records where an entry came from: a lib overlay or package overlay
entry carries `project` (null for a local registration, the project's
name for a contributed entry, `caisson-core` for the lib overlay entries
caisson-core publishes into every composition), and
`moduleProjects.<class>.<name>` holds the same for modules, beside the
module dictionary. The export selectors default to the entries whose
origin is null. An
mkLib composition self-describes: the composed library of a consumer
carries the manifest of that consumer. Checks live on the export side
only (the flake-parts integration type-checks it and projects the
exports and the `flake.modules` output from it, so an
`exported` selection can re-export a project-borne entry the same
way as a hand-registered entry); a producer validates the manifest it
publishes in its CI.

`_type = "caisson-manifest"` marks the attrset as a manifest, which
is how `manifestOf` recognizes a manifest.

`history` lists the events recorded on the way to the lib, in stage
order, and the history of each stage begins with the history of the
stage before it. The core stage records one `layer` event per
`caisson-core` entry, then the lib overlay registrations. The
bootstrap stage adds one `layer` event per entry it composes that the
core stage did not, in composition order: the selection, and a
registration replacing a `caisson-core` entry, which so comes after
the entry it replaces. The full stage adds the `modules`, `configs`
and `pkgOverlays` registrations. A layer event carries `prev` and
`result` as the stage that recorded it composed them.

```
event : { manifest : listOf { type : str; name : str; };   # [ ] for the root lib
          type : "lib"; operation : "registry" | "layer";
          key : str; index : int;                            # index within its operation
          origin : { project : nullOr str; file : nullOr str; };
          prev ? attrs; result ? attrs; }                    # layer events only, lazy
```

`origin.project` is the project that registered the entry (the
composition's `name` for a local entry, `caisson-core` for its
entries) and `origin.file` the file the entry was built from, where
there is such a file; a lib overlay built from a file records it as its
`origin`. A layer event also keeps `prev` and `result` of its overlay
call `final: prev: result`: `prev` is the accumulation it received and
`result` the attrset it returned. They are the
values the lib was built from, and nothing reads them until
`definers` does.

### `definers`

```
definers : manifest -> listOf str
         -> listOf { key; index; origin; value; position : nullOr { file; line; column; }; }
```

The layers that define an attribute path, in composition order: the
last is the winner and the rest are shadowed. `value` is the path's
value after that layer. `position` is where the layer binds the name,
from `unsafeGetAttrPos`, kept only when it lies within the layer's
file, so a name the layer computes (with `mapAttrs`, say) reports
none. A layer that returns `prev.x // { ... }` carries the names
already under `x` without defining them: a name counts as carried
when its binding position is the same in what the layer returned and
what it received, or, with no position on either side, its value is
equal.

```nix
definers lib.caisson-core.libManifest [ "my-project" "greet" ]
# [ { key = "default"; value = <function>; position = { file = ".../lib-overlays/default/default.nix"; line = 6; ... }; ... } ]
```

### `manifestOf`

```
manifestOf : any -> nullOr manifest
```

Finds the manifest in whatever a file returns, so that a tool reading
a flakeless top needs only its `default.nix`. The value may be:

- a manifest, returned as it is;
- an attrset carrying a manifest at `caisson.manifest`;
- an evaluated configuration carrying a manifest at
  `config.caisson.manifest`;
- a composed library carrying the phase manifests (`libManifest`,
  `pkgsManifest`, `evalManifest` under `caisson-core`), or a package
  set carrying them in `pkgs.lib`. The last of them filled in is the
  manifest: `evalManifest` if set, else `pkgsManifest`, else
  `libManifest`.

A value carrying none of these returns null.

```nix
manifestOf (import ./.)   # the manifest of a flakeless top
manifestOf lib            # lib.caisson-core.libManifest
```

### `libOverlays`, `pkgOverlays`

```
lib.caisson.libOverlays : attrsOf libOverlay
lib.caisson.pkgOverlays : attrsOf pkgOverlay
```

These attributes are the lib overlay registry and the package overlay
registry of the composition that built the library, keyed by registry
name. Both are read from the manifest of the library
(`caisson-core.libManifest.libOverlays` and
`caisson-core.libManifest.pkgOverlays`), which is the only place
caisson-core keeps them. Each has the name of the `mkLib` argument
that fills it.

- `libOverlays` holds the entries `mkLib` registered, the entries
  consumed projects contributed under `<project>/<name>`, and the
  `caisson-core/<name>` entries. A `libOverlayImports` selection
  refers into it.
- `pkgOverlays` holds the package overlay entries: those `mkLib`
  registered and those consumed projects contributed. A package config
  selects from it:
  `caisson.nixpkgs.overlays = [ lib.caisson.pkgOverlays.default ];`.

Both are empty in a library that no `mkLib` call built.

### `ecosystemSrc`

```
lib.caisson-core.ecosystemSrc : name -> source | null
```

`ecosystemSrc` takes an ecosystem name and returns the source the
composition supplies for exactly that name. That is the
`defaultEcosystemSrc.<name>` the composition declares, or else the
source it pins under that name, or else null. The result is fixed by
the arguments of the `mkLib` call.

An overlay whose added names come from a source calls it on `prev`.
`prev.caisson-core.ecosystemSrc "nixpkgs-lib"` returns the nixpkgs
library source of the flake whose `mkLib` call composes the overlay,
whichever flake registered the overlay. The `nixpkgs-lib` integration
of caisson finds its source this way.

### `withManifests`

```
lib.caisson-core.withManifests :
  { pkgsManifest ? nullOr manifest; evalManifest ? nullOr manifest; } -> lib
```

Carried by every stage of a library `mkLib` builds. It rebuilds that
stage from its declaration with the given phase manifests filled in:
the same entries and the same `libManifest`, composed as a new
fixpoint, so code inside the library that reads
`final.caisson-core.pkgsManifest` sees the manifest, and `manifestOf`
returns it. Merging the attribute onto a built library would leave
those readers seeing `null`. The nixpkgs integration uses it to hand
out `pkgs.lib`, the bootstrap lib with `pkgsManifest` filled in, and a
module evaluation fills in `evalManifest` the same way. The rebuilt
library carries `withManifests` too, and a further call keeps what is
already filled in. Any other name, `libManifest` included, and any
value that is neither a manifest nor null is refused.

### `finalizeChild`

```
lib.caisson-core.finalizeChild :
  { name : str; parent : manifest; what ? str; } -> configuration -> manifest
```

A configuration learns its name and its parent from where it is
declared, so what an integration's `mkConfiguration` returns is a
function `{ name, parent }: manifest`. `finalizeChild` calls it with
the name it is declared under and the parent's childless manifest,
and requires a manifest back. It first reads the function's pattern
with `builtins.functionArgs` and requires exactly `name` and
`parent`, so anything else declared where a configuration belongs is
refused there, with a message saying what a configuration is. `what`
names the declaration in those messages. `mkLib` finalizes each
`pkgSets` entry this way, and the `caisson.<integration>.configurations`
options finalize each entry this way.

### `mkConfiguration`

```
lib.caisson-core.mkConfiguration :
  { type     : str                                 # the name of the integration
  , evaluate : { lib, manifest } ->
               { value; outputs ? { }; children ? { }; forChildren ? { }; }
  , record   ? { }                                 # plain data added to the manifest
  } -> configuration
```

Builds the configuration of a module evaluation: the function of
`{ name, parent }` that `finalizeChild` calls. It is what an
integration's `mkConfiguration` is written with. Nothing is evaluated
when it is called; the manifest the configuration returns reads
`value`, `outputs` and `children` from `evaluate` when they are read.

`evaluate` performs the evaluator's call on `lib`, and returns the
evaluation as the evaluator returned it (`value`), the integration's
references into it (`outputs`) and the finalized configurations
declared beneath it, by integration and then name (`children`).

The evaluation has a childless view and a full view. Each is a
manifest, and each runs on the declaring lib rebuilt with that manifest
as `evalManifest` (`withManifests`).

- The **childless** view is the evaluation without the configurations
  declared beneath it: `childless = true` and no `children`.
- The **full** view is the manifest returned. It carries the childless
  manifest as `childlessManifest`, and children are finalized against
  that, so a child's `parent` and `nearest.<integration>` are the
  childless manifest of the configuration that declares it.

A configuration with children is evaluated in both views, and a
configuration with none is evaluated once.

`forChildren` is what the evaluation gives the configurations
declared inside it. It has three fields:

- `extraDefaultModuleImports`, by class a list of selections, each a
  function of a lib returning modules.
- `defaultPkgs`, which selects the package set its children run on by
  default. It is null when the configuration selects no set.
- `systems`, the systems its children are evaluated for. It is null
  when the configuration lists no systems.

They are read from the childless evaluation and recorded on the
manifest as `forChildren`. A configuration declared inside inherits
the selections of its parent, extended by them. Its manifest holds
the selections added above it as `defaultModuleImports`, those from
the top first. Every level extends them in turn, so a selection
reaches the configurations beneath the level that added it, nested
ones and ones beneath a system included.

Both views carry `type`, `name`, `parent`, `ancestors` (the parent's
list with the parent appended), `nearest` (the parent's attrset with
the parent under its integration; a lib is not among them), `inputs`,
and the parent's `sources`, `root`, `systems`, `projects`,
`defaultEcosystemSrc`, `pkgSets` and registries. A `record` that names
a field `mkConfiguration` writes is refused.

An integration that evaluates a configuration at a system passes
`perSystem = true`. A declared configuration is then an evaluation for
every system in force where it is declared, and the configuration
returns those evaluations by system. In the tree the system sits
above the name:

```
flake
└── children.system
    ├── x86_64-linux                     type system
    │   └── children.nixos.hostname2     an evaluation, with a value
    └── aarch64-linux                    type system
        └── children.nixos.hostname2     an evaluation, with a value
```

There are as many evaluations as there are systems in force, also for
a single system, and none where no system is in force; nothing is
refused. Each evaluation is a manifest as described above, under the
name it is declared by, carrying its system as `system`, and its
parent is the system, a manifest of type `system`. The parent's full
manifest holds each system under `children.system`, beside the
configurations evaluated once for every system, which stay under
`children.<integration>`.

Where a configuration that is evaluated per system is declared inside
another, the system of its parent is the default. A home declared
inside a NixOS configuration has, by default, one evaluation per
evaluation of the machine, for the same system. The manifest of each
evaluation of the machine holds that system as `systems`.

A parent changes this by returning `forChildren.systems`, the systems
its per-system children are evaluated for: a machine that holds an
image for another architecture states that architecture there. A configuration
that is evaluated once can return a list the same way, to narrow what
its children are evaluated for. The list has to come from the systems
allowed where that parent is declared, and a system outside them is
refused.

`finalizeChild` accepts either result, a manifest or the evaluations
by system.

### `elide`

```
lib.caisson-core.elide : listOf path -> listOf (listOf str)
path = listOf { type : str; name : str; }
```

The naming rule. A path is the list of segments from a top down to a
thing, ending in the name of the thing; a system is a segment of type
`system`. For each path, in order, `elide` returns the segments
needed to tell the thing apart from the others, as strings in path
order.

It keeps the last segment of every path, and beyond it only the
segments where paths that end in the same name fork. Among those
paths it drops the prefix they share, keeps the segment at which they
first differ, the segment nearest the top that separates them, and
does the same within each branch.

```nix
elide [
  [ { type = "structural"; name = "a"; } { type = "system"; name = "x86_64-linux";  } { type = "nixos"; name = "host-1"; } ]
  [ { type = "structural"; name = "b"; } { type = "system"; name = "aarch64-linux"; } { type = "nixos"; name = "host-1"; } ]
  [ { type = "structural"; name = "a"; } { type = "system"; name = "x86_64-linux";  } { type = "nixos"; name = "host-2"; } ]
]
# [ [ "a" "host-1" ] [ "b" "host-1" ] [ "host-2" ] ]
```

A name that is alone stays bare, whatever sits above it, so the system
above a configuration with a single system in force drops out. A
segment is kept as its name, or as `type/name` where the branches of
that fork hold the same name under several types. How the kept
segments are written out as a name, and a clash between equal paths,
are for whoever publishes them (`caisson.integrations.publish`).

### `finalizeTop`

```
lib.caisson-core.finalizeTop : configuration -> manifest
```

Finalizes the configuration a top ends with. A top has no parent that
declares it under an attribute, so its name is the name the composition
declares on `mkLib`, absent when it declares none, and its parent is
the lib's manifest. An integration's `mkTopConfiguration` is this
followed by the step that turns the result into what a tool reads.

### `importApply`

```
importApply : freeformModule -> attrs -> module
```

Applies static arguments to a module through `_file`/`imports` wrappers while preserving wrapper metadata. Used for threading arguments through module import chains.

### `compose`, `resolve`

`compose` composes entries by key. `resolve` resolves an ecosystem
source from `explicit`, `defaults` and `sources`, in that order. See
[How `lib` is composed](../deep-dives/how-lib-is-composed.md) and
the documentation of caisson-core.

## The caisson namespace

The functions, registries and manifests a flake uses are under
`lib.caisson`. It holds those listed in
[Functions and registries](#functions-and-registries-under-libcaisson),
a namespace per integration target (`lib.caisson.flake-parts`,
`lib.caisson.nixos`, and so on; see
[Integration namespaces](#integration-namespaces)), and the
pkgs-dependent tooling documented at the end of this section.
caisson's registered flake modules are listed here too.

### Functions and registries under `lib.caisson`

```nix
lib = caisson.lib.caisson.mkLib {
  inherit (caisson.lib.caisson.pins.flake inputs) sources root;
  projects = { inherit caisson; };
  modules = lib: lib.caisson.mkModules ./modules;
  configs = lib: lib.caisson.mkModules ./configs;
  libOverlays = lib: lib.caisson.mkLibOverlays ./lib-overlays;
};
```

| Group | Names under `lib.caisson` |
| --- | --- |
| composing | `mkLib`, `pins`, `callFlake`, `callConsumerFlake`, `realizeInputs` |
| making and reading entries | `mkModule`, `mkModules`, `mkLibOverlay`, `mkLibOverlays`, `mkPkgOverlay`, `mkPkgOverlays`, `importApply` |
| registries | `modules`, `configs`, `libOverlays`, `pkgOverlays`, `pkgOverlaysFor` |
| manifests | `libManifest`, `pkgsManifest`, `evalManifest`, `manifestOf` |
| for an integration written outside caisson | `finalizeTop`, `elide`, `ecosystemSrc` |

- `pins`, `callFlake`, `callConsumerFlake` and `realizeInputs` are
  defined in caisson and documented below.
- `modules`, `configs`, `libOverlays` and `pkgOverlays` are read from
  the manifest of the library (`lib.caisson-core.libManifest`). They
  are empty in a library that no `mkLib` built.
- Every other name is the value of the same name under
  `lib.caisson-core` in the same library, documented in
  [The caisson-core namespace](#the-caisson-core-namespace).
  caisson-core is the library caisson is built from.
- Several arguments of `mkLib` are functions of a library that is
  still being built. In the `mkLib` of caisson-core, `libOverlays` and
  `libOverlayImports` receive a library that holds only the
  caisson-core names. `lib.caisson.mkLib` adds the names above, under
  `lib.caisson`, to the library each of those functions receives.

### Overlay imports

An entry of `libOverlays` or `pkgOverlays` states what it imports as
names or as entries, and both registries treat them the same way.

- A name is looked up in the registry of the flake that registers the
  importer. `imports = [ "base" ];` imports an entry of the same
  flake, and `imports = [ "caisson/nixpkgs-lib" ];` imports an entry
  of a consumed project.
- When a project is consumed, its entries become `<project>/<name>`,
  and the names in their imports are renamed the same way. An entry
  that imports another entry of its project is therefore composed
  once.
- Registering under a name replaces that entry for everything that
  imports it.
- Two entries built from different files under one key are refused.

### `pins`

```
lib.caisson.pins.flake        : inputs -> { sources; root; }
lib.caisson.pins.flake-compat : path -> { sources; }
lib.caisson.pins.npins        : path -> { sources; }
lib.caisson.pins.gitRoot      : path -> root
```

`pins` holds a reader per pin system. Each reads the files of its pin
system into `sources`: the pinned source trees, each as its pin system
hands it over (a flake input keeps its outputs), with `pin`, the
record of how it is pinned.

- `pin.system` is `"flake"` from either flake reader and `"npins"`
  from `pins.npins`. It says which tool moves the source.
- `pin.files` is `{ refs; revisions; }`: the file that holds the ref
  and the file that holds the revision, relative to `pin.dir` when
  present and to the root of the flake otherwise.
- `pin.dir` is the directory holding the pin files, for a reader given
  a directory.
- `pin.url` is the ref as the pin files write it.
- `pin.rev`, `pin.narHash` and `pin.lastModified` identify the source
  tree, where the pin system records them.
- `pin.follows` is, for a flake input declared as a `follows`, the
  path of input names it follows. Its source tree is that of the input
  it lands on.
- `pin.overridden` is set by `pins.flake` alone. It is true when an
  `--override-input` replaced the input, in which case `pin.url`
  describes the lock and not the source tree.

`pins.flake inputs` reads the inputs Nix's flake evaluator resolved for
the flake being evaluated, the `inputs` its `outputs` receives, and
returns the `root` from `self`.

`pins.flake-compat ./dir` resolves the `flake.lock` beside a
`flake.nix` in that directory the way flake-compat does, stopping
before the flake's `outputs`. Nix's flake evaluator does not see that
pair of files, so no `--override-input` applies to it and it has no
root. It stays valid under read-only evaluation (`nix flake check
--no-build`). A flake-parts partition takes the inputs of its
lockfile'd subflake from this reader.

`pins.npins ./npins` reads `sources.json` format 8 and fetches each
pin as npins' generated `default.nix` does. It refuses Container
pins, which need nixpkgs.

A root is `{ outPath; dirty; rev; shortRev; dirtyRev; dirtyShortRev;
lastModified; lastModifiedDate; narHash; }`. It identifies the source
tree being built, with the source-info fields a flake's `self` has,
each null where the reader has no value for it. The names are fixed
and the values lazy, since inside a flake's `outputs` asking which
attributes `self` has forces the outputs being computed. The names of
a flake input's `pin` are fixed for the same reason, and `pin.url` and
`pin.follows` are null where they do not apply. A flakeless top in a
git working tree reads its root with `pins.gitRoot ./.` under an
impure evaluation. The result has the revision of a clean working
tree, or `dirty = true` with `dirtyRev` for a dirty working tree.

```nix
# flake.nix outputs
inherit (caisson.lib.caisson.pins.flake inputs) sources root;

# test-only pins beside the pins of the flake
inherit (lib.caisson.pins.flake-compat ./tests/dependencies) sources;

# a flakeless top pinned with npins
inherit (lib.caisson.pins.npins ./npins) sources;
root = lib.caisson.pins.gitRoot ./.;
```

### `callFlake`, `callConsumerFlake`

```
lib.caisson.callFlake : { src, inputs, sourceInfo ? { } } -> flakeOutputs

lib.caisson.callConsumerFlake :
  { path       : path | string   # directory containing flake.nix
  , pool       ? { } : attrs     # inputs resolvable by name
  , overrides  ? { } : attrs     # highest-precedence injections
  , sourceInfo ? { } : attrs     # extra self attrs (lastModified, rev, ...)
  } -> flakeOutputs              # self: inputs, outputs, outPath, _type
```

`callFlake` applies the outputs function of a flake to inputs given as
values and fetches nothing. The flake-parts integration instantiates
flake-parts with it.

`callConsumerFlake` evaluates a consumer-style flake from source with
inputs supplied by hand, which is how a flake checks the flakes under
its `tests/`. The declared inputs of that flake resolve by name:
`overrides` first, then `follows` chains through the other resolved
inputs, then `pool`. An input that does not resolve throws an error
naming it. `callFlake` handles the `self` fixpoint and its
decoration, and the eval-weight harness uses it too. Nothing is
fetched: locks are not read, and `sourceInfo` attributes appear only
if supplied. See [Testing](../testing.md).

### `realizeInputs`

```
lib.caisson.realizeInputs : inputs -> { "<name>/<name>/…" = storePath; }
```

`realizeInputs` takes flake inputs that Nix has already resolved. It
makes sure that each input is present in the Nix store, and it returns
the store path of each input. It does the same for the inputs of each
input, and for the inputs of those, to any depth. "Realize" is the
word Nix uses for making sure a store path is present, as in
`nix-store --realise`.

The name of each input in the result is the list of input names that
leads to it, joined with `/`. That is the form of name that the Nix
flag `--override-input` takes:

```nix
lib.caisson.realizeInputs { inherit (inputs) caisson; }
# => {
#   "caisson" = "/nix/store/…-source";
#   "caisson/caisson-core" = "/nix/store/…-source";
#   "caisson/flake-parts" = "/nix/store/…-source";
#   "caisson/flake-parts/nixpkgs-lib" = "/nix/store/…-source";
#   "caisson/nixpkgs-lib" = "/nix/store/…-source";
# }
```

When two inputs both follow a third input, the third input appears in
the result twice, once under each name that leads to it. The function
leaves out `self`. An input that is a plain source tree has no inputs,
and neither has a store path that the caller writes directly as a
value.

**The problem the function solves.** Some tools evaluate a flake from
inside a Nix build. nix-unit does this when it runs as a flake check.
The check is a derivation. The builder of that derivation runs
nix-unit, and nix-unit evaluates the flake that holds the tests.

Nix runs every builder in a sandbox. Inside the sandbox, the builder
can see a path in the Nix store only when the derivation names that
path as a dependency. The rest of the store is hidden from the
builder. The builder also has no network access.

So when nix-unit evaluates the flake and the evaluation needs a flake
input, the evaluation fails. Nix looks for the input in the store and
does not see it, because the derivation did not name it. Nix then
tries to download the input and cannot, because the builder has no
network access. The check fails with the message `unable to download`.

The lock file of the flake does not change this. The lock file tells
Nix which revision of the input to use. It does not put a copy of that
revision where the builder can see it.

**How the problem is solved by hand.** nix-unit accepts the flag
`--override-input <name> <store path>` for each input. The flag
tells nix-unit to read the input from that store path
and not to fetch it. The store path is also written in the command
that the builder runs, so the derivation names the store path as a
dependency, and the builder can see it. The flake-parts module of
nix-unit writes these flags from the option `nix-unit.inputs`, which
is an attribute set of names and store paths.

The inputs of an input need the same flag. Suppose a test composes
caisson as a project. To do that, nix-unit has to evaluate the caisson
flake. The caisson flake has inputs too, and caisson-core is one of
them. Nix looks for caisson-core, does not see it, and the check fails
in the way described above. The flag for an input of an input names
both of them: `--override-input caisson/caisson-core <store path>`.

Writing these flags by hand means copying the list of inputs out of
the lock file of the caisson flake, and keeping that copy up to date.
If a name is missing from the copy, nothing reports it until the check
runs and fails inside the sandbox. `realizeInputs` builds the whole
set from the resolved inputs.

**Which inputs to give the function.** Give the function the inputs of
the test flake:

```nix
nix-unit.inputs = lib.caisson.realizeInputs inputs;
```

The result then names each input of the test flake and each input of
those inputs, so the test flake needs no `follows` to point the inputs
of its inputs back at inputs it already lists.

To return the store path of an input, Nix has to fetch that input. The
function therefore fetches every input it is given, and every input of
those inputs, to any depth. It fetches an input even when no test
reads it. For most test flakes that adds a few small sources.

The cost is large when one input exists to gather many others. The
unit test flake of caisson has an input of that kind, `deps`, which
pins everything any caisson test uses. Given all the inputs of that
test flake, the function fetches 24 sources where the unit tests read
6. In that case, give the function only the inputs that the tests
evaluate as flakes, and list the other inputs directly:

```nix
nix-unit.inputs = inputs // lib.caisson.realizeInputs { inherit (inputs) caisson; };
```

An input that the test flake declares with `flake = false` has no
inputs as far as the test flake is concerned. Give the function such
an input as a source tree, and not as an evaluated flake, or the
result will name inputs under it that nix-unit reports as matching
nothing. See also [Testing](../testing.md#unit-tests).

### `modules.<class>."caisson/core"`, `modules.flake."caisson/default"`

- **Source:** `modules/generic/core/` (the core module; `caisson.*`
  options under `caisson/`), `modules/structural/core`,
  `modules/nixos/core` and `modules/homeManager/core` (symlinks to
  it), `modules/flake/core/` (imports it and adds the flake
  mechanics), `modules/flake/default/`

caisson's core module, the `caisson.*` options every evaluation
carries (the manifest, the registry selectors, `caisson.exports`),
registered as `core` in the class-free `generic` class and in every
class whose integration forces it (`flake`, `structural`), and
exported so a consumer's composition carries `caisson/core` there.

The registry selectors, `caisson.libOverlays.exported`,
`caisson.modules.<class>.exported` and `caisson.pkgOverlays.exported`,
each choose what of a
registry leaves the project, and each defaults to the entries the
project registers itself. An entry a consumed project contributed
(`<project>/<name>`), or an entry caisson-core publishes into every
composition, leaves only when a selector names it: a project
republishes an upstream's entries only on purpose, and a consumer
takes them from that upstream through its `projects`. The exported
entries are in the manifest. The
outputs are `modules` (and `flakeModules`) and `overlays`.
`caisson.flakeOutputs.modules` selects which exported
modules the `modules` output holds. `overlays` holds the exported
package overlays as plain nixpkgs overlays. The exported lib overlays
have no output.
`caisson/default` for the `flake` class is caisson's contribution to
the default default: it imports `caisson/nixpkgs` below.

### `modules.nixos."caisson/default"`, `modules.homeManager."caisson/nixos-parent"`

- **Source:** `modules/nixos/default/`,
  `modules/homeManager/nixos-parent/`

These two modules are what a NixOS configuration gives the homes
declared inside it.

home-manager has a NixOS module that embeds homes in a machine. For
each home, that module sets a few options of the home from the
machine. caisson does not use that NixOS module. A home declared
inside a NixOS configuration is a caisson configuration, and it gets
the same settings from the home-manager module
`caisson/nixos-parent`.

`caisson/default` is the `default` NixOS module caisson registers. A
NixOS configuration imports every registered module named `default`
unless it passes `moduleImports`. This module sets
`caisson.forChildren.extraDefaultModuleImports.homeManager`, which adds
`caisson/nixos-parent` to the modules that the homes declared inside
the machine import by default. It also imports
[`caisson/home-manager-activation`](#modulesnixoscaissonhome-manager-activation),
which runs those homes on the machine.

`caisson/default` also brings in the modules described under
[`caisson/home-manager-source-marker`](#modulesnixoscaissonhome-manager-source-marker-moduleshomemanagercaissonnixos-source-marker).
With those modules, a home prints a warning when it is activated
on a machine it was not built for.

`caisson/default` also imports
[`caisson/hjem-activation`](#modulesnixoscaissonhjem-activation), which
activates the hjem configurations declared inside the machine, and adds
the hjem module
[`caisson/nixos-parent`](#moduleshjemcaissonnixos-parent) to the modules
those configurations import by default.

`caisson/default` also defines `networking.hostName` as the name the
NixOS configuration is declared under, at `mkDefault` priority. So the
machine declared as `nas-1` names itself `nas-1`, and a host name the
machine's own modules set replaces it. A NixOS configuration with no
name, and an evaluation without NixOS's networking module (the minimal
NixOS evaluator), keep NixOS's default.

`caisson/nixos-parent` sets these options of the home:

| Option of the home | Value |
| --- | --- |
| `home.homeDirectory` | `users.users.<user>.home` of the machine, when the machine declares that account |
| `home.uid` | `users.users.<user>.uid` of the machine, when the machine declares that account and its `uid` is set |
| `nix.enable` | `nix.enable` of the machine |
| `nix.package` | `nix.package` of the machine, when the machine has Nix enabled |
| `submoduleSupport.enable` | `true`, which home-manager reads to tell that a machine activates the home |
| `home.packages` | home-manager's command-line program, when the home sets `programs.home-manager.enable` |

`<user>` is `home.username` of the home.

A machine whose user is managed by systemd-homed has no entry for
that user in `users.users`. For such a home, `nixos-parent` leaves
`home.homeDirectory` and `home.uid` alone, and the home sets its home
directory itself.

home-manager leaves its command-line program out of a home that has
`submoduleSupport.enable` set. `nixos-parent` puts it back, because
the program is how the user runs `home-manager switch`.

A NixOS configuration or a home can take `nixos-parent` out:

- A NixOS configuration that passes `moduleImports` selects its
  modules itself. It does not import `caisson/default`, and then no
  home inside it gets `nixos-parent` from caisson.
- A home that passes `moduleImports` selects its modules itself, and
  then that home does not get `nixos-parent`.

Each can keep it while selecting its other modules. The NixOS
configuration lists `caisson/default`, which is a NixOS module, in its
selection. The home lists `caisson/nixos-parent`, which is a
home-manager module, in its selection.

`nixos-parent` reads the machine through the manifest of the home, so
only a home with a NixOS configuration above it can import it.

In a NixOS evaluation whose library is not a caisson composition,
`caisson/default` defines nothing, as the core module declares
nothing there.

### `modules.nixos."caisson/home-manager-activation"`

- **Source:** `modules/nixos/home-manager-activation/`

The NixOS module with which a machine activates the homes declared
inside it. `caisson/default` for the `nixos` class imports it, so a
NixOS configuration has it unless it passes `moduleImports`.

Activating a home means running the `activate` script of its
activation package as the user of the home. The script links the
files of the home into the home directory and installs its packages.
This module writes a systemd unit for each home, so that switching
the machine to a new generation also applies its homes. caisson does
not use home-manager's NixOS module for this.

**Which homes.** The module activates the home-manager configurations
that the NixOS configuration passes up. Those are the homes declared
inside it, also through a structural configuration, that its
`caisson.home-manager.exported` selector selects. The module leaves
out:

- A home declared inside a NixOS configuration that is itself inside
  this one. That home belongs to the inner machine.
- A home evaluated for a system other than the system of this
  machine.

**The account of the user.** The module expects the machine to declare
the account of the user of each home in `users.users`. A home whose
user has no account there is refused, with an assertion that names the
home and the user. On most machines such a home is a mistake: a
misspelled user name, or a home declared on the wrong machine.

Some accounts are provided by something other than `users.users`. An
account that systemd-homed manages is one. systemd-homed keeps the
record of it, the machine must not declare it a second time, and its
home directory is mounted only at login. The option
[`caisson.home-manager.activation.usersDeclaredElsewhere`](./options.md#caissonhome-manageractivationusersdeclaredelsewhere)
lists the users that have such an account on the machine. The home of
a listed user is not refused.

**Which unit.** The unit depends on what provides the account of the
user.

| | Account in `users.users` | User listed as declared elsewhere |
| --- | --- | --- |
| Unit | system unit `home-manager-<user>` | user unit `home-manager-<user>` |
| Runs | during boot, as that user, before users can log in | when the service manager of that user starts, at login |
| Restricted by | `User=<user>` | `ConditionUser=<user>` |
| Waits for | the home directory, and the Nix daemon socket | the home directory |

`<user>` is `home.username` of the home.

The system unit is the unit home-manager's NixOS module writes.

**The profile of the home.** Both units run `activate` with no driver
version. home-manager calls that the legacy behavior: the script also
updates the home-manager profile of the user. The user can then run
`home-manager switch` and `home-manager generations` on the same
profile. home-manager's NixOS module passes `--driver-version 1`,
which leaves the profile alone.

**Two homes for one user.** A machine that would activate two homes
with the same `home.username` fails an assertion. The message names
the user and both homes. Give one of the homes a different
`home.username`, or leave one out with
`caisson.home-manager.exported`.

**Where the module defines nothing.** The module reads the homes from
the full evaluation of the NixOS configuration, so it defines nothing
in the childless evaluation. It also defines nothing in a NixOS
evaluation that declares no systemd options. The nixos-minimal
integration produces such an evaluation, and a machine of that kind
cannot run units.

### `modules.nixos."caisson/hjem-activation"`

- **Source:** `modules/nixos/hjem-activation/`

The NixOS module with which a machine activates the hjem configurations
declared inside it. `caisson/default` for the `nixos` class imports it,
so a NixOS configuration has it unless it passes `moduleImports`.

Activating a hjem configuration means applying its manifest with
hjem's CLI. The CLI links the files of the user and removes the files of
the previous generation, whose manifest the machine keeps in
`/var/lib/hjem/manifest-<user>.json`. The module writes the units that
hjem's NixOS module writes, under the same names:

| Unit | Runs |
| --- | --- |
| `hjem-prepare` | creates `/var/lib/hjem` |
| `hjem-activate@<user>` | as the user, links the files of the new manifest |
| `hjem-reload@<user>` | as the user, reloads the systemd user units that the change touched, when the service manager of the user is running |
| `hjem-update-state@<user>` | stores the new manifest in `/var/lib/hjem` |
| `hjem-cleanup` | removes the stored manifests of users that are no longer activated |

The target `hjem` requires them all, and starts at boot and when the
machine switches to a new generation. Each instance runs the CLI of the
hjem configuration of its user. The units link with hjem's own CLI and
back up a file they replace under the prefix `.backup-`. hjem's NixOS
options for another linker, for `systemd-tmpfiles` and for
`clobberByDefault` have no counterpart here; a configuration sets
`clobberFiles` itself.

The module also adds the `packages` of each user to
`users.users.<user>.packages`, and keeps the `extraDependencies` of each
user in the closure of the system.

**Which configurations.** The hjem configurations that the NixOS
configuration passes up and that are enabled, leaving out those
declared inside a NixOS configuration that is itself inside this one,
and those evaluated for another system. A machine that would activate
two hjem configurations with the same `user` fails an assertion naming
the user.

The module defines nothing in the childless evaluation, and nothing in
a NixOS evaluation that declares no systemd options, such as one from
the nixos-minimal integration.

### `modules.hjem."caisson/nixos-parent"`

- **Source:** `modules/hjem/nixos-parent/`

The hjem module that a NixOS configuration adds to the modules that the
hjem configurations declared inside it import by default, through
`caisson/default`. It sets `directory` to `users.users.<user>.home` of
the machine, at `mkDefault` priority. It refuses an enabled
configuration whose user has no enabled account on the machine, with an
assertion naming the user, as hjem's NixOS module does.

A hjem configuration that passes `moduleImports` gets this module only
if its list names it. The module reads the machine through the manifest
of the configuration, so only a hjem configuration with a NixOS
configuration above it can import it.

### `modules.nixos."caisson/home-manager-source-marker"`, `modules.homeManager."caisson/nixos-source-marker"`

- **Source:** `modules/nixos/home-manager-source-marker/`,
  `modules/homeManager/nixos-source-marker/`

With these two modules, a home prints a warning when it is activated
on a machine it was not built for.

The machine activates the homes declared inside its NixOS
configuration. The user can also activate such a home by hand, with
`home-manager switch`. `home-manager switch` builds the home from the
source the user has checked out.

That source can describe a different machine than the machine that is
running. This happens when the user changed the NixOS configuration
and has not switched the machine yet. It also happens when the
checkout is older than the machine.

A home reads settings of its machine. A home built from such a source
has read the settings of a machine that is not the machine the home
is activated on.

**The file on the machine.** The NixOS module
`caisson/home-manager-source-marker` writes the file
`/etc/caisson-home-manager/source.json`. `caisson/default` for the
`nixos` class imports this module. A NixOS configuration therefore
has the module unless the NixOS configuration passes `moduleImports`.

The file has one field, `baseSystemOutPath`. It is the store path of
the system of the NixOS configuration, as its childless evaluation
builds it.

The childless evaluation is the evaluation of the NixOS configuration
that leaves out the configurations declared inside the NixOS
configuration. The homes are among those configurations. So
`baseSystemOutPath` does not depend on the homes. Changing a home
leaves `baseSystemOutPath` the same. Changing anything else about the
machine changes it.

The module writes the file only when at least one home is declared
inside the NixOS configuration. A NixOS configuration can have a
second NixOS configuration declared inside it. A home declared inside
the second NixOS configuration belongs to the second, and does not
count for the first.

**The comparison in the home.** The home-manager module
`caisson/nixos-source-marker` computes the same store path from the
source the home is built from. The module reads the childless
evaluation of the NixOS configuration through the manifest of the
home.

The module adds a step to the activation of the home. The step
compares the store path the module computed with `baseSystemOutPath`
in the file. The step prints a warning when they differ. The step
also prints a warning when the file does not exist. The step does not
stop the activation.

`caisson/default` for the `nixos` class gives this module to the
homes declared inside the machine, through
`caisson.forChildren.extraDefaultModuleImports.homeManager`. Such a home
imports the module by default. A home that passes `moduleImports`
imports the module only if the home lists it.

The option
[`caisson.home-manager.machineDrift.warn`](./options.md#caissonhome-managermachinedriftwarn)
of the home removes the step.

**When the machine activates the home.** The file on the machine then
already belongs to the generation that is being activated. The store
path the module computed equals `baseSystemOutPath`, and the step
prints nothing.

**Cost.** Both modules evaluate the system of the childless
evaluation. That is a second evaluation of the whole NixOS
configuration. A NixOS configuration with no homes writes no file and
does not pay for the second evaluation.

**Where the NixOS module defines nothing.** The NixOS module defines
nothing in the childless evaluation, because the childless evaluation
has no homes. The NixOS module also defines nothing in a NixOS
evaluation that has no `environment.etc` option. The nixos-minimal
integration can produce such an evaluation.

### `modules.darwin."caisson/default"`

- **Source:** `modules/darwin/default/`, `modules/homeManager/darwin-parent/`,
  `modules/hjem/darwin-parent/`, `modules/darwin/home-manager-activation/`,
  `modules/darwin/hjem-activation/`

`caisson/default` is the `default` darwin module caisson registers. A
darwin configuration imports every registered module named `default`
unless it passes `moduleImports`. It holds what a macOS machine does
for the homes and the hjem configurations declared inside it.

It adds the home-manager module `caisson/darwin-parent` to the modules
that the homes inside the machine import by default, and the hjem
module `caisson/darwin-parent` to those of the hjem configurations.
They set what home-manager's and hjem's nix-darwin modules set from the
machine:

| Module | Option | Value |
| --- | --- | --- |
| home-manager `darwin-parent` | `home.homeDirectory` | `users.users.<user>.home` of the machine, when the machine declares that account |
| | `home.uid` | `users.users.<user>.uid` of the machine, when it is set |
| | `nix.enable`, `nix.package` | those of the machine |
| | `submoduleSupport.enable` | `true` |
| | `home.packages` | home-manager's command-line program, when the home sets `programs.home-manager.enable` |
| hjem `darwin-parent` | `directory` | `users.users.<user>.home` of the machine, at `mkDefault` priority |

The hjem module refuses a user that has no account in `users.users`.

#### `modules.darwin."caisson/home-manager-activation"`

The darwin module with which a machine activates the homes declared
inside it. `caisson/default` imports it. A step of the machine's
`postActivation` script runs the `activate` script of each home as its
user, through `launchctl asuser` and `sudo`, as home-manager's
nix-darwin module does, so `darwin-rebuild switch` applies the homes. A
home whose user has no account in `users.users` is refused with an
assertion, and so are two homes for one user.

The step runs `activate` with no driver version, as caisson's NixOS
activation does. The script then also updates the home-manager profile
of the user, so the user can run `home-manager switch` on the same
profile. home-manager's nix-darwin module passes `--driver-version 1`,
which leaves the profile alone.

#### `modules.darwin."caisson/hjem-activation"`

The darwin module with which a machine applies the hjem configurations
declared inside it. `caisson/default` imports it. It writes the two
launchd agents of hjem's nix-darwin module, with the same labels and
scripts:

| Agent | Runs |
| --- | --- |
| `org.hjem.activate` | at login and when the machine is activated, as the user: applies the manifest of the user, with the state in `~/Library/Application Support/Hjem` |
| `org.nix.link-nix-apps` | the same: links the applications of the packages of the user into `~/Applications/Nix User Apps` |

Each agent exits for a user that no hjem configuration of the machine
names, and runs the CLI of the hjem configuration of the user it runs
for. The module also adds each user's `packages` to
`users.users.<user>.packages`, and lists each user's
`extraDependencies` in `/etc/hjem/extra-dependencies`, which keeps them
in the system.

The module differs from hjem's nix-darwin module in two places:

- It declares the agents in `launchd.agents`. nix-darwin installs those
  in `/Library/LaunchAgents`, where launchd loads them for every user
  who logs in. hjem's nix-darwin module declares them in
  `launchd.user.agents`, which nix-darwin installs for
  `system.primaryUser` alone, and it requires the machine to set
  `system.primaryUser`.
- It restarts the agents of each user from `postActivation`, which
  nix-darwin runs after it installs the agents of the new generation.
  hjem's nix-darwin module restarts the activation agent from an
  activation step that nix-darwin does not run, and the applications
  agent from a step that runs before the agents are installed.

### `modules.flake."caisson/nixpkgs"`

- **Source:** `modules/flake/nixpkgs/`

The nixpkgs integration's flake module. It hands `perSystem` the
package sets of the package configs declared in `mkLib`'s `pkgSets`
(see `caisson.nixpkgs` below), and exports from them:

- The `perSystem` `pkgSets` argument is every package config's set at
  that system, keyed by config name, and `pkgs` is the `default`
  config's set. A flake that declares no `default` config keeps the
  `pkgs` flake-parts provides.
- The flake's `overlays` output carries the entries of
  `caisson.pkgOverlays.exported` as plain overlays, each with the
  entries it imports composed in, so a consumer that is not caisson
  gets a working overlay.
- `pkgs.export.enabled`, `packages.export.enabled`: whether to export
  `legacyPackages`, and the package scope of the flake
  (`pkgs.<name>`, after the `name` declared on `mkLib`) as `packages`.

### `integrations`

- **Source:** `lib-overlays/integrations/default.nix`

This namespace holds the functions that every integration is written
from. Each integration overlay imports this overlay by key, so
composing any integration composes this overlay as well, and the
integration reads these functions through `final`.

#### `mkEvaluation`

```
mkEvaluation : { compose, evaluate } -> args -> result
```

`mkEvaluation` is the body of both entry points of an integration. It
passes the arguments the entry point's pattern admitted to `compose`,
which returns an attribute set holding `ecosystemArgs`, the arguments
of the evaluator's call as the integration composed them, beside
anything `evaluate` needs, such as the resolved source. It then calls
`evaluate` with that set and the call to make. When the arguments
carry `ecosystemArgs`, which only the pattern of the
`WithEcosystemArgs` twin admits, they are merged over the composed
call verbatim, last.

The pattern is the whole check. Every entry point is a function of an
attribute set pattern with no `...`,
so Nix matches the call against the pattern before the body runs: a
missing or unexpected argument is Nix's error, named after the entry
point and raised at the call site, with no frame of caisson above it.
Required arguments are bare in the pattern and optional arguments
default to `null`; the composition supplies the value of an omitted
argument. `builtins.functionArgs` reads a signature back as data.

#### `resolveEcosystemSrc`

```
resolveEcosystemSrc : { name, context } -> { explicit ? null, manifest ? libManifest } -> src
```

`resolveEcosystemSrc` finds the source of an ecosystem in the layered
order that [Ecosystem sources](../concepts/ecosystem-sources.md)
describes: the explicit argument first, then `defaultEcosystemSrc.<name>`
as declared in the composition, then the pinned source named exactly `<name>`.
The first call names the ecosystem and the caller; the second supplies
the explicit argument and the manifest to read the declarations from.
When nothing provides a source, it throws a message that names the
caller and those places.

#### `coreModules`, `defaultModuleImports`

```
coreModules          : attrsOf module -> listOf module
defaultModuleImports : attrsOf module -> listOf module
```

Both take a class registry (`lib.caisson.modules.<class>`) and
select entries by name. `coreModules` returns every entry named `core`,
which includes the `<project>/core` entries of consumed projects;
these form the framework module of the class, and every integration
applies them to every evaluation. `defaultModuleImports` returns every
entry named `default`, in the same way; this list is the default
default, the selection an evaluation gets when it passes no
`moduleImports`.

#### `integrationsIn`, `childrenOf`, `configurationsModuleFor`, `nearestOf`

```
integrationsIn          : options -> listOf str
childrenOf              : { options; config } -> attrsOf (attrsOf manifest)
configurationsModuleFor : listOf str -> module
nearestOf               : listOf str -> manifest -> manifest or null
integrationsDeclaringIn : options -> listOf str
```

`integrationsDeclaringIn` is the part of `integrationsIn` whose
`caisson.<integration>.configurations` a module of the evaluation
defines. `childrenOf` and re-export read only those integrations, so an
evaluation does not merge the options of an integration it holds no
configurations of.

`nearestOf` takes a list of integration names and a manifest, and
returns the nearest configuration above the manifest whose integration
is one of them, null when there is none. The home-manager and hjem
integrations find the machine of a configuration with
`nearestOf [ "nixos" "darwin" ]`.

`integrationsIn` takes the options of an evaluation and lists the
integrations whose configurations it can hold beneath it: those whose
`configurationsModule` the evaluation imports, which declares
`caisson.<integration>.configurations` and
`caisson.<integration>.exported`. `configurationsModuleFor` takes a
list of integration names and returns one module that declares those
options for all of them. The core module of caisson imports it once,
for every integration of caisson, which costs less to evaluate than a
module per integration. `childrenOf` takes the
options and the `config` of an evaluated configuration and returns
the configurations declared beneath it, by integration and then name,
leaving out an integration with none: the `children`
`mkModuleConfiguration` hands to `lib.caisson-core.mkConfiguration`.
It reads only the options that a module of the evaluation defines.

#### `frameworkModules`, `mkModuleConfiguration`

```
frameworkModules      : str -> attrsOf module -> listOf module
mkModuleConfiguration : { type : str; perSystem ? false; defaultPkgs ? null; exportsTo ? null; evaluate : view -> evaluated; } -> configuration
evaluated = { value; outputs ? { }; config ? value.config; }
exportsTo = export | listOf export
export    = { attrset : str; value : manifest -> value; single ? false : bool;
              bySystem ? false : bool; only ? : manifest -> bool;
              name ? : { name, manifest } -> { value : str; description ? : str; }; }
```

`mkModuleConfiguration` builds a configuration that is a module
evaluation. `type` and `perSystem` are what
`lib.caisson-core.mkConfiguration` takes. `evaluate` is the evaluator
step of the integration: from the view being evaluated,
`{ lib, manifest }`, it returns `value`, the evaluation as the
evaluator returned it, and `outputs`, the references into it that the
integration declares (`config` says where the evaluated options are
when that is not `value.config`). `defaultPkgs` is the package set
selection the configuration was constructed with, which the builder
records on the manifest (`pkgSetOf` below).

`exportsTo` says how the configuration is published, and the builder
records it on the manifest too. It is one export, or a list of them for
an integration whose configurations are published in more than one
output. `attrset` is the output attribute set; a NixOS configuration
records `nixosConfigurations`. `value` takes the manifest of the
configuration to what is published.

`only` takes the manifest and says whether the configuration is
published in that output at all. A configuration it leaves out is still
passed up. The treefmt integration
uses it to publish only the configuration named `default`.

`single` says the output holds a single value rather than values by
name, as `colmenaHive` does. The configuration declared under the name
`default` is then the output's value, and a configuration declared
under another name is refused there.

`bySystem` says the output is keyed by system first, as flakes key
`packages` and `formatter`. Each configuration is published under the
system of its evaluation, `<attrset>.<system>.<name>`, named by the
usual rules over its path without the systems on it. With `single`
too, the output holds the configuration named `default` at each
system, as `formatter.<system>` does. A configuration with no system,
one not evaluated per system, is refused in such an output.

`name` is for an integration whose configurations are known by a name
other than the name they are declared under. It takes the name the
configuration is passed up under and its manifest. It returns `value`,
the name to publish the configuration under, and optionally
`description`, a sentence describing how the name was formed. The
home-manager integration uses it to name a home declared inside a
NixOS configuration: the name of the home, `@`, and the name of the
NixOS configuration.

A structural or flake-parts configuration is built with no `exportsTo`
and is not published under a name. The configurations declared inside
it are published, with its segment on their paths.

The configuration holds configurations of any integration beneath
it: those its modules declare under
`caisson.<integration>.configurations` are its children, and
`caisson.exports`, which carries what they pass up, is its `exports`
output. What its modules define under `caisson.forChildren` is what
it registers for the configurations beneath it
(`lib.caisson-core.mkConfiguration`).

`frameworkModules` takes a class and its registry and returns the
framework module of the class, which every evaluation of the class
imports: caisson's core module for the class, read from the closure of
caisson, followed by `coreModules` of the registry. The core module
declares `caisson.manifest`, `caisson.<integration>.configurations`,
`caisson.<integration>.exported` and `caisson.exports`.

Structural, flake-parts, nixos and nixos-minimal configurations are
built with both.

#### `moduleImportsOf`

```
moduleImportsOf : str -> { lib, manifest } -> args -> registry -> listOf module
```

The selection of an evaluation over the registry of its class. It
takes the class, the view being evaluated and the arguments of the
configuration, and reads two of them:

- `moduleImports` replaces the default of the class. With none given,
  the selection is that default: every entry named `default`,
  followed by what the levels above the evaluation added with
  `caisson.forChildren.extraDefaultModuleImports`, those from the top
  first, each applied to the lib of the evaluation.
- `extraModuleImports` is appended to the selection, whichever it is.
  A configuration that adds a module with it keeps the default of its
  class.

Both are functions of the registry returning modules, and every
constructor of every integration takes both.

#### `pkgSetsAt`, `pkgSetOf`

```
pkgSetsAt : { context, what } -> manifest -> system -> attrsOf pkgs
pkgSetOf  : { context, what } -> manifest -> attrsOf pkgs -> pkgs
selection = attrsOf pkgs -> pkgs
```

How a configuration gets the package set it runs on. It is the same
for every integration whose configurations run on a package set.

A configuration selects its set when it is constructed, with the
`defaultPkgs` argument: a function of the package sets available where
the configuration is declared, by package config name, each at the
system of the evaluation.

```nix
lib.caisson.nixos.mkConfiguration {
  defaultPkgs = pkgSets: pkgSets.stable;
}
```

The function receives the available sets as an attribute set and
returns the one to run on, here the set of the package config named
`stable`.

A selection holds for the subtree: the configuration that makes it
and every configuration beneath it that selects none, through levels
of any integration. A configuration that selects none runs on what
the nearest configuration above it selected. A module of a
configuration selects for the configurations beneath it, and not for
the configuration itself, with the `caisson.forChildren.defaultPkgs`
option. Where no configuration from the top down selects, a configuration runs on the set named
`default`, and a composition that declares no `default` and selects
nothing is told so, with the sets it declares.

The modules of a configuration can also use any available set by
name, through the `pkgSets` argument.

`pkgSetsAt` gives the sets available to an evaluation: the package
configs its manifest holds, each projected to its set at the system.
`pkgSetOf` applies the selection in force at the manifest (`defaultPkgs`,
which `mkModuleConfiguration` records from the argument and
`lib.caisson-core` carries to everything beneath) to those sets.

The argument is on the nixos, nixos-minimal, home-manager,
home-manager-minimal, flake-parts, structural and colmena
constructors. In a
flake it selects the `pkgs` of `perSystem`. A structural configuration
runs on no package set and selects for what is beneath it.

#### `entriesOf`, `publish`, `displayName`, `topValue`

```
entriesOf   : attrsOf (attrsOf finalized) -> listOf entry
publish     : listOf entry -> attrsOf (attrsOf value)
entry       = { path; manifest; attrset; value; description ?; }
displayName : listOf str -> str
topValue    : attrsOf manifest -> value | attrsOf value
```

How the configurations in a tree are named and published.

`entriesOf` gives the entries a configuration passes up: an entry for
each configuration declared inside it, directly or deeper, whose
manifest records `exportsTo`. Its argument is what each integration's
`exported` selected, by integration and then name.

The configuration that passes a child up makes the entry, because it
knows the name the child is declared under. The entry holds the
output attribute set and the value the manifest records, and the path
from that configuration to the child. The last segment of the path is
the name `exportsTo.name` returns, when the integration defines
`name`. A name that contains `/` is refused. The structural,
flake-parts and system levels on the way are segments of the path.
caisson's core module defines `caisson.exports.configurations` with
`entriesOf`.

`publish` is what a top does with the entries. It groups them by the
output attribute set named in each entry, computes the names in each
group from `lib.caisson-core.elide` over the paths, and returns the
values by attribute set and name. Entries that still share a name are
refused, with their paths. The flake-parts top writes the
result into the flake outputs, and the structural top into what it
returns.

`displayName` writes the kept segments out as a name: in path order,
separated by `/`. Every name caisson publishes is written by it.

`topValue` is what a tool reads from a top that is a configuration
evaluated per system, given its evaluations by system. They are
named as anything published is, and the name of the top, which the
file that returns it stands for, is left out of each: a single
evaluation is its value, and several are the values by system.

#### `mkIntegration`

```
mkIntegration :
  { name       : string            # the namespace, lib.caisson.<name>
  , class      : string            # the module class this integration owns
  , mkConfiguration                  : pattern -> result  # the entry point, a pattern function
  , mkConfigurationWithEcosystemArgs : pattern -> result  # the same pattern plus ecosystemArgs
  , top        ? null : manifest -> value  # what a configuration with no parent returns
  , extra      ? { } : attrs       # further members of the namespace
  } -> { namespace : attrs }
```

`mkIntegration` builds an integration that owns a module class from a
declaration. The result has the part `namespace`.

`namespace` is the value to publish as `lib.caisson.<name>`. It holds
`mkConfiguration`, `mkConfigurationWithEcosystemArgs`, `mkModule`,
`configurationsModule`, `mkTopConfiguration` when the declaration
gives `top`, and everything in `extra`. The entry points come from the declaration,
written as pattern functions whose body is
`mkEvaluation { compose, evaluate }` applied to the admitted
arguments. The pattern of `mkConfiguration` names the arguments
every entry point takes (`ecosystemSrc`, `pkgSets`, `configModule`,
`moduleImports`, `specialArgs`) and the few of its target, with the
required arguments bare and the rest defaulting to `null`; a comment
beside each argument says what it is, and the `at` line of Nix's
argument error points at that block. The twin's pattern repeats the
entry point's plus `ecosystemArgs`, merged over the composed call
before evaluating, so the caller can set or replace anything the
evaluator takes. `mkModule` is `lib.caisson-core.mkModule` bound to
`class`. `extra` is for the members a declaration cannot generate,
such as a variant entry point, an adapter, or the composition an alt
over this class builds on.

`configurationsModule` is the module that lets a configuration hold
configurations of this integration beneath it. It declares
`caisson.<name>.configurations` and `caisson.<name>.exported`. An
integration written outside caisson registers a module that imports
it where its configurations may be declared. The integrations of
caisson have their options declared by the core module of caisson,
through `configurationsModuleFor`, so importing the
`configurationsModule` of one of them into a caisson evaluation
declares its options a second time.

`top` is what a configuration of the integration returns when it has
no parent, as a function of its finalized manifest. When the
declaration gives it, the namespace has `mkTopConfiguration`, which
takes the arguments of `mkConfiguration`, finalizes the configuration
with no parent, and applies `top` to the manifest. Its argument
pattern is the pattern of `mkConfiguration`.

The integration's `compose` receives the admitted arguments and
returns an attribute set. That set must hold `ecosystemArgs`, the
arguments of the evaluator's call as the integration composed them; it
may hold anything else `evaluate` needs, such as the resolved source.
`evaluate` receives that set and the call arguments to use, and
returns the evaluation.

The constructor returns values rather than an overlay output, because
the attribute names an overlay produces must not depend on `final`.
The overlay file writes the key itself:

```nix
overlay = final: prev:
  let
    integration = final.caisson.integrations.mkIntegration { ... };
  in
  {
    caisson = (prev.caisson or { }) // {
      nixos = integration.namespace;
    };
  };
```

#### `mkAltIntegration`

```
mkAltIntegration :
  { over     : attrs               # the integration that owns the class, e.g. final.caisson.nixos
  , mkConfiguration                  : pattern -> result
  , mkConfigurationWithEcosystemArgs : pattern -> result
  , top      ? null : manifest -> value  # as for mkIntegration
  , extra    ? { } : attrs
  } -> attrs                       # the value of lib.caisson.<name>
```

`mkAltIntegration` builds an integration that evaluates a class
another integration owns. `over` is that owning integration, reached
through the lib. The result is the value to publish as
`lib.caisson.<name>`: the entry points of the declaration, pattern
functions as for an owner, `mkTopConfiguration` when the declaration
gives `top`, and `extra`. It has no `mkModule`, because modules of the
class are registered through the owner, and no
`configurationsModule`, because its configurations are configurations
of the owner. The composition its entry points evaluate over is expected
to build on the composition the owner publishes, so that the evaluators
cannot produce different configurations from the same arguments;
`caisson.nixos-minimal` composes through `caisson.nixos.compose` and
`caisson.home-manager-minimal` through
`caisson.home-manager.configuration`, which builds on
`caisson.home-manager.compose`.

Every integration caisson ships is declared with these
constructors: `mkIntegration` for the owners of a class (nixos,
flake-parts, structural, home-manager, colmena, terranix,
system-manager) and `mkAltIntegration` for `caisson.nixos-minimal`
and `caisson.home-manager-minimal`. Each overlay file holds the
composition, the evaluator step, the patterns and the extras of
its integration, and nothing else.

### `eval-weight`

- **Source:** `lib-overlays/tooling/eval-weight/`

The evaluation-cost measurement harness: `eval-weight.mkCheck` builds a
check derivation that measures eval scenarios in a sandbox and gates
deterministic metrics against a committed baseline. Documented in
[Evaluation weight](../eval-weight.md).

### `mkMemoizedDerivationRead`

- **Source:** `lib-overlays/tooling/mk-memoized-derivation-read.nix`

Builds memoized derivation-content readers; see the source header.

## Integration namespaces

Each integration is a library overlay exported by this flake
(`libOverlays.<ecosystem>`). Composing an integration contributes its
`lib.caisson.<ecosystem>` namespace, documented below (the flake-parts
integration also contributes the `lib.flake-parts` mirror of
the flake-parts library, instantiated over the composed lib). Each
entry point takes its ecosystem as an `ecosystemSrc` argument, and
every ecosystem, flake-parts included, is resolved from the
composition of the consumer.

An adapter's ecosystem source resolves in layers: the explicit
`ecosystemSrc` argument first, then the composition's declared
`defaultEcosystemSrc.<name>` (an mkLib argument, carried by the
manifest), then the source named exactly `<name>` in the `sources`
passed to mkLib. The name is the integration's ecosystem, and one
ecosystem may serve several integrations: `nixpkgs` for the nixos,
nixos-minimal and nixpkgs integrations, `colmena` for the
caisson-colmena and colmena integrations, `disko` for the caisson-disko
and disko integrations, `nix-darwin` for the darwin integration, then
`home-manager`, `hjem`, `terranix`, `system-manager` and `flake-parts` for the
integration of the same name
(the table in
[Ecosystem sources](../concepts/ecosystem-sources.md)). A full
miss throws at the adapter, naming those places; a composition
built without mkLib (no manifest) accepts only the explicit argument.
Common conventions:

- Every integration exports `mkConfiguration` (evaluate the target's
  module system with the selected class modules) and, where it has a
  module class, `mkModule`, the form a tree registers that
  class's modules with (`caisson-core.mkModule` bound to the class).
  Target-specific variants and helpers sit beside them under the same
  namespace.
- `configModule`: the top-level module of the configuration, always a
  single module (compose several with `imports`); the framework's
  selected class modules are applied beside it.
- `specialArgs`: extra module arguments; the same name on every entry
  point, translated to the evaluator's spelling where it differs
  (home-manager's `extraSpecialArgs`, terranix's `extraArgs`).
- `defaultPkgs` is accepted by the nixos, nixos-minimal, darwin, hjem,
  home-manager, home-manager-minimal, terranix, flake-parts, structural,
  caisson-colmena, colmena, caisson-disko and disko entry points. It
  selects the package set the configuration runs on from the package
  configs the composition declares (see
  `caisson.integrations.pkgSetOf`). In a configuration evaluated at a
  system, the modules get the package sets by config name as the
  `pkgSets` special argument.
- `pkgSets`: on the colmena and disko entry points, an attrset of
  package sets passed through as the `pkgSets` special argument, where
  `pkgSets.pkgs` is the package set of `colmena eval`. flake-parts and
  structural forward it to their modules.
- The signature is the whole surface. An entry point takes exactly
  the arguments listed for it and composes the evaluator's call from
  them; nothing else is forwarded, and an unknown or missing argument
  is Nix's function-argument error, raised at the call site and
  pointing at the entry point's pattern, whose comments name the
  caisson argument to use where such an argument exists. That
  keeps an evaluator argument from being silently overwritten
  (`modules`), silently dropped (anything the minimal evaluator does
  not take), or surfacing as a conflict inside the evaluator
  (`pkgs` beside the framework's `nixpkgs.pkgs`).
- The full surface of the evaluator is reachable, deliberately, through
  the `mkConfigurationWithEcosystemArgs` twin of each entry point. It takes the same
  arguments plus `ecosystemArgs`, an attrset merged over the composed
  evaluator call verbatim, last: anything the evaluator accepts can
  be set or replaced there, including what caisson composed
  (`modules`, `specialArgs`, the package set). The name is the
  contract: from there on the evaluator's semantics are the caller's
  to know.
- `moduleImports`: a selection function over the corresponding class
  registry (`lib.caisson.modules.<class>`), returning the list
  of modules to apply; the default is the default default, every
  entry named `default` (`default`, `<project>/default`). The
  framework module, every entry named `core`, applies before the
  selection whatever it is. The list shape matches
  `libOverlayImports`; for order-sensitive list-typed options, prefer
  `mkOrder` over selection position.
- Framework-provided special arguments compose first; the caller's
  win on conflict.

### `caisson.structural` (module class `structural`)

- **Source:** `lib-overlays/structural/default.nix`

The empty integration: it wraps no ecosystem, and its class carries
nothing but caisson's core module: the manifest, the configurations
declared beneath, the registry selectors and `caisson.exports`. A
structural configuration is the top of a repository whose point is
what it exports (the `default.nix` of caisson is such a top), and a
layer at any depth, declared beneath another configuration under
`caisson.structural.configurations`.

- `mkModule : freeformModule -> module`: the registration form for
  structural modules.
- `mkConfiguration`:

```
mkConfiguration :
  { configModule  ? (the configuration registered under the name)
                  : module                                  # structural class
  , moduleImports ? (every entry named default)
                  : attrsOf module -> listOf module          # selection from the structural class registry
  , specialArgs   ? { }
  , pkgSets       ? null : attrs                            # the pkgSets special argument
  } -> configuration
```

Returns a configuration, a function of `{ name, parent }`, built with
`lib.caisson-core.mkConfiguration`. The parent that declares it under
`caisson.structural.configurations.<name>` finalizes it, and
`mkTopConfiguration` finalizes it at a top. Nothing is evaluated
until the manifest is read.

The evaluation is the framework module (every `core` of the class,
the `core` of caisson, read through the integration's closure), the
selected structural modules and the config module, with `evalModules`
over the lib of the view being evaluated. When `configModule` is
absent, the config module is the configuration registered under the
configuration's name, `lib.caisson.configs.structural.<name>`,
and there is none when nothing is registered under it. The manifest's
`value` is the evaluation as `evalModules` returned it (`config`,
`options`); `outputs.exports` is `caisson.exports`, the `lib`,
`libOverlays`, `modules` and `pkgOverlays` the selectors chose; and
`children` holds the configurations declared beneath it. The
integration wraps no ecosystem, so the signature has no `ecosystemSrc`.

- `mkConfigurations`: a configuration for every configuration
  registered in the class, each as `mkConfiguration` builds it without
  `configModule`.
- `mkConfigurationWithEcosystemArgs`: the twin; `ecosystemArgs` is
  merged over the `evalModules` call (`class`, `modules`,
  `specialArgs`).
- `mkTopConfiguration`: the same arguments. It finalizes the
  configuration with `lib.caisson-core.finalizeTop` and returns
  `outputs.exports` with the configuration's manifest beside it as
  `caisson.manifest`, which is what `default.nix` returns for a reader
  that indexes attributes of the file's value.

### `caisson.flake-parts` (module class `flake`)

- **Source:** `lib-overlays/flake-parts/default.nix`
- `mkModule : freeformModule -> module`: the registration form for
  flake-parts modules (`caisson-core.mkModule` bound to the `flake`
  class).
- `mkConfiguration`:

```
mkConfiguration :
  { configModule  ? (the configuration registered under the name)
                  : module                                  # flake class
  , pkgSets       ? null                                    # the `pkgSets` special argument
  , ecosystemSrc  ? null                                    # the flake-parts source
  , moduleImports ? (every entry named default)
                  : attrsOf module -> listOf module          # selection from the flake class registry
  , specialArgs   ? { }                                     # beside `lib`, the composed library
  } -> configuration
```

  Returns a configuration, a function of `{ name, parent }`, built
  with `lib.caisson-core.mkConfiguration`. A parent that declares it
  under `caisson.flake-parts.configurations.<name>` finalizes it, and
  `mkTopConfiguration` finalizes it at a top. The evaluator's call is
  flake-parts' `evalFlakeModule` over the lib of the view being
  evaluated: the manifest's `value` is the evaluation (`config`,
  `options`), `outputs.flake` is what flake-parts' `mkFlake` returns
  from it, `outputs.exports` is `caisson.exports`, and `children`
  holds the configurations declared beneath it. When `configModule` is
  absent, the config module is the configuration registered under the
  configuration's name, `lib.caisson.configs.flake.<name>`.
  flake-parts' `inputs` are the manifest's pinned `sources`, and the
  integration ties `self` the way Nix does for a flake: the
  evaluation's outputs with the root's source info (out path,
  revision, last-modified) beside them and `self.inputs` the sources,
  so flake-parts modules receive `self`, `self'` and `inputs` as they
  would under Nix's flake evaluation. `moduleImports` selects over
  the `flake` class of `lib.caisson.modules`, the same registry
  every adapter selects from, so modules arriving by local
  registration, overlay contribution, or consumed project are all
  selectable. flake-parts itself resolves like every ecosystem, from
  `ecosystemSrc`, `defaultEcosystemSrc.flake-parts` or the pinned
  source named `flake-parts`, and is instantiated over the composed
  library. The name of the configuration sets flake-parts'
  `moduleLocation`, so exported modules deduplicate across revisions.
- `mkTopConfiguration`: the same arguments. It finalizes the
  configuration with `lib.caisson-core.finalizeTop`, under the name
  the composition declares on `mkLib`, and returns its flake outputs
  (`outputs.flake`). It is what a `flake.nix` returns from `outputs`,
  and what a flakeless top that keeps flake-parts returns from
  `default.nix`.
- `mkConfigurations`: a configuration for every configuration
  registered in the class, each as `mkConfiguration` builds it without
  `configModule`.
- `types.libOverlay`: a module-system option type for built library
  overlays. Its `check` verifies the structure recursively: an
  attrset with an `overlay` function and a (possibly absent)
  `imports` list whose entries are themselves valid `libOverlay`s.
  Used by options that carry overlays, such as
  `caisson.libOverlays.exported`.
- `types.manifest`: a structural option type for the caisson-core
  lib manifest (`{ inputs, modules, libOverlays, ecosystems, projects,
  systems }`). The export-side check: the core flake-parts module
  reads the manifest of the evaluation
  through an option of this type before projecting the
  exports and the `flake.modules` output.

### `caisson.nixos` (module class `nixos`)

- **Source:** `lib-overlays/nixos/default.nix`
- `mkModule : freeformModule -> module`: class-bound `mkModule`.
- `mkConfiguration`:

```
mkConfiguration :
  { configModule  ? (the configuration registered under the name)
                  : module                                  # nixos class
  , ecosystemSrc  ? null                                    # the nixpkgs source tree
  , moduleImports ? (every entry named default)
                  : attrsOf module -> listOf module          # selection from the nixos class registry
  , specialArgs   ? { }
  } -> configuration
```

  Returns a configuration, a function of `{ name, parent }`, built
  with `lib.caisson-core.mkConfiguration`. A parent that declares it
  under `caisson.nixos.configurations.<name>` finalizes it, and
  `mkTopConfiguration` finalizes it at a top. The evaluation is
  `<ecosystemSrc>/nixos/lib/eval-config.nix` (a nixpkgs source tree)
  over the selected class modules and the config module. When
  `configModule` is absent, the config module is the configuration
  registered under the configuration's name,
  `lib.caisson.configs.nixos.<name>`.

  A NixOS configuration is evaluated per system, so the integration
  passes `perSystem`: a declared configuration is an evaluation for
  every system in force where it is declared (`systems` on `mkLib`),
  each under its name beneath its system in the tree. There are as
  many as there are systems, also for a single system, and none where
  no system is in force. An evaluation's `value` is the evaluated
  NixOS configuration, and its `outputs` are `toplevel`, `vm`,
  `vmWithBootLoader` and `images`, each a reference into
  `config.system.build`, and `exports`, what the configuration passes
  up to its parent.

  A module of the configuration declares configurations beneath it
  under `caisson.<integration>.configurations`. They see the
  evaluation as `nearest.nixos`.

  The package set comes from the composition, through the manifest.
  An evaluation runs on the set the `defaultPkgs` argument selects
  from the package sets available at the system of the evaluation
  (see `caisson.integrations.pkgSetOf`), defined as `nixpkgs.pkgs`. A
  configuration that passes none runs on what the nearest
  configuration above it selected, and on the set named `default`
  where none above selects. The modules can also use any set at that
  system by config name, through the `pkgSets` special argument. A
  module reads its name as
  `lib.caisson-core.evalManifest.name` and its system as
  `lib.caisson-core.evalManifest.system`.

  A NixOS configuration records `exportsTo` as `nixosConfigurations`,
  the value being the evaluated configuration: a flake-parts or
  structural top
  publishes the NixOS configurations declared beneath it there, under
  names from their paths.
- `mkTopConfiguration`: the same arguments. It finalizes the
  configuration with `lib.caisson-core.finalizeTop` and returns what a
  tool reads (`caisson.integrations.topValue`): the evaluated NixOS
  configuration where there is a single evaluation, which is what
  `nixos-rebuild --file` reads and what a test evaluates, and the
  evaluated configurations by system where there are several.
- `mkConfigurationFull`: as `mkConfiguration`, additionally passing nixpkgs'
  `module-list.nix` as `baseModules`.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`
  (see the conventions above); eval-config's `baseModules` is among
  the arguments reachable that way.
- `mkConfigurations`: a configuration for every configuration
  registered in the class, each as `mkConfiguration` builds it without
  `configModule`.
- `compose : { context?, nixpkgsModule? } -> { lib, manifest } -> args
  -> { modules, specialArgs, system, pkgSets, src }`: the composition
  of the class on the view being evaluated, from the caisson arguments
  (the framework and selected modules, the config module, the
  package-set module, the system, the resolved nixpkgs
  source), which every entry point here builds on and which an
  integration evaluating the `nixos` class with another evaluator
  reads, so two evaluators cannot express different machines from the
  same arguments. `nixpkgsModule = false` delivers the package set as
  the `pkgs` module argument for an evaluation without NixOS'
  nixpkgs module.

### `caisson.nixos-minimal` (module class `nixos`, owned by `caisson.nixos`)

- **Source:** `lib-overlays/nixos-minimal/default.nix`

A second integration over the `nixos` class: the minimal evaluator,
`evalModules` from `<ecosystemSrc>/nixos/lib`, with no NixOS base
modules, so the config module declares any options it uses and the
package set arrives as the `pkgs` module argument rather than through
`nixpkgs.pkgs`. It carries constructors only. The class, its
registration form (`caisson.nixos.mkModule`), its framework module and
its default default belong to the nixos integration, and the module
list comes from `caisson.nixos.compose`; composing it needs the nixos
integration composed beside it. In the tree its configurations are
nixos configurations: the manifest's `type` is `nixos`, a
configuration is declared under `caisson.nixos.configurations` and
published under `nixosConfigurations`, and it is `nearest.nixos` for
what is declared beneath it.

- `mkConfiguration : { configModule?, ecosystemSrc?, defaultPkgs?, moduleImports?, extraModuleImports?,
  specialArgs?, prefix? } -> configuration`: the arguments of
  `caisson.nixos.mkConfiguration` plus `prefix`, and the same result,
  a configuration whose manifest's `value` is the evaluation. The
  system and the package set come from the composition as they do
  there.
- `mkTopConfiguration`: the same arguments; finalizes the
  configuration at a top and returns the evaluation.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`
  (`prefix`, `modules`, `specialArgs`).

### `caisson.darwin` (module class `darwin`)

- **Source:** `lib-overlays/darwin/default.nix`

A darwin configuration is a macOS machine, evaluated with nix-darwin's
`eval-config.nix` over the composed library, the way nix-darwin's
`darwinSystem` calls it. caisson adds to the modules what
`darwinSystem` adds: `nixpkgs.source` from the nixpkgs the
composition declares, no check of `NIX_PATH`, and the revision of the
nix-darwin source in the version of the system.

Like a NixOS configuration, a darwin configuration is evaluated at
every system in force where it is declared, and runs on the package
set selected for it (`defaultPkgs`, else the set named `default`),
which caisson hands to `nixpkgs.pkgs`. `nixpkgs.hostPlatform`
defaults to the system of the evaluation. nix-darwin records no
nixpkgs revision for a package set it did not build itself, so the
system carries none, as with `darwinSystem` given `pkgs`.

A tree registers the machine as `configs/darwin/macbook-1/default.nix`
and declares it with
`caisson.darwin.configurations.macbook-1 = lib.caisson.darwin.mkConfiguration { };`,
which finds the configuration by its name. It is published as
`darwinConfigurations.macbook-1`, the evaluated configuration with
`system` beside `config`, which is what `darwin-rebuild` reads.
`darwin-rebuild` without `--flake '.#<name>'` looks the machine up by
its local host name, so we recommend declaring a machine under that
name.

Every configuration evaluated per system has an evaluation for each
system in force where it is declared. A tree whose `systems` hold both
Linux and darwin systems therefore declares its darwin machines under a
configuration that narrows the systems beneath it, such as a structural
configuration with `caisson.forChildren.systems = [ "aarch64-darwin" ];`,
and its NixOS machines under one narrowed to its Linux systems.

A darwin machine activates the homes and the hjem configurations
declared inside it, with the modules of
[`modules.darwin."caisson/default"`](#modulesdarwincaissondefault).
A home inside a darwin machine is published as `<user>@<machine>`, as a
home inside a NixOS machine is, and gets `osClass = "darwin"` and the
machine as `darwinConfig`, as home-manager's nix-darwin module gives
them.

caisson's tests evaluate a darwin machine on Linux and compare its
system with what `darwinSystem` builds from the same module and package
set. They also evaluate a machine with a home and a hjem configuration
inside it, and compare the manifest of the hjem configuration with the
manifest hjem's nix-darwin module makes. caisson's CI builds the systems
of both machines on a macOS runner. Activation on a running machine is
not tested.

- `mkModule : freeformModule -> module`: class-bound `mkModule` for
  darwin modules.
- `mkConfiguration : { configModule?, ecosystemSrc?, defaultPkgs?,
  moduleImports?, extraModuleImports?, specialArgs? } -> configuration`:
  the arguments of `caisson.nixos.mkConfiguration`. `configModule`
  defaults to the configuration registered under its name in
  `configs/darwin`. `ecosystemSrc` is the nix-darwin flake or source
  tree, resolved from the composition under the name `nix-darwin` when
  absent.
- `mkTopConfiguration`: the same arguments; finalizes the
  configuration at a top and returns the evaluation, or the evaluations
  by system where several systems are in force.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the call of `eval-config.nix` (`modules`, `specialArgs`).

### `caisson.home-manager` (module class `homeManager`)

- **Source:** `lib-overlays/home-manager/default.nix`
- `mkModule : freeformModule -> module`.
- `mkConfiguration : { configModule?, ecosystemSrc?, defaultPkgs?,
  moduleImports?, extraModuleImports?, specialArgs?, osConfig?, check? }
  -> configuration`

  `mkConfiguration` builds a home: a configuration evaluated with
  home-manager's evaluator, the modules under `<ecosystemSrc>/modules`.
  A home is declared under
  `caisson.home-manager.configurations.<name>` in a module of any
  configuration, or finalized as a top.
  `mkConfigurationWithEcosystemArgs` takes `ecosystemArgs` as well,
  which is how to pass home-manager's `lib` argument.

  A home is evaluated per system. A home declared inside a NixOS
  configuration is evaluated for the system of that configuration by
  default, and the NixOS configuration can list other systems with
  `caisson.forChildren.systems`. A home declared anywhere else is
  evaluated for each system the composition declares on `mkLib`,
  unless a configuration it is declared inside lists others the same
  way.

  `configModule` defaults to the configuration registered as
  `configs/homeManager/<name>`, where `<name>` is the name of the
  home. `home.username` defaults to the name the home is declared
  under, and a module of the home may set a different username.

  The home runs on the package set `defaultPkgs` selects (see
  `caisson.integrations.pkgSetOf`). A home constructed with no
  `defaultPkgs` and declared inside a NixOS configuration runs on the
  set of that NixOS configuration, unless the NixOS configuration sets
  `caisson.forChildren.defaultPkgs`. `pkgs` in the home is that set.
  The evaluation leaves out home-manager's nixpkgs module, as
  home-manager's NixOS module does under `useGlobalPkgs`, so
  `nixpkgs.config` and `nixpkgs.overlays` belong in the package
  config. The modules can also use any package set for that system by
  config name, through the `pkgSets` special argument.

  A home declared inside a NixOS configuration is given that machine.
  The integration hands the home the configuration of the machine as
  the module argument `osConfig`, and the class of the machine as
  `osClass`. These are the arguments home-manager's NixOS module
  passes to a home it embeds. The configuration is the childless
  evaluation of the NixOS configuration, which leaves out the
  configurations declared inside it, because the home is one of them.
  A home with no NixOS configuration above it gets `osConfig = null`,
  as a home evaluated by home-manager alone does. An `osConfig`
  passed to `mkConfiguration` takes the place of the configuration of
  the machine.

  Such a home also imports two home-manager modules by default, which
  the NixOS configuration adds. `nixos-parent` sets the options of
  the home that come from the machine. `nixos-source-marker` makes the
  home print a warning when it is activated on a machine it was not
  built for. The machine activates the home with the NixOS module
  `home-manager-activation`. See
  [`modules.nixos."caisson/default"`](#modulesnixoscaissondefault-moduleshomemanagercaissonnixos-parent).

  A home that passes `moduleImports` selects all of its modules
  itself. Such a home gets `modules."caisson/nixos-parent"` and
  `modules."caisson/nixos-source-marker"` only if its list names
  them. `extraModuleImports` adds
  to the default selection and keeps both.

  home-manager's legacy argument `nixosConfig` stays null. Its
  fontconfig module reads `nixosConfig.home-manager.useUserPackages`,
  an option that only home-manager's NixOS module declares, and
  caisson does not use that module.
- `mkTopConfiguration` takes the same arguments. It finalizes the home
  at a top and returns the evaluated home with its
  `activationPackage`, which is what the home-manager CLI reads.
- A top publishes homes as `homeConfigurations.<name>`. A home
  declared inside a NixOS configuration is published under the name
  the home is declared under, `@`, and the name the NixOS
  configuration is declared under. The home-manager CLI looks up
  `$USER@$(hostname)`, so that is the name it finds when the two
  names are the user and the hostname. A home with no NixOS
  configuration above it is published under its name.

### `caisson.hjem` (module class `hjem`)

- **Source:** `lib-overlays/hjem/default.nix`

A hjem configuration is the files and packages of one user, written
with the options of hjem's user module (`files`, `xdg.config.files`,
`packages`, `directory`). hjem evaluates a user only inside its NixOS
and nix-darwin modules, as an entry of `hjem.users`. caisson evaluates
the user module itself, with the arguments those modules pass: hjem's
library as `hjem-lib`, the name of the user as `name`, the package set
as `pkgs`, and the machine above the configuration as `osConfig`, null
when there is none.

A hjem configuration is evaluated at every system in force where it is
declared, and runs on the package set selected for it (`defaultPkgs`,
else the selection of the nearest configuration above, else the set
named `default`). `user` defaults to the name the configuration is
declared under, and `clobberFiles` defaults to false, as in hjem's NixOS
module.

A tree registers the user as `configs/hjem/alice/default.nix` and
declares it with
`caisson.hjem.configurations.alice = lib.caisson.hjem.mkConfiguration { };`,
which finds the configuration by its name. Its outputs are what hjem's
tools read:

| Output | Value |
| --- | --- |
| `manifest` | the version 3 manifest of the files of the user, as hjem's OS modules write it |
| `manifestFile` | that manifest as a JSON file, checked against hjem's schema with `cue vet` when it is built |
| `packages` | the `packages` of the user |
| `cli` | hjem's CLI, built from the hjem source the configuration is evaluated with |

A failed assertion of the user fails `manifest`, `manifestFile` and
`packages` with its message.

A top publishes the configuration as `hjemConfigurations.alice`, with
`manifest` and `packages`. `hjem standalone switch --flake .` reads
`hjemConfigurations."$USER"` from the flake in the current directory, so
it finds the configuration of the user running it when the two names
are the same; `--flake-attr` names another attribute. The value of a hjem
configuration that is a top has `manifest` and `packages` too, which is
what `hjem standalone switch --config` reads from a file.

**Inside a NixOS machine.** A NixOS configuration activates the hjem
configurations declared inside it with
[`caisson/hjem-activation`](#modulesnixoscaissonhjem-activation), and
gives each of them the hjem module
[`caisson/nixos-parent`](#moduleshjemcaissonnixos-parent), which sets
`directory` from the account of the user on the machine. Such a
configuration also imports hjem's `modules/nixos/systemd.nix` with the
`utils` and options of the machine, as a user that hjem's NixOS module
embeds does, so it can declare systemd user units under
`systemd.services` and the other unit types. hjem's NixOS module is not
used.

**Inside a darwin machine.** A darwin configuration applies the hjem
configurations declared inside it with the launchd agent of
[`caisson/hjem-activation`](#modulesdarwincaissonhjem-activation), and
gives each of them the hjem module `caisson/darwin-parent`, which sets
`directory` from the account of the user on the machine.

caisson's tests compare the manifest of a hjem configuration inside a
NixOS machine with the manifest hjem's NixOS module makes from the same
user module, and build its manifest file and the units that activate
it. Activation on a running machine is not tested.

- `mkModule : freeformModule -> module`: class-bound `mkModule` for
  hjem modules.
- `mkConfiguration : { configModule?, ecosystemSrc?, defaultPkgs?,
  moduleImports?, extraModuleImports?, specialArgs? } -> configuration`.
  `configModule` defaults to the configuration registered under its
  name in `configs/hjem`. `ecosystemSrc` is the hjem flake or source
  tree, resolved from the composition under the name `hjem` when
  absent.
- `mkTopConfiguration`: the same arguments; finalizes the configuration
  at a top and returns its value, or the values by system where several
  systems are in force.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the call of `evalModules` (`modules`, `specialArgs`).
- `manifestOf : hjemLib -> config -> manifest`: the manifest of an
  evaluated user, from hjem's library and the `config` of the user.

### `caisson.home-manager-minimal` (module class `homeManager`, owned by `caisson.home-manager`)

- **Source:** `lib-overlays/home-manager-minimal/default.nix`

A second integration over the `homeManager` class: home-manager's
minimal evaluation, the module list that omits what a standalone
activation needs, which home-manager selects with its `minimal` flag.
It carries constructors only. The class, its registration form
(`caisson.home-manager.mkModule`), its framework module and its
default default belong to the home-manager integration, and the
configuration it builds comes from `caisson.home-manager.configuration`;
composing it needs the home-manager integration composed beside it.

- `mkConfiguration` takes the arguments of
  `caisson.home-manager.mkConfiguration` and returns the same result.
  The configuration is a home: it is declared under
  `caisson.home-manager.configurations` and published under
  `homeConfigurations`.
- `mkTopConfiguration` takes the same arguments and returns the
  evaluated home.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`.

### `caisson.nixpkgs` (module class `nixpkgsConfig`)

- **Source:** `lib-overlays/nixpkgs/default.nix`

The nixpkgs integration builds package sets from package configs. A
package config is a module evaluation of the class nixpkgs evaluates
`pkgs/top-level/config.nix` under: nixpkgs' options (`allowUnfree`
and the rest) sit at the top level, as upstream declares them, and
caisson's sit under `caisson.nixpkgs`. Its module lives at
`configs/nixpkgsConfig/<name>/default.nix`, and further modules of
the class are registered under `modules/nixpkgsConfig/<name>`.

#### `mkConfiguration`

```
lib.caisson.nixpkgs.mkConfiguration :
  { configModule  ? null : module      # the config's module
  , moduleImports ? null : registry -> listOf module
  , ecosystemSrc  ? null : path        # the nixpkgs source tree
  } -> configuration
```

Declares a package config, in `mkLib`'s `pkgSets`. `configModule`
defaults to the configuration registered under the name the config is
declared under (`lib.caisson.configs.nixpkgsConfig.<name>`), and
a config with neither evaluates with no module of the tree.
`moduleImports` selects from the `nixpkgsConfig` module registry and
defaults to every entry named `default`. `ecosystemSrc` is the
nixpkgs tree, resolved from the composition's declarations when
absent (see [Ecosystem sources](../concepts/ecosystem-sources.md)).

It returns a configuration: a function `{ name, parent }: manifest`
that `mkLib` calls. The manifest has `type = "nixpkgs"`, the config's
`name`, its `systems`, the evaluation as `value`, the config handed
to nixpkgs as `config`, and one package set per system under
`children.nixpkgs.<system>`, whose `value` is the set.

These options under `caisson.nixpkgs` declare the sets:

- `caisson.nixpkgs.systems`: the systems to build a set for. It
  defaults to the `systems` declared on `mkLib`; a config with no
  systems in force is an error saying to declare them.
- `caisson.nixpkgs.overlays`: the package overlay registry entries the
  sets apply, each after the entries it imports and each key once. It
  defaults to every entry named `default` or `<project>/default`, and
  a definition replaces that default.
- `caisson.nixpkgs.extraOverlays`: entries applied in addition to
  `overlays`, whichever selection that is. A config that adds an entry
  with it keeps the default:
  `caisson.nixpkgs.extraOverlays = [ lib.caisson.pkgOverlays.<name> ];`.

caisson instantiates the sets itself, without going through
`pkgs/top-level/default.nix`: it boots the stdenv stages and
`stage.nix` on the composed library with `pkgsManifest` filled in, so
`pkgs.lib` is the library the config is declared under and
`pkgs.lib.caisson-core.pkgsManifest` is the set's manifest. The
derivations are those `import nixpkgs { system; config; overlays; }`
produces. `mkConfigurationWithEcosystemArgs` takes `ecosystemArgs` as
well, merged into every instantiation (`crossSystem`,
`crossOverlays`, `stdenvStages`).

#### `mkConfigurations`

```
lib.caisson.nixpkgs.mkConfigurations :
  { moduleImports ? null; ecosystemSrc ? null; } -> attrsOf configuration
```

Declares a package config for every configuration registered in
`configs/nixpkgsConfig`, by its name, each as `mkConfiguration`
builds it without `configModule`. The arguments apply to all of them.
`pkgSets = lib: lib.caisson.nixpkgs.mkConfigurations { };` is the
usual declaration; a tree that wants only some configs, or a config that
differs, declares them with `mkConfiguration`. `mkIntegration`
generates this function for every integration whose
`mkConfiguration` finds its module by name.

#### `mkTopPkgSet`

```
lib.caisson.nixpkgs.mkTopPkgSet : manifest -> pkgs
```

Turns a package config into what the legacy readers take, for a
repository that is a package set. Its `default.nix` ends with
`lib.caisson.nixpkgs.mkTopPkgSet lib.caisson.nixpkgs.pkgSets.default`.

The result is the set for the current system, with a `__functor`
that takes the legacy arguments and returns the set for the system
asked for. Nix auto-calls a lambda and not a functor, so
`nix-build -A hello` indexes the set, and
`import ./. { system = "aarch64-linux"; }` calls it.

- `system` defaults to `builtins.currentSystem`. Pure evaluation has
  none: the result is then the functor alone, and a call has to pass
  `system`. A system the config builds no set for is refused, with
  the systems it does build.
- `overlays` are applied over the config's selection, through the
  set's `appendOverlays`.
- `config` must be empty. The nixpkgs config is the package config,
  declared in `configs/nixpkgsConfig/<name>`.

The set carries its manifest in `pkgs.lib.caisson-core.pkgsManifest`,
whose parent is the config, so nothing else is added to it.

#### `pkgSets`

```
lib.caisson.nixpkgs.pkgSets : attrsOf manifest     # the package configs, by name
```

`pkgSets` is a view of the manifest. It holds the package configs
`mkLib` recorded, by name.

#### Overlay constructors and types

- `mkScope : pkgs -> (callPackage -> attrs) -> scope`: a
  `makeScope` wrapper handing the scope function its `callPackage`.
- `mkPackagesOverlay : pkgsFn -> name -> overlayFn`: turns a scope
  function (or path; optionally context-taking
  `{ callPackage, inputs, lib }`) into an overlay that merges the
  scope under attribute `name`.
- `mkPolyfillOverlay : overlayFn -> name -> overlayFn`: wraps an
  overlay (or path; optionally context-taking) for registration
  alongside package overlays; the name is ignored.
- `types.nixpkgsOverlay`, `types.nixpkgs`: option types.

### `caisson.caisson-colmena` (module class `caisson-colmena`)

- **Source:** `lib-overlays/caisson-colmena/default.nix`

`caisson-colmena` is the native colmena integration, and the one we
recommend for writing new configurations. Its machines are NixOS
configurations declared like any other, so they share modules through
the registry and through structural groups, and they take their
package sets from caisson's package configs. The integration named
`colmena`, below, exists for porting a hive written for colmena as it
is.

A colmena configuration is a module of the `caisson-colmena` class, a
class caisson defines itself, since colmena's hive format is not a
module class; the class carries the `caisson-` prefix because the bare
name is not caisson's to claim. The integration is not compatible with
colmena's hive modules (`makeHive`, `defaults`, `meta.nixpkgs`). The
word hive names only the output colmena's CLI reads.

A colmena configuration declares `meta` (`name`, `description`,
`machinesFile`, `allowApplyAll`), and the machines colmena deploys as
NixOS configurations, under `caisson.nixos.configurations.<name>`, the
way any configuration declares them:

```nix
caisson.caisson-colmena.configurations.default = lib.caisson.caisson-colmena.mkConfiguration {
  configModule = { lib, ... }: {
    meta.allowApplyAll = false;
    caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
      configModule = { deployment.targetHost = "nas-1.lan"; /* ... */ };
    };
  };
};
```

The nodes are the NixOS configurations the colmena configuration passes
up, each under the name it is published under. The default module of
the class adds caisson's NixOS module `colmena-deployment` to the
default selection of the NixOS configurations declared inside it. That
module declares colmena's `deployment` options and imports colmena's
modules for assertions and keys, from the colmena source the
composition declares or pins under the name `colmena`. A NixOS
configuration that passes `moduleImports` lists the module itself, as
`caisson/colmena-deployment` in a flake that lists caisson in
`projects`.

The integration reads `deployment` back from each node and builds the
hive: `__schema`, `nodes`, `toplevel`, `deploymentConfig`,
`evalSelected` and the other attributes colmena's CLI reads. A
`deployment.targetHost` the node leaves at `null` is the node's name in
the hive. The hive refuses a node that declares no `deployment`
options, and a node whose name colmena's `--on` filter could never
select: a name containing a comma, starting with `@`, or empty. Names
colmena's own hive format reserves (`meta`, `defaults`, `network`) are
ordinary names. The schema version is asserted against the `makeHive`
of the colmena source, so a colmena revision that moves it fails at
evaluation.

A colmena configuration is published as `colmenaHive`, an output that
holds a single value, so the colmena configuration declared under the
name `default` fills it, and another name is refused there. Its nodes
are published as `nixosConfigurations.<name>` as well, from the same
evaluation, so `nixos-rebuild` and `colmena apply` build the same
machine.

- `mkModule : freeformModule -> module`: class-bound `mkModule` for
  colmena modules.
- `mkConfiguration : { configModule?, pkgSets?, defaultPkgs?,
  ecosystemSrc?, moduleImports?, extraModuleImports?, specialArgs? }`:
  a colmena configuration, a function of `{ name, parent }`, finalized
  by the configuration that declares it under
  `caisson.caisson-colmena.configurations.<name>`. `configModule` defaults to
  the configuration registered under its name in `configs/caisson-colmena`.
  `ecosystemSrc` is the colmena flake, resolved from the composition
  when absent. `pkgSets.pkgs` serves `colmena eval` (`introspect`) and
  nothing else.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the `evalModules` call (`class`, `modules`,
  `specialArgs`).
- `metaOptions`, `hiveOf`, `exportsTo`, `ecosystemSrcOf`: the `meta`
  options, the hive built from an evaluated colmena configuration, how
  a colmena configuration is published, and the resolution of the
  colmena source. The upstream-compatible `colmena` integration builds
  on them.

### `caisson.colmena` (module class `colmena`)

- **Source:** `lib-overlays/colmena/default.nix`

`colmena` is the upstream-compatible colmena integration. It is there
so that a hive written for colmena can move to caisson as it is, and so
that modules written for colmena's evaluator can be used with caisson:
a project with many of them can port without rewriting them. For a new
configuration, we recommend `caisson-colmena`, which works like the
other caisson integrations. It gives up compatibility with Nix code
written for colmena to do that: a hive file or a module written for
colmena's evaluator does not work with it. It keeps compatibility with
colmena's CLI, which deploys from `colmenaHive` either way.

It takes a hive in the format colmena reads: `meta` (or `network`, its
older name), `defaults`, and a module or list of modules per node. Each node
becomes a caisson NixOS configuration declared beneath the colmena
configuration, and is published as `nixosConfigurations.<node>`:

```nix
caisson.colmena.configurations.default = lib.caisson.colmena.mkConfiguration {
  hive = {
    meta.nixpkgs = pkgSets.default;
    defaults = { name, ... }: { networking.hostName = name; };
    nas-1 = ./hosts/nas-1.nix;
  };
};
```

A node is built as colmena builds it: from colmena's deployment,
assertion and key modules, the `defaults` of the hive and the modules
of the node, with the special arguments `name`, `nodes`,
`meta.specialArgs` and `meta.nodeSpecialArgs.<node>`. With `name`
given, `deployment.targetHost` defaults to the name of the node, as in
colmena. `nodes` holds every node evaluated again with type checking
off, as colmena provides it, made only when a module reads it.

A node runs on `meta.nodeNixpkgs.<node>`, else `meta.nixpkgs`, else the
package set caisson selects for it. Those values are package sets
already built, such as caisson's package sets; a path to nixpkgs, a
nixpkgs function or an uninitialized flake input is refused. The set is
handed to NixOS whole, so its overlays and its config are those it was
built with. As a caisson NixOS configuration, a node also gets the
framework modules and the default selection of caisson's NixOS
integration.

For a hive with nothing caisson adds to it, each node builds the same
system as colmena builds from the same hive. The colmena configuration
builds its hive from the NixOS configurations it passes up, as
caisson-colmena does, and is published as `colmenaHive`.

- `mkModule : freeformModule -> module`: class-bound `mkModule` for
  modules of the colmena class.
- `mkConfiguration : { hive, pkgSets?, defaultPkgs?, ecosystemSrc?,
  moduleImports?, extraModuleImports?, specialArgs? }`: a colmena
  configuration, a function of `{ name, parent }`, finalized by the
  configuration that declares it under
  `caisson.colmena.configurations.<name>`. `hive` is an attribute set,
  or a function returning one, as colmena accepts. `defaultPkgs`
  selects the package set of a node the hive names none for.
  `pkgSets.pkgs` serves `colmena eval`, else `meta.nixpkgs`.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the `evalModules` call of the colmena configuration.

### `caisson.caisson-disko` (module class `caisson-disko`)

- **Source:** `lib-overlays/caisson-disko/default.nix`

`caisson-disko` is the native disko integration, and the one we
recommend for new configurations. A disko configuration is a disk
layout, and the NixOS configurations installed onto it are declared
inside it. Those NixOS configurations get the file systems the layout
produces and nothing of disko itself, so the scripts that format and
destroy the disks are not reachable from a machine. The integration
named `disko`, below, gives its machines disko's own NixOS module
instead.

A disko configuration is a module of the `caisson-disko` class. It sets
`disko.devices`, disko's grammar for the disks, typed with disko's type
library from the disko source the composition declares or pins under
the name `disko`. It declares the NixOS configurations installed onto
the layout under `caisson.nixos.configurations.<name>`, the way any
configuration declares them, and it may declare none, as for a data
array:

A tree registers the layout as `configs/caisson-disko/nas-1/default.nix`:

```nix
{ ... }:
{ lib, ... }:
{
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S5GXNX0T123456";
    type = "disk";
    content = { type = "gpt"; partitions = { /* ... */ }; };
  };
  # The NixOS configuration registered as `configs/nixos/nas-1`.
  caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration { };
}
```

and declares it where it belongs, here at the top of its flake.
`mkConfiguration` without `configModule` takes the configuration
registered under the name it is declared under:

```nix
caisson.caisson-disko.configurations.nas-1 = lib.caisson.caisson-disko.mkConfiguration { };
```

The layout is evaluated with caisson's own `evalModules` over
`disko.devices`, the framework modules, the selection and the
configuration's module. The class also declares `assertions`, a list of
`{ assertion, message }` as in NixOS. A module of the class refuses a
layout with an assertion that is false, and every output of the layout
then fails with the messages of those assertions.

The outputs are the layout product:

- `serializableLayout`: the device tree as data, with disko's internal
  attributes and functions left out.
- `layoutHash`: the sha256 of `serializableLayout` as JSON, the
  identity of the disks the layout describes.
- `nixosConfig`: the NixOS settings the devices produce, `fileSystems`,
  `boot` and `swapDevices`, each a definition for a NixOS option.
- `meta`: disko's record of which device depends on which.
- `scripts`: a function of a package set returning the scripts disko
  makes from the layout: `format`, `mount`, `unmount`, `destroy`,
  `formatMount`, `destroyFormatMount`, and each of them without its
  dependencies (`formatNoDeps` and so on).
- `packages`: a function of a package set returning the packages the
  scripts run.
- `rootMountPoint`: the directory the mount script mounts the layout
  under.

The default module of the class adds caisson's NixOS module
`caisson-disko-layout` to the default selection of the NixOS
configurations declared inside the layout. That module defines
`fileSystems`, `boot` and `swapDevices` from the layout's
`nixosConfig`, at default priority, and refuses a layout that produces
settings under any other key. A NixOS configuration that passes
`moduleImports` lists the module itself, as
`caisson/caisson-disko-layout` in a flake that lists caisson in
`projects`. A module of a NixOS configuration that needs more of its
layout reads it as `lib.caisson-core.evalManifest.nearest.caisson-disko`.

A layout passes up its NixOS configurations under the names they are
declared with. So the machine declared as `nas-1` inside the layout
`nas-1` is published as `nixosConfigurations.nas-1`, and is the node
`nas-1` of a colmena configuration that declares the layout.

Where a layout holds one machine, we recommend naming the machine after
the layout. The layout's module declares it under its own name, read
from the manifest, and caisson's default NixOS module names the host
after the name the machine is declared under:

```nix
{ lib, ... }: {
  caisson.nixos.configurations.${lib.caisson-core.evalManifest.name} =
    lib.caisson.nixos.mkConfiguration { };
}
```

`mkConfiguration` without `configModule` takes the NixOS configuration
registered under the name the machine is declared under. So the layout
`nas-1` holds the machine registered as `configs/nixos/nas-1`, and
publishes it as `nixosConfigurations.nas-1`, whose host name is `nas-1`
unless its modules set another.

A disko configuration is published as `diskoConfigurations.<name>`, in
the form disko's CLI reads: `{ disko.devices = <serializableLayout>; }`.
disko's CLI evaluates it again with its own evaluator, so
`disko --mode format --flake '.#nas-1'` formats the disks the layout
describes.

- `mkModule : freeformModule -> module`: class-bound `mkModule` for
  modules of the caisson-disko class.
- `mkConfiguration : { configModule?, pkgSets?, defaultPkgs?,
  ecosystemSrc?, moduleImports?, extraModuleImports?, specialArgs?,
  rootMountPoint?, checked? }`: a disko configuration, a function of
  `{ name, parent }`, finalized by the configuration that declares it
  under `caisson.caisson-disko.configurations.<name>`. `configModule`
  defaults to the configuration registered under its name in
  `configs/caisson-disko`. `ecosystemSrc` is the disko flake or source
  tree, resolved from the composition when absent. `rootMountPoint`
  defaults to `/mnt`. `checked` says whether the scripts are checked
  with shellcheck when they are built, and defaults to false.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the `evalModules` call.
- `ecosystemSrcOf`, `diskoLibOf`, `devicesOptions`, `layoutOf`,
  `exportsTo`: the resolution of the disko source, disko's type library
  from a source, the module declaring `disko.devices`, the layout
  product of an evaluated layout, and how a layout is published. The
  upstream-compatible `disko` integration builds on them.

### `caisson.disko` (module class `disko`)

- **Source:** `lib-overlays/disko/default.nix`

`disko` is the upstream-compatible disko integration. It is there so
that a layout written for disko can be used with caisson as it is, and
so that the machines installed onto it work with disko's tools:
disko's CLI against `nixosConfigurations`, `disko-install`, the image
builder and the install test. For a new configuration, we recommend
`caisson-disko`, which keeps disko out of the machines.
`caisson-disko` gives up those tools on the machine to do that, and
keeps compatibility with disko's CLI through `diskoConfigurations`.

A disko configuration is a module of the `disko` class: what a file
written for disko sets, `disko.devices`, is its module as it is. The
module also declares the NixOS configurations installed onto the
layout, under `caisson.nixos.configurations.<name>`. A tree registers
it as `configs/disko/nas-1/default.nix`:

```nix
{ ... }:
{ lib, ... }:
{
  # As written for disko.
  disko.devices.disk.main = { /* ... */ };
  # The NixOS configuration registered as `configs/nixos/nas-1`.
  caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration { };
}
```

and declares it with
`caisson.disko.configurations.nas-1 = lib.caisson.disko.mkConfiguration { };`.

The layout is evaluated as disko evaluates a layout on its own:
`evalModules` over `disko.devices`, typed with disko's type library,
with the framework modules, the selection and the configuration's
module beside it. The outputs are the layout product of
`caisson-disko`, without assertions, and `ecosystemSrc`, the disko
source the layout was evaluated with.

The default module of the class adds caisson's NixOS module
`disko-layout` to the default selection of the NixOS configurations
declared inside the layout. That module imports disko's NixOS module
from that source and defines `disko.devices` from the layout's
`serializableLayout`, at default priority. The NixOS configuration then
holds what disko's tools read: `config.disko.devices`, and the scripts
under `system.build`. `disko-install` replaces the disks with
`mkVMOverride`, which wins over the default priority. The other options
disko's module declares, such as `disko.imageBuilder` and
`disko.tests`, are set in the NixOS configuration's own modules. A
NixOS configuration that passes `moduleImports` lists the module
itself, as `caisson/disko-layout`.

For a layout and a machine with nothing caisson adds to them, the
machine builds the same system, with the same format script, as NixOS
builds from disko's module, the layout and the same machine module. The
machines are passed up under the names they are declared with, and the
layout is published as `diskoConfigurations.<name>`, as for
`caisson-disko`.

- `mkModule : freeformModule -> module`: class-bound `mkModule` for
  modules of the disko class.
- `mkConfiguration : { configModule?, pkgSets?, defaultPkgs?,
  ecosystemSrc?, moduleImports?, extraModuleImports?, specialArgs?,
  rootMountPoint?, checked? }`: a disko configuration, a function of
  `{ name, parent }`, finalized by the configuration that declares it
  under `caisson.disko.configurations.<name>`. `configModule` defaults
  to the configuration registered under its name in `configs/disko`.
  The other arguments are those of `caisson-disko`.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the `evalModules` call.

### `caisson.caisson-facter` (module class `caisson-facter`)

- **Source:** `lib-overlays/caisson-facter/default.nix`

A caisson-facter configuration is the hardware of a machine: a module
of the class with `facter.report`, the hardware report nixos-facter
writes, as data, or `facter.reportPath`, the `facter.json` it writes,
which `facter.report` defaults to. It declares the NixOS configurations
that run on the hardware under `caisson.nixos.configurations`. A
project can extend the class with options of its own about the
hardware.

caisson evaluates the configuration with its own `evalModules`, on the
composed library, over the report options, `assertions`, the framework
modules, the selection and the configuration's module. Its outputs are:

| Output | Value |
| --- | --- |
| `report` | the report, refused unless its `version` is one of `supportedReportVersions` (today `[ 1 ]`) or the report is empty |
| `reportFile` | the report as a JSON file |
| `serializableConfig` | the configuration as data, without caisson's options and without functions or attributes whose names begin with `_` |
| `hash` | the hash of `serializableConfig` |

Every output fails with the messages of the assertions that do not
hold. The NixOS configurations declared inside it get caisson's NixOS
module `caisson-facter-hardware` by default. That module sets
`hardware.facter.report` to the report, at `mkDefault` priority, and
nixpkgs' `hardware.facter` module turns the report into the settings
of the hardware. A module of such a NixOS configuration that needs more
of the hardware reads it through
`lib.caisson-core.evalManifest.nearest.caisson-facter`.

A tree registers the hardware as
`configs/caisson-facter/box-1/default.nix`, with `facter.reportPath =
./facter.json;` and the machine
`caisson.nixos.configurations.${lib.caisson-core.evalManifest.name} =
lib.caisson.nixos.mkConfiguration { };`. It is not published under an
output attribute set; its outputs are on its manifest.

- `mkModule : freeformModule -> module`.
- `mkConfiguration : { configModule?, defaultPkgs?, moduleImports?,
  extraModuleImports?, specialArgs? } -> configuration`.
  `configModule` defaults to the configuration registered under its
  name in `configs/caisson-facter`.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the `evalModules` call.
- `supportedReportVersions`: the report versions the integration
  accepts.

### `caisson.facter` (module class `facter`)

- **Source:** `lib-overlays/facter/default.nix`

A facter configuration is a `facter.json` as nixos-facter writes it,
named by `reportPath`, the one option of the class, with the NixOS
configurations that run on that hardware declared inside it. The
NixOS configurations get caisson's NixOS module `facter-hardware` by
default, which sets `hardware.facter.reportPath` to that file at
`mkDefault` priority, the line a NixOS configuration written for
nixos-facter carries. The outputs are `reportPath` and `report`, the
content of the file. For a report checked against the versions caisson
knows or extended with options of a project, see
[`caisson.caisson-facter`](#caissoncaisson-facter-module-class-caisson-facter).

- `mkModule : freeformModule -> module`.
- `mkConfiguration : { configModule?, defaultPkgs?, moduleImports?,
  extraModuleImports?, specialArgs? } -> configuration`.
  `configModule` defaults to the configuration registered under its
  name in `configs/facter`.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the `evalModules` call.

caisson's tests declare a machine inside each kind of facter
configuration, from the report of nixpkgs' own facter test. Each
machine gets the report and the kernel modules of its initrd that a
NixOS configuration setting `hardware.facter.reportPath` itself gets.

### `caisson.terranix` (module class `terranix`)

- **Source:** `lib-overlays/terranix/default.nix`

A terranix configuration is a Terraform configuration written as
terranix modules, evaluated with terranix's `terranixConfiguration` at
every system in force where it is declared, on the package set
selected for it (`defaultPkgs`, else the set named `default`). A tree
registers it as `configs/terranix/infra/default.nix` and declares it
with
`caisson.terranix.configurations.infra = lib.caisson.terranix.mkConfiguration { };`,
which finds the configuration by its name.

Its value and its output `json` are the `config.tf.json` file that
Terraform reads, with the evaluated configuration under
`passthru.config`. A top publishes it as `terranixConfigurations.infra`,
the name terranix's flake-parts module gives its configurations, and a
terranix configuration that is a top is that file.

terranix evaluates its modules with its own module system, on the
library of the package set, and caisson cannot hand it the composed
library as the library of the evaluation. The modules get the composed
library as the `lib` argument, and the package sets of the composition
as `pkgSets`; terranix merges and checks the options with its own
library. terranix returns only the configuration Terraform reads and
its `_meta`, so caisson reads its own options back through
`_meta.caisson`, and a terranix configuration holds no configurations
beneath it.

- `mkModule : freeformModule -> module`.
- `mkConfiguration : { configModule?, ecosystemSrc?, defaultPkgs?,
  moduleImports?, extraModuleImports?, specialArgs? } -> configuration`.
  `configModule` defaults to the configuration registered under its
  name in `configs/terranix`. `specialArgs` becomes terranix's
  `extraArgs`.
- `mkTopConfiguration`: the same arguments; finalizes the configuration
  at a top and returns its `config.tf.json`, or the files by system
  where several systems are in force.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the call of `terranixConfiguration` (`pkgs`, `modules`,
  `extraArgs`, `strip_nulls`).

### `caisson.treefmt` (module class `treefmt`)

- **Source:** `lib-overlays/treefmt/default.nix`

A treefmt configuration is the formatters of a tree, written as
treefmt-nix modules (`projectRootFile`, `programs.<name>.enable`,
`settings`). It is evaluated at every system in force where it is
declared, on the package set selected for it (`defaultPkgs`, else the
set named `default`).

treefmt-nix evaluates its modules on the library of a nixpkgs. caisson
evaluates them with its own `evalModules`, on the composed library, over
`submodule-modules`, the modules treefmt-nix publishes for a
configuration embedded in another, with `pkgs` set to the selected
package set. The special arguments those modules need are read from the
type treefmt-nix's `submoduleWith` returns.

| Output | Value |
| --- | --- |
| `wrapper` | treefmt with its configuration, the program `nix fmt` runs |
| `configFile` | the `treefmt.toml` |
| `programs` | the formatters by name |
| `check` | a function from a source tree to a derivation that fails when the tree is not formatted |

A tree registers the configuration as `configs/treefmt/default/default.nix`
and declares it with
`caisson.treefmt.configurations.default = lib.caisson.treefmt.mkConfiguration { };`.
A top publishes only the configuration named `default`:

| Output | Value |
| --- | --- |
| `formatter.<system>` | its wrapper, which `nix fmt` runs |
| `checks.<system>.treefmt` | its `check` over the root of the tree, `root` on `mkLib`, which `nix flake check` builds; it fails when the tree is not formatted |

The check is published where `mkLib` is given a `root`. caisson's tests check that the wrapper is the derivation treefmt-nix's
`mkWrapper` builds from the same module on the same package set, and
that the published check is the configuration's `check` over the root.

- `mkModule : freeformModule -> module`.
- `mkConfiguration : { configModule?, ecosystemSrc?, defaultPkgs?,
  moduleImports?, extraModuleImports?, specialArgs? } -> configuration`.
  `ecosystemSrc` is the treefmt-nix flake or source tree, resolved from
  the composition under the name `treefmt-nix` when absent.
- `mkTopConfiguration`: the same arguments; finalizes the configuration
  at a top and returns its evaluation, or the evaluations by system
  where several systems are in force.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the `evalModules` call.

### `caisson.nvf` (module class `nvf`)

- **Source:** `lib-overlays/nvf/default.nix`

An nvf configuration is a Neovim, written as nvf modules (`vim.*`). It
is evaluated per system, once for each system in force where it is
declared, on the package set selected for it (`defaultPkgs`, else the
set named `default`).

nvf evaluates its modules with `neovimConfiguration`, on the library of
nixpkgs extended with nvf's `lib.nvim`. caisson evaluates the same
module list, `modules/modules.nix`, with the special arguments
`neovimConfiguration` passes, on the composed library extended with
`lib.nvim` from the same nvf source. nvf's modules read the inputs of
the nvf flake, so `ecosystemSrc` is the nvf flake, resolved from the
composition under the name `nvf` when absent.

The output is `neovim`, the wrapped Neovim that `neovimConfiguration`
returns. A top publishes the configuration as
`nvfConfigurations.<system>.<name>`, in the shape `neovimConfiguration`
returns: `neovim`, `config` and `options`. caisson's tests check that
the Neovim is the derivation `neovimConfiguration` builds from the same
module on the same package set.

- `mkModule : freeformModule -> module`.
- `mkConfiguration : { configModule?, ecosystemSrc?, defaultPkgs?,
  moduleImports?, extraModuleImports?, specialArgs? } -> configuration`.
  `configModule` defaults to the configuration registered under its
  name in `configs/nvf`.
- `mkTopConfiguration`: the same arguments; finalizes the configuration
  at a top and returns its evaluation, or the evaluations by system
  where several systems are in force.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the `evalModules` call.

### `caisson.nixvim` (module class `nixvim`)

- **Source:** `lib-overlays/nixvim/default.nix`

A nixvim configuration is a Neovim, written as nixvim modules
(`plugins.*`, `opts`, `keymaps`). It is evaluated at every system in
force where it is declared, on the package set selected for it
(`defaultPkgs`, else the set named `default`).

nixvim evaluates its modules with `evalNixvim`, `evalModules` over
`modules/top-level` on a library extended with the overlay the nixvim
flake publishes as `lib.overlay`. caisson makes the same evaluation on
the composed library extended with that overlay, with `nixpkgs.pkgs`
set to the selected package set and the flake as `flake`. So
`ecosystemSrc` is the nixvim flake, resolved from the composition under
the name `nixvim` when absent.

The output is `package`, the Neovim (`config.build.package`). A top
publishes the evaluated configuration as
`nixvimConfigurations.<system>.<name>`, the name the nixvim flake
publishes its own configurations under. caisson's tests check that the
package is the derivation `evalNixvim` builds from the same module on
the same package set.

- `mkModule : freeformModule -> module`.
- `mkConfiguration : { configModule?, ecosystemSrc?, defaultPkgs?,
  moduleImports?, extraModuleImports?, specialArgs? } -> configuration`.
  `configModule` defaults to the configuration registered under its
  name in `configs/nixvim`.
- `mkTopConfiguration`: the same arguments; finalizes the configuration
  at a top and returns its evaluation, or the evaluations by system
  where several systems are in force.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the `evalModules` call.

### `caisson.topology` (module class `topology`)

- **Source:** `lib-overlays/topology/default.nix`

A topology configuration is the diagram of a network: the NixOS
configurations declared inside it under `caisson.nixos.configurations`,
whose `topology` options nix-topology reads, and modules of the class
that add nodes and networks of their own. It is evaluated at every
system in force where it is declared, on the package set selected for
it, extended with the packages of nix-topology.

caisson evaluates nix-topology's `topology` modules with its own
`evalModules` on the composed library, and sets `nixosConfigurations`
to the NixOS configurations declared inside it, evaluated at its
system. Those NixOS configurations get nix-topology's NixOS module by
default, through `caisson.forChildren`. `ecosystemSrc` is the
nix-topology flake or source tree, resolved under the name
`nix-topology`.

The output is `output`, the rendered diagram. A top publishes the
configuration named `default` as `topology.<system>`, the evaluation,
where nix-topology's flake module publishes it, so
`nix build '.#topology.x86_64-linux.config.output'` builds the diagram.
Its machines are published as `nixosConfigurations` like any NixOS
configuration. caisson's tests check that two machines declared inside
give the nodes and the diagram nix-topology gives the same machines
evaluated with its NixOS module.

### `caisson.kubenix` (module class `kubenix`)

- **Source:** `lib-overlays/kubenix/default.nix`

A kubenix configuration is Kubernetes resources written as kubenix
modules, which import the kubenix modules they use from the `kubenix`
argument (`imports = [ kubenix.modules.k8s ];`). caisson makes the
evaluation kubenix's `evalModules` makes, on the composed library
extended with kubenix's `upstreamables.nix`, with the same `kubenix`
argument, at every system in force on the selected package set.
`ecosystemSrc` is the kubenix flake or source tree, resolved under the
name `kubenix`.

The output is `result`, the resources as the JSON file
`kubectl apply -f` reads, the `kubernetes.result` of kubenix's `k8s`
module. A top publishes it as `packages.<system>.<name>`. caisson's
tests check that it is the result kubenix's `evalModules` gives the
same module.

### `caisson.nixidy` (module class `nixidy`)

- **Source:** `lib-overlays/nixidy/default.nix`

A nixidy configuration is an Argo CD environment written as nixidy
modules (`nixidy.target`, `applications.*`). caisson evaluates it with
nixidy's own `mkEnv`, giving it the composed library as the library of
the evaluation and, through `mkEnv`'s `libOverlay`, the namespaces of
the composed library that nixidy's library lacks, such as `caisson`.
`mkEnv` returns no options, so a nixidy configuration holds no
configurations beneath it. `ecosystemSrc` is the nixidy flake,
resolved under the name `nixidy`.

The outputs are `environmentPackage`, the rendered manifests,
`activationPackage` and `bootstrapPackage`. A top publishes the
configuration as `nixidyEnvs.<system>.<name>`, which the nixidy CLI
reads. caisson's tests check that the environment is the one `mkEnv`
renders from the same module.

Each of the three takes the arguments of `caisson.treefmt`:

- `mkModule : freeformModule -> module`.
- `mkConfiguration : { configModule?, ecosystemSrc?, defaultPkgs?,
  moduleImports?, extraModuleImports?, specialArgs? } -> configuration`,
  `configModule` defaulting to the configuration registered under its
  name in `configs/<class>`.
- `mkTopConfiguration`, with the same arguments.
- `mkConfigurationWithEcosystemArgs`, the twin with `ecosystemArgs`,
  merged over the evaluator's call (`mkEnv`'s arguments for nixidy).

### `caisson.system-manager` (module class `systemManager`)

- **Source:** `lib-overlays/system-manager/default.nix`

A system-manager configuration is the system of a machine running
another Linux distribution, evaluated with system-manager's
`makeSystemConfig` at every system in force where it is declared. A
tree registers it as `configs/systemManager/default/default.nix` and
declares it with
`caisson.system-manager.configurations.default = lib.caisson.system-manager.mkConfiguration { };`.
Its value and its output `toplevel` are the system, with the evaluated
configuration under `passthru.config`. A top publishes it as
`systemConfigs.default`, which `system-manager switch --flake .` reads
when it is given no name.

A system-manager configuration runs on the package set selected for it
(`defaultPkgs`, else the set named `default`), as every other
integration does, and on the nixpkgs the composition declares, as a
NixOS configuration does. system-manager's flake publishes
`makeSystemConfig` from its `nix/lib.nix` called with the nixpkgs the
flake pins. caisson calls the same file with the composition's nixpkgs
and the composed library, as the NixOS integration calls
`nixos/lib/eval-config.nix`. The library, the NixOS modules
system-manager imports and the evaluation all come from there.

`makeSystemConfig` makes `pkgs` itself and declares `nixpkgs.pkgs`
read-only. caisson passes the selected set as the `pkgs` special
argument, which the module system takes before `_module.args`, so the
selected set is the `pkgs` of every module and `nixpkgs.pkgs`.
`userborn`, the user manager system-manager pins, is built from the same
source on the selected set. caisson defaults `nixpkgs.hostPlatform` to
the platform of the selected set.

The selected set makes `nixpkgs.overlays`, `nixpkgs.config` and the
`overlays` argument of `makeSystemConfig` ineffective, so a
configuration that sets one is refused, as one whose
`nixpkgs.hostPlatform` differs from the platform of the selected set
is. Package configs and package overlays are declared on `mkLib`. The
modules get the composed library as `lib` and the package sets of the
composition as `pkgSets`. caisson adds a compatibility bridge for the
current nixos-unstable restructuring of the NixOS nix module (each half
self-retires; see the source comments).

- `mkModule : freeformModule -> module`.
- `mkConfiguration : { configModule?, ecosystemSrc?, defaultPkgs?,
  moduleImports?, extraModuleImports?, specialArgs? } -> configuration`.
  `configModule` defaults to the configuration registered under its
  name in `configs/systemManager`.
- `mkTopConfiguration`: the same arguments; finalizes the configuration
  at a top and returns its system, or the systems by system where
  several systems are in force.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the call of `makeSystemConfig` (`modules`, `specialArgs`,
  `allowUnsupportedNixpkgs`; `overlays` is refused).
