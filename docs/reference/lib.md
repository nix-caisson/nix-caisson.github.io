# Library Reference

A composed library carries the framework namespaces `lib.caisson-core`
and `lib.caisson`. `lib.caisson-core` holds the machinery, injected by
`mkLib` itself (its code lives in
[caisson-core](https://github.com/nix-caisson/caisson-core), which
caisson pins internally). `lib.caisson`
holds the integrations and the pkgs-dependent tooling, contributed by
the overlays this flake exports. The flake-level `lib` output mirrors
both namespaces (`caisson.lib.caisson-core`, `caisson.lib.caisson`).

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
entry the full lib as `closure-lib`, and its
`caisson-core.modules.<class>` is the registry the entry joins, so a
module imports a sibling by name. A registration under a
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
  `colmena`); `lib: lib.caisson-core.mkModules ./configs` reads that
  layout. They come back
  as `lib.caisson-core.configs.<class>.<name>`, so a top and a
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
  `libOverlayImports = lib: [ lib.caisson-core.libOverlays.my-overlay ];`
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
  (`{ my-dep = inputs.my-dep; }`): each value carries `libOverlays`,
  class-keyed `modules` and `pkgOverlays` dictionaries, the outputs of
  a caisson-built flake. A project's overlays and package overlays join
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
class index and the entry constructors of that lib. Each registry
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
its name, and registers each entry directory through the class index
of the lib, `caisson-core.classes.<class>.mkModule`, the
`mkModule` of the integration that declares the class; a directory
for a class no composed integration declares is an error naming the
declared classes. `mkLibOverlays` applies `mkLibOverlay`, and
`mkPkgOverlays` applies `mkPkgOverlay`. An entry is
a directory holding a `default.nix`, a symlink to such a directory
included; anything else in a directory being read is an error, so a
stray file cannot silently vanish from a registry. A tree with another
layout writes the registration by hand.

### `classes`, `contributeClasses`

```
classes : attrsOf { integration : string; mkModule : freeformModule -> module }
contributeClasses : attrs -> attrsOf { integration; mkModule } -> attrs
```

The class index of a composition: per class, the integration that
owns it and the `mkModule` the class registers through. An
integration declares the class it owns from its overlay body, the way
`contributeModules` contributes modules
(`overlay = final: prev: contributeClasses prev { nixos = { integration = "nixos"; mkModule = final.caisson-core.mkModule "nixos"; }; } // { ... }`),
and a declaration composed later replaces it: an integration that
wraps another declares the same class with the `mkModule` it defines, and
every reader of the class, `mkModules` first, registers through the
wrapper. `caisson-core` declares the class-free `generic` class
itself. An integration that evaluates a class another integration
owns (`caisson.nixos-minimal`, `caisson.home-manager-minimal`) declares
nothing here.

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
          ; contributeModules  : attrs -> attrsOf (attrsOf module) -> attrs
          ; contributeClasses  : attrs -> attrsOf { integration; mkModule } -> attrs
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
composition through it (`closure-lib.caisson-core.modules.<class>`),
wherever it is later composed. The closure's `mkModule` is bound to
the defining composition, so modules contributed by an overlay close
over the definer's inputs and library. `contributeModules prev { <class>.<name> = module; }`
returns the `caisson-core.modules` registry merge for the overlay's
output (merge its result with any namespace contributions); it
is passed through the closure rather than the composed library because
an overlay's output attribute names must not depend on `final`.
Qualify contributed names with your project prefix
(`my-flake/my-service`); the registrations made in the `mkLib` call
itself apply last and win over same-named contributions. See
[Module classes](../concepts/module-classes.md) for the ways
modules enter the registry.

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

The `mkModule` closure member is bound to the same class, so nested module composition stays in that class. A module imports a sibling by name through `closure-lib.caisson-core.modules.<class>.<name>`, the registry of the composition that registered it.

### `modules`

```
modules : attrsOf (attrsOf module)    # class -> name -> module
```

The class-keyed module registry of this composition: the registrations
of the flake merged with every overlay-borne contribution and every
consumed project's entries (`<project>/<name>`), locals winning on
name conflicts. Integration adapters read their class from here
(`caisson-core.modules.<class>`): every entry named `core` (`core`,
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
`flake.libOverlays` and `flake.modules` outputs from it, so an
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
lib.caisson-core.libOverlays : attrsOf libOverlay
lib.caisson-core.pkgOverlays : attrsOf pkgOverlay
```

These attributes are the lib overlay registry and the package overlay
registry of the composition that built the library, keyed by registry
name. Each has the name of the `mkLib` argument that fills it and of
the manifest field it is a view of.

- `libOverlays` holds the entries `mkLib` registered, the entries
  consumed projects contributed under `<project>/<name>`, and the
  `caisson-core/<name>` entries. A `libOverlayImports` selection
  refers into it.
- `pkgOverlays` holds the package overlay entries: those `mkLib`
  registered and those consumed projects contributed. A package config
  selects from it:
  `caisson.nixpkgs.overlays = [ lib.caisson-core.pkgOverlays.default ];`.

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

`forChildren` is what the evaluation registers for the configurations
declared inside it. It has four fields:

- `modules`, by class and then name.
- `defaultModuleImports`, by class a list of selections, each a
  function of a lib returning modules.
- `defaultPkgs`, which selects the package set its children run on by
  default. It is null when the configuration selects no set.
- `systems`, the systems its children are evaluated for. It is null
  when the configuration lists no systems.

They are read from the childless evaluation and recorded on the
manifest as `forChildren`. A configuration declared inside inherits
the registry and the selections of its parent, extended by them. Its manifest holds the registry it sees as `modules`, where a
registration under a name already there replaces the entry, and the
selections added above it as `defaultModuleImports`, those from the
top first. The lib it runs on shows that registry as
`caisson-core.modules`. Every level extends both in turn, so a
registration can be selected by the configurations beneath the level
that made it, nested ones and ones beneath a system included.

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
| composing | `mkLib`, `pins`, `callFlake`, `callConsumerFlake` |
| making and reading entries | `mkModule`, `mkModules`, `mkLibOverlay`, `mkLibOverlays`, `mkPkgOverlay`, `mkPkgOverlays`, `importApply` |
| registries | `modules`, `configs`, `classes`, `libOverlays`, `pkgOverlays`, `pkgOverlaysFor` |
| manifests | `libManifest`, `pkgsManifest`, `evalManifest`, `manifestOf` |
| for an integration written outside caisson | `contributeClasses`, `contributeModules`, `finalizeTop`, `elide`, `ecosystemSrc` |

- `pins`, `callFlake` and `callConsumerFlake` are defined in caisson
  and documented below.
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

### `modules.<class>."caisson/core"`, `modules.flake."caisson/default"`

- **Source:** `modules/generic/core/` (the core module; `caisson.*`
  options under `caisson/`), `modules/structural/core` (a symlink to
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
takes them from that upstream through its `projects`. The flake
outputs are `libOverlays`, `modules` (and `flakeModules`),
`pkgOverlays` when the selection holds any, and `overlays`.
`caisson/default` for the `flake` class is caisson's contribution to
the default default: it imports `caisson/nixpkgs` below.

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

Both take a class registry (`lib.caisson-core.modules.<class>`) and
select entries by name. `coreModules` returns every entry named `core`,
which includes the `<project>/core` entries of consumed projects;
these form the framework module of the class, and every integration
applies them to every evaluation. `defaultModuleImports` returns every
entry named `default`, in the same way; this list is the default
default, the selection an evaluation gets when it passes no
`moduleImports`.

#### `names`, `childrenOf`

```
names      : listOf str
childrenOf : config -> attrsOf (attrsOf manifest)
```

`names` lists the integrations a configuration may be declared of:
those that own a module class, read from the class index. caisson's
core module declares `caisson.<integration>.configurations` for each.
`childrenOf` takes an evaluated configuration's `config` and returns
the configurations declared beneath it, by integration and then name,
leaving out an integration with none: the `children`
`mkModuleConfiguration` hands to `lib.caisson-core.mkConfiguration`.

#### `frameworkModules`, `mkModuleConfiguration`

```
frameworkModules      : str -> attrsOf module -> listOf module
mkModuleConfiguration : { type : str; perSystem ? false; defaultPkgs ? null; exportsTo ? null; evaluate : view -> evaluated; } -> configuration
evaluated = { value; outputs ? { }; config ? value.config; }
exportsTo = { attrset : str; value : manifest -> value;
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
records it on the manifest too. `attrset` is the output attribute
set; a NixOS configuration records `nixosConfigurations`. `value`
takes the manifest of the configuration to what is published.

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
  `caisson.forChildren.defaultModuleImports`, those from the top
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
home-manager-minimal, flake-parts and structural constructors, and on
the colmena node constructors. In a
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
evaluated at a system, given its evaluations by system. They are
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
  , extra      ? { } : attrs       # further members of the namespace
  } -> { namespace : attrs; classes : attrsOf { integration; mkModule } }
```

`mkIntegration` builds an integration that owns a module class from a
declaration. The result has the parts `namespace` and `classes`.

`namespace` is the value to publish as `lib.caisson.<name>`. It holds
`mkConfiguration`, `mkConfigurationWithEcosystemArgs`, `mkModule`, and
everything in `extra`. The entry points come from the declaration,
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

`classes` is the declaration of `class` for the class index: the
integration's name and its `mkModule`. Once it is in the index,
`mkModules` registers every `modules/<class>` directory through this
integration.

The integration's `compose` receives the admitted arguments and
returns an attribute set. That set must hold `ecosystemArgs`, the
arguments of the evaluator's call as the integration composed them; it
may hold anything else `evaluate` needs, such as the resolved source.
`evaluate` receives that set and the call arguments to use, and
returns the evaluation.

The constructor returns values rather than an overlay output, because
the attribute names an overlay produces must not depend on `final`.
The overlay file writes the keys itself:

```nix
overlay = final: prev:
  let
    integration = final.caisson.integrations.mkIntegration { ... };
  in
  contributeClasses prev integration.classes
  // {
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
  , extra    ? { } : attrs
  } -> attrs                       # the value of lib.caisson.<name>
```

`mkAltIntegration` builds an integration that evaluates a class
another integration owns. `over` is that owning integration, reached
through the lib. The result is the value to publish as
`lib.caisson.<name>`: the entry points of the declaration, pattern
functions as for an owner, and `extra`. It has no `mkModule`, because
modules of the class are registered through the owner, and it declares
no class. The composition its entry points evaluate over is expected
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
nixos-minimal and nixpkgs integrations, then `home-manager`, `colmena`,
`terranix`, `system-manager` and `flake-parts` for the integration of
the same name (the table in
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
- `defaultPkgs` is accepted by the nixos, nixos-minimal, home-manager,
  home-manager-minimal, flake-parts and structural entry points. It
  selects the package set the configuration runs on from the package
  configs the composition declares (see
  `caisson.integrations.pkgSetOf`). In a nixos or home-manager
  configuration, the modules get the package sets by config name as
  the `pkgSets` special argument.
- `pkgSets`: on the colmena, terranix and system-manager entry
  points, an attrset of package sets passed through as the `pkgSets`
  special argument, where `pkgSets.pkgs` is what the evaluator gets:
  the package set of a terranix evaluation, the default for colmena's
  `meta.nixpkgs`, and the source of system-manager's default
  `nixpkgs.hostPlatform`. flake-parts and structural forward it to
  their modules.
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
  registry (`lib.caisson-core.modules.<class>`), returning the list
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
configuration's name, `lib.caisson-core.configs.structural.<name>`,
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
  configuration's name, `lib.caisson-core.configs.flake.<name>`.
  flake-parts' `inputs` are the manifest's pinned `sources`, and the
  integration ties `self` the way Nix does for a flake: the
  evaluation's outputs with the root's source info (out path,
  revision, last-modified) beside them and `self.inputs` the sources,
  so flake-parts modules receive `self`, `self'` and `inputs` as they
  would under Nix's flake evaluation. `moduleImports` selects over
  the `flake` class of `lib.caisson-core.modules`, the same registry
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
  `flake.libOverlays` and `flake.modules` outputs.

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
  `lib.caisson-core.configs.nixos.<name>`.

  A NixOS configuration is evaluated at a system, so the integration
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

### `caisson.home-manager` (module class `homeManager`)

- **Source:** `lib-overlays/home-manager/default.nix`
- `mkModule : freeformModule -> module`.
- `mkConfiguration : { configModule?, ecosystemSrc?, defaultPkgs?,
  moduleImports?, extraModuleImports?, specialArgs?, osConfig?, check?,
  sourceMeta? } -> configuration`

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

  The defaults of the source metadata come from the sources the
  evaluation uses: `homeManagerOutPath` from `ecosystemSrc`, and
  `nixpkgsOutPath` from the path of the package set. The schema
  version is 3.
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
- `mkStandaloneAdapter : { moduleImports?, extraModuleImports?, ... } -> { homeModules,
  buildHome }`: the selected class modules as a list plus a
  `buildHome` closure over the same arguments, which returns a home
  as `mkConfiguration` does.
- `mkNixosAdapter : { users, ecosystemSrc, hostName?, hostKind?,
  baseSystem?, sourceMeta?, defaultPkgs?, moduleImports?, extraModuleImports?,
  sharedModules?, useGlobalPkgs?, useUserPackages?, activationMode?,
  specialArgs?, ... } -> module (nixos class)`: embeds
  home-manager in a NixOS generation. `activationMode = "upstream"`
  uses home-manager's NixOS module; `"user-service"` builds each home
  as `mkConfiguration` does, as a child of the NixOS configuration
  that imports the module, and runs its activation package from a
  `ConditionUser` user unit. That mode leaves `users.users`
  untouched, so it works on a machine whose user is managed by
  systemd-homed. Both write `/etc/caisson-home-manager/source.json`
  for the drift check.
- `mkSourceMeta`, `assertSourceCoherence`: source-provenance records
  and the fingerprint comparison used by the drift machinery.
  `mkSourceMeta` takes the building tree as `root`
  (`lib.caisson-core.libManifest.root`) and records its out path as
  `selfOutPath`.

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
declared under (`lib.caisson-core.configs.nixpkgsConfig.<name>`), and
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
  `caisson.nixpkgs.extraOverlays = [ lib.caisson-core.pkgOverlays.<name> ];`.

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

### `caisson.colmena` (module class `caisson-colmena`)

- **Source:** `lib-overlays/colmena/default.nix`
A colmena configuration is a module of the `caisson-colmena` class, a
class caisson defines itself, since colmena's hive format is not a
module class; the class carries the `caisson-` prefix because the bare
name is not caisson's to claim. The integration is not compatible with colmena's hive modules
(`makeHive`, `defaults`, `meta.nixpkgs`). The word hive names
only this here: the output colmena's binary reads, which the evaluator
step projects the evaluated configuration onto.

- `mkModule : freeformModule -> module`: class-bound `mkModule` for
  colmena modules.
- `mkConfiguration : { ecosystemSrc, configModule, moduleImports?, extraModuleImports?,
  specialArgs?, pkgSets? } -> hive`: evaluates the configuration's
  module with the selected colmena-class modules through
  `evalModules`, and projects the result onto colmena's hive schema
  (`__schema`, `nodes`, `toplevel`, `deploymentConfig`,
  `evalSelected`, ...), the attributes colmena's binary reads. The
  configuration declares `meta` (`name`, `description`,
  `machinesFile`, `allowApplyAll`) and `nodes.<name>`, and receives
  `mkNixosConfiguration` as a module argument, closed over the
  configuration's colmena source: `caisson.nixos.mkConfiguration`'s signature and
  composition over the host's module plus colmena's public node
  modules (`deploymentOptions`, `keyChownModule`, `keyServiceModule`,
  `assertionModule`). Its `ecosystemSrc` is nixpkgs, as for any NixOS
  configuration; set `deployment.*` in the host's module. A node is an
  ordinary NixOS configuration that also declares `deployment`; a
  consumer that exports it as `nixosConfigurations.<host>` reads it
  back from `hive.nodes`, one evaluation for `nixos-rebuild` and
  `colmena apply`. The schema version is asserted against the
  `makeHive` of the ecosystem source, so a colmena revision that moves
  it fails at evaluation; a node that did not come from
  `mkNixosConfiguration` is refused. What the constructor returns is a
  NixOS configuration, and the colmena configuration finalizes it
  under the name of the node, so a node takes its system and its
  package set from the composition like any NixOS configuration. A
  node is a machine, so the configuration has to have exactly one
  evaluation; with no system in force, or several, the colmena
  configuration refuses it and names the systems.
  `pkgSets` on the colmena
  configuration only serves `colmena eval` (`introspect`).
  `mkNixosConfigurationWithEcosystemArgs`
  is the node constructor's twin, also a module argument. Every node
  receives colmena's `name` and `nodes` special arguments (the latter
  the whole hive, lazily, for cross-node references), so a module
  written for colmena's evaluator works unchanged. Node names are
  free: `meta`, `defaults` and `network`, reserved in colmena's flat
  hive, are ordinary names under `nodes`. The only constraint is
  colmena's `--on` filter grammar: a name containing a comma, starting
  with `@`, or empty could never be selected, and is refused when the
  configuration is evaluated.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the `evalModules` call (`class`, `modules`,
  `specialArgs`); the result is projected onto the hive the same way.

### `caisson.terranix` (module class `terranix`)

- **Source:** `lib-overlays/terranix/default.nix`
- `mkModule : freeformModule -> module`.
- `mkConfiguration : { ecosystemSrc, pkgSets, configModule, moduleImports?, extraModuleImports?,
  specialArgs? } -> derivation`:
  `ecosystemSrc.lib.terranixConfiguration` against `pkgSets.pkgs`,
  with the selected class modules and the config module;
  `specialArgs` becomes terranix's `extraArgs`.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`
  (`system`, `pkgs`, `strip_nulls`, and the composed arguments);
  `pkgSets` is optional there.

### `caisson.system-manager` (module class `systemManager`)

- **Source:** `lib-overlays/system-manager/default.nix`
- `mkModule : freeformModule -> module`.
- `mkConfiguration : { ecosystemSrc, configModule, moduleImports?, extraModuleImports?,
  specialArgs?, pkgSets? } -> systemConfig`:
  `ecosystemSrc.lib.makeSystemConfig` with the selected class
  modules and the config module, plus a compatibility bridge for the current
  nixos-unstable restructuring of the NixOS nix module (each half
  self-retires; see the source comments).
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`
  (`overlays`, `allowUnsupportedNixpkgs`, and the composed arguments).
