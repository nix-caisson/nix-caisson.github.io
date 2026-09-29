# Library Reference

A composed library carries two framework namespaces. `lib.caisson-core`
holds the machinery, injected by `mkLib` itself (its code lives in
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
  `lib-overlays/<name>/default.nix` (`compose`, `resolve`, `kernel`,
  `lifecycle`, `readers`, `pins`): caisson-core is a composition of those
  entries, and `mkLib` composes the same entries, keyed `caisson-core/<name>`,
  into every library it builds, so this namespace is one definition
  wherever it appears and each part is a registered entry a same-key
  entry replaces.

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
  , libOverlays       ? (mkLibOverlay: { })
                      : (freeformOverlay -> libOverlay) -> attrsOf libOverlay
  , libOverlayImports ? (lib: <every project and local registration>)
                      : lib -> listOf libOverlay           # given the core lib
  , pkgOverlays       ? (mkPkgOverlay: { })
                      : (freeformOverlay -> pkgOverlay) -> attrsOf pkgOverlay
  , defaultEcosystemSrc ? { } : attrs                      # the tree's default source per ecosystem, by exact name;
                                                           # nixpkgs supplies the nixpkgs-lib part unless nixpkgs-lib names its own
  , systems           ? null : listOf str                  # the platforms the tree builds on
  , projects          ? { } : attrs                        # consumed upstream contributions, by project name
  } -> lib
```

Builds a composed library over the seed, the empty attribute set: the
`caisson-core` entry (registered under that name, so a registration
under the same name replaces it), the published `nixpkgs-lib` entry
(nixpkgs' `lib`, sourced from `defaultEcosystemSrc`, imported by every
integration overlay rather than composed on its own), the selected
registered overlays, then two synthetic overlays: the local module
registrations (so local names win over overlay-borne contributions)
and the manifest. Every source arrives as an argument or a
declaration; the exact-name fallback over `sources` applies to
ecosystem resolution only (see
[Ecosystem sources](../concepts/ecosystem-sources.md)).

The library is built in three stages, each a new fixpoint over the
seed with its own manifest in `lib.caisson-core.libManifest`:

- The **core lib** holds the `caisson-core` entries and nothing else,
  with the lib overlay registry grafted onto its manifest.
  `libOverlayImports` receives it.
- The **bootstrap lib** adds the selection, and with it the
  `nixpkgs-lib` entry and every integration namespace. `modules` and
  `configs` receive it; its manifest has no `modules`,
  `moduleProjects`, `configs` or `pkgOverlays`.
- The **full lib** is the same entries with the module
  registrations, the configurations and the package overlay registry
  grafted on. `mkLib` returns it.

A registration made at an earlier stage still closes over the full
lib. The constructors the core and bootstrap libs hold (`mkModule`,
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
leftover `inputs` included, is Nix's own error at the call site,
naming `mkLib` and pointing at the pattern.

- `modules` receives the bootstrap lib and returns the class-keyed
  registration, built with the
  integrations' `mkModule` helpers (`lib.caisson.nixos.mkModule`,
  `lib.caisson.flake-parts.mkModule`, and so on).
  `lib.caisson-core.mkModule "<class>"` is for a class no integration
  covers. `mkModules ./modules` derives the function from the
  conventional layout.
- `configs` receives the bootstrap lib the same way and returns the
  configurations of the tree, keyed by module class then name, the
  layout `configs/<class>/<name>` on disk (colmena's class is
  `colmena`); `mkModules ./configs` reads that layout. They come back
  as `lib.caisson-core.configs.<class>.<name>`, so a top and a
  configuration that evaluates another beneath itself reach them by
  name rather than by a path out of their directory.
- `libOverlays` receives the input-closed `mkLibOverlay` helper and
  returns the registered overlays; `mkLibOverlays ./lib-overlays`
  derives it from the layout.
- `pkgOverlays` receives the input-closed `mkPkgOverlay` helper and
  returns the registered package overlays; `mkPkgOverlays
  ./pkg-overlays` derives it from the layout (see `pkgOverlays` below).
  These four arguments take exactly the function shape shown; passing
  anything else is an error.
- `libOverlayImports` selects which registered overlays apply to the
  `lib` of this flake. It receives the core lib and names entries from
  the registry on its manifest
  (`lib: [ lib.caisson-core.libManifest.libOverlays.my-overlay ]`);
  the default selects every project and local registration.
  Registration also feeds export, so the two can differ.
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
  a single overlay by hand is the way to cherry-pick or rename one.

### `mkModules`, `mkLibOverlays`, `mkPkgOverlays`

```
mkModules     : path -> lib -> attrsOf (attrsOf module)   # <dir>/<class>/<name>/default.nix
mkLibOverlays : path -> (freeformOverlay -> libOverlay) -> attrsOf libOverlay
                                                          # <dir>/<name>/default.nix
mkPkgOverlays : path -> (freeformOverlay -> pkgOverlay) -> attrsOf pkgOverlay
                                                          # <dir>/<name>/default.nix
```

The directory readers: each returns the function `mkLib` takes, so a
tree with the conventional layout registers by naming the directory
(`modules = core.mkModules ./modules; configs = core.mkModules
./configs; libOverlays = core.mkLibOverlays ./lib-overlays;`).
`mkModules` reads the first directory level as the class, whatever
its name, and registers each entry directory through the class index
of the composed library, `caisson-core.classes.<class>.mkModule`, the
`mkModule` of the integration that declares the class; a directory
for a class no composed integration declares is an error naming the
declared classes. `mkLibOverlays` applies `mkLibOverlay`, and
`mkPkgOverlays` applies `mkPkgOverlay`. An entry is
a directory holding a `default.nix`, a symlink to one included;
anything else in a directory being read is an error, so a stray file
cannot silently vanish from a registry. A tree with another layout
writes the registration by hand. Both are also available before any
composition exists, on `caisson-core` itself
(`caisson.lib.caisson-core.mkModules`).

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
join under `<project>/<name>`; a key of the project's own (one
without a `/`) becomes `<project>/<key>` in its imports too, so an
import still meets its sibling, and a key naming another project's
entry (one with a `/`) is kept, so two projects importing the same
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
to one, and normalizes the result: the built `libOverlay` always carries
both keys, with `imports` defaulted to `[ ]`. Already-built overlays are
registered directly rather than wrapped.

The closure's `closure-lib` is the composed library of the composition
that registered the overlay, bound lazily: read it inside the
`overlay` function or a function it defines, never while the overlay
is being registered. An integration reaches the registry of its own
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

Factory for class-specific module normalizers. Given a class name, returns a normalizer that applies the closure attrset to a module given as a function or a path to one; the module takes the closure as its first arg list (`{ ... }:` when unused). Plain modules are imported/registered directly rather than wrapped. Path modules gain `_file` and a path-based dedup `key`.

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
`nearest` and `children` are empty. The manifests of the core and
bootstrap libs have `childless = true`, and the core manifest lists
only the `caisson-core` entries in `entries`.
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
name for a contributed one, `caisson-core` for the lib overlay entries
caisson-core publishes into every composition), and
`moduleProjects.<class>.<name>` holds the same for modules, beside the
module dictionary. The export selectors default to the entries whose
origin is null. An
mkLib composition self-describes: the composed library of a consumer
carries the manifest of that consumer. Checks live on the export side
only (the flake-parts integration type-checks it and projects the
`flake.libOverlays` and `flake.modules` outputs from it, so an
`exported` selection can re-export a project-borne entry the same
way as a hand-registered one); a producer validates the manifest it
publishes in its CI.

`_type = "caisson-manifest"` marks the attrset as a manifest, which
is how `manifestOf` recognizes one.

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
composition's own `name` for a local one, `caisson-core` for its
entries) and `origin.file` the file the entry was built from, where
there is one; a lib overlay built from a file records it as its
`origin`. A layer event also keeps the two sides of its overlay call
`final: prev: result`: `prev` is the accumulation it received and
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
- an attrset carrying one at `caisson.manifest`;
- an evaluated configuration carrying one at `config.caisson.manifest`;
- a composed library carrying the phase slots (`libManifest`,
  `pkgsManifest`, `evalManifest` under `caisson-core`), or a package
  set carrying them in `pkgs.lib`. The last filled slot is the
  manifest: `evalManifest` if set, else `pkgsManifest`, else
  `libManifest`.

A value carrying none of these returns null.

```nix
manifestOf (import ./.)   # the manifest of a flakeless top
manifestOf lib            # lib.caisson-core.libManifest
```

### `importApply`

```
importApply : freeformModule -> attrs -> module
```

Applies static arguments to a module through `_file`/`imports` wrappers while preserving wrapper metadata. Used for threading arguments through module import chains.

### `callConsumerFlake`

```
callConsumerFlake :
  { path       : path | string   # directory containing flake.nix
  , pool       ? { } : attrs     # inputs resolvable by name
  , overrides  ? { } : attrs     # highest-precedence injections
  , sourceInfo ? { } : attrs     # extra self attrs (lastModified, rev, ...)
  } -> flakeOutputs              # self: inputs, outputs, outPath, _type
```

Evaluates a consumer-style flake from source with explicitly supplied
inputs: the heart of integration testing. The flake's declared inputs
resolve by name: `overrides` first, then `follows` chains through the
other resolved inputs, then `pool`; an unresolvable input throws an
error naming it. The self fixpoint and decoration are handled by the
shared `call-flake` kernel (also used by the eval-weight harness).
Nothing is fetched: locks are not read, and `sourceInfo` attrs appear
only if supplied. See [Testing](../testing.md).

### `compose`, `resolve`, `callFlake`

Keyed composition (`compose`), the layered ecosystem-source
resolver (`resolve`, over `explicit`, `defaults` and `sources`) and
the flake caller (`callFlake { src, inputs }`: a flake's outputs
function applied to inputs given as values, fetching nothing; the
flake-parts integration instantiates flake-parts through it),
re-exposed from caisson-core. A flake-parts partition takes the
inputs of its lockfile'd subflake from `pins.flake-compat` (below).
See
[How `lib` is composed](../deep-dives/how-lib-is-composed.md) and
the documentation of caisson-core.

### `pins`

```
pins.flake        : inputs -> { sources; root; }
pins.flake-compat : path -> { sources; }
pins.npins        : path -> { sources; }
pins.gitRoot      : path -> root
```

The pin readers, a reader per pin system. Each reads the pin system's
files into `sources`: every pinned tree, as the pin system hands it
over (a flake input keeps its outputs), plus `pin`, the record of how
it is pinned.

- `pin.system`: `"flake"` from either flake reader, `"npins"` from
  `pins.npins`; the writer that moves the source follows from it.
- `pin.files`: `{ refs; revisions; }`, the file that holds the ref and
  the file that holds the revision, relative to `pin.dir` when present
  and to the tree's root otherwise.
- `pin.dir`: the directory holding the pin files, for a reader given a
  directory.
- `pin.url`: the ref as the pin files write it.
- `pin.rev`, `pin.narHash`, `pin.lastModified`: the identity of the
  tree, where the pin system records it.
- `pin.follows`: for a flake input declared as a `follows`, the path of
  input names it follows; its tree is that of the input it lands on.
- `pin.overridden`: `pins.flake` only, true when an `--override-input`
  replaced the input, so `pin.url` describes the lock rather than the
  tree.

`pins.flake inputs` reads the inputs Nix's flake evaluator resolved for
the flake being evaluated, the `inputs` its `outputs` receives, and
returns the `root` from `self`. `pins.flake-compat ./dir` resolves the
`flake.lock` beside a `flake.nix` in that directory the way
flake-compat does, stopping before the flake's `outputs`; Nix's flake
evaluator never sees the pair, so no `--override-input` reaches it and
it has no root. It stays valid under read-only evaluation (`nix flake
check --no-build`). `pins.npins ./npins` reads `sources.json` format
8 and fetches each pin as npins' generated `default.nix` does; it
refuses Container pins, which need nixpkgs.

A root is `{ outPath; dirty; rev; shortRev; dirtyRev; dirtyShortRev;
lastModified; lastModifiedDate; narHash; }`, the identity of the tree
being built: the source-info fields a flake's `self` carries, each
null where the reader has none. The names are fixed and the values
lazy, since inside a flake's `outputs` asking which attributes `self`
has forces the outputs being computed; the names of a flake input's
`pin` are fixed for the same reason, `pin.url` and `pin.follows` being
null where they do not apply. A flakeless top in a git working
tree reads it with `pins.gitRoot ./.` under an impure evaluation: the
revision of a clean tree, or `dirty = true` with `dirtyRev` for a
dirty one.

```nix
# flake.nix outputs
inherit (caisson-core.pins.flake inputs) sources root;

# test-only pins beside the tree's own
inherit (caisson-core.pins.flake-compat ./tests/dependencies) sources;

# a flakeless top pinned with npins
inherit (caisson-core.pins.npins ./npins) sources;
root = caisson-core.pins.gitRoot ./.;
```

## The caisson namespace

`lib.caisson` holds one namespace per integration target
(`lib.caisson.flake-parts`, `lib.caisson.nixos`, and so on; see
[Integration namespaces](#integration-namespaces)), plus the
pkgs-dependent tooling documented at the end of this section.
caisson's registered flake modules are listed here too.

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
(`<project>/<name>`), or one caisson-core publishes into every
composition, leaves only when a selector names it: a project
republishes an upstream's entries only on purpose, and a consumer
takes them from that upstream through its own `projects`. The flake
outputs are `libOverlays`, `modules` (and `flakeModules`),
`pkgOverlays` when the selection holds any, and `overlays`.
`caisson/default` for the `flake` class is caisson's contribution to
the default default: it imports `caisson/nixpkgs` below.

### `modules.flake."caisson/nixpkgs"`

- **Source:** `modules/flake/nixpkgs/`

The nixpkgs integration's flake module, the package-set machinery.
Package overlays are entries of the mkLib `pkgOverlays` registry
(`mkPackagesOverlay` and `mkPolyfillOverlay` below build the overlay
an entry holds), and this module's `caisson.nixpkgs.*` options apply
them:

- `pkgSets.<name>`: a package-set definition: `pkgFunction` (a
  nixpkgs-style entry point, e.g. `import inputs.nixpkgs`) and
  `pkgOverlayImports` (a selection function from the registry to the
  entries to apply; default every entry named `default` or
  `<project>/default`). A set applies each selected entry after the
  entries it imports, and each key once (`pkgOverlaysFor`). Each set
  is reified per system and handed to `perSystem` modules as the
  `pkgSets` argument; `pkgSets.pkgs` also becomes the default
  `perSystem` `pkgs`.
- `config`: the nixpkgs config applied to every generated package set.
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
composing any integration composes this one as well, and the
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
Required arguments are bare in the pattern and optional ones default
to `null`; the composition supplies the value of an omitted argument.
`builtins.functionArgs` reads a signature back as data.

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
caller and the three places.

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
declaration. The result has two parts.

`namespace` is the value to publish as `lib.caisson.<name>`. It holds
`mkConfiguration`, `mkConfigurationWithEcosystemArgs`, `mkModule`, and
everything in `extra`. The two entry points are the declaration's,
written as pattern functions whose body is
`mkEvaluation { compose, evaluate }` applied to the admitted
arguments. The pattern of `mkConfiguration` names the five arguments
every entry point takes (`ecosystemSrc`, `pkgSets`, `configModule`,
`moduleImports`, `specialArgs`) and the few of its one target, with
the required ones bare and the rest defaulting to `null`; a comment
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
The overlay file writes the two keys itself:

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
`lib.caisson.<name>`: the two entry points of the declaration, pattern
functions as for an owner, and `extra`. It has no `mkModule`, because
modules of the class are registered through the owner, and it declares
no class. The composition its entry points evaluate over is expected
to build on the one the owner publishes, so that the two evaluators
cannot produce different configurations from the same arguments;
`caisson.nixos-minimal` composes through `caisson.nixos.compose` and
`caisson.home-manager-minimal` through `caisson.home-manager.compose`.

Every integration caisson ships is declared with these two
constructors: `mkIntegration` for the owners of a class (nixos,
flake-parts, structural, home-manager, colmena, terranix,
system-manager) and `mkAltIntegration` for `caisson.nixos-minimal`
and `caisson.home-manager-minimal`. Each overlay file holds the
composition, the evaluator step, the two patterns and the extras of
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
(`libOverlays.<ecosystem>`). Composing one contributes its
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
miss throws at the adapter, naming the three places; a composition
built without mkLib (no manifest) accepts only the explicit argument.
Common conventions:

- Every integration exports `mkConfiguration` (evaluate the target's
  module system with the selected class modules) and, where it has a
  module class of its own, `mkModule`, the form a tree registers that
  class's modules with (`caisson-core.mkModule` bound to the class).
  Target-specific variants and helpers sit beside them under the same
  namespace.
- `configModule`: the top-level module of the configuration, always a
  single module (compose several with `imports`); the framework's
  selected class modules are applied beside it.
- `specialArgs`: extra module arguments; the one name on every entry
  point, translated to the evaluator's spelling where it differs
  (home-manager's `extraSpecialArgs`, terranix's `extraArgs`).
- `pkgSets`: an attrset of package sets, accepted by every entry
  point and passed through as the `pkgSets` special argument. Where
  the evaluator has a package-set slot of its own, `pkgSets.pkgs`
  fills it: required for nixos, home-manager and terranix (the
  evaluation's package set), the default for colmena's
  `meta.nixpkgs`, and the source of system-manager's default
  `nixpkgs.hostPlatform`. flake-parts only forwards it.
- The signature is the whole surface. An entry point takes exactly
  the arguments listed for it and composes the evaluator's call from
  them; nothing else is forwarded, and an unknown or missing argument
  is Nix's function-argument error, raised at the call site and
  pointing at the entry point's pattern, whose comments name the
  caisson argument to use where one exists. That
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
nothing but caisson's core module, the manifest, the registry
selectors and `caisson.exports`. A structural configuration is the top
of a repository whose point is what it exports (the `default.nix` of
caisson is one).

- `mkModule : freeformModule -> module`: the registration form for
  structural modules.
- `mkConfiguration`:

```
mkConfiguration :
  { configModule  : module                                  # structural class
  , moduleImports ? (every entry named default)
                  : attrsOf module -> listOf module          # selection from the structural class registry
  , specialArgs   ? { }
  , pkgSets       ? null : attrs                            # the pkgSets special argument
  } -> { value : config; outputs : { exports : attrs } }
```

Evaluates the framework module (every `core` of the class, the one of
caisson read through the integration's closure), the selected
structural modules and the config module with `evalModules` over the
composed library. `value` is
the evaluated configuration; `outputs.exports` is `caisson.exports`,
the `lib`, `libOverlays` and `modules` the selectors chose. The
signature admits `ecosystemSrc` like every entry point, and this
integration refuses it, since it wraps no ecosystem.

- `mkConfigurationWithEcosystemArgs`: the twin; `ecosystemArgs` is
  merged over the `evalModules` call (`class`, `modules`,
  `specialArgs`).
- `mkTopConfiguration`: the same arguments; returns `outputs.exports`
  with `caisson.manifest` beside it, which is what `default.nix`
  returns for a reader that indexes attributes of the file's value.

### `caisson.flake-parts` (module class `flake`)

- **Source:** `lib-overlays/flake-parts/default.nix`
- `mkModule : freeformModule -> module`: the registration form for
  flake-parts modules (`caisson-core.mkModule` bound to the `flake`
  class).
- `mkConfiguration`:

```
mkConfiguration :
  { configModule  : module                                  # flake class
  , pkgSets       ? null                                    # the `pkgSets` special argument
  , ecosystemSrc  ? null                                    # the flake-parts source
  , moduleImports ? (every entry named default)
                  : attrsOf module -> listOf module          # selection from the flake class registry
  , specialArgs   ? { }                                     # beside `lib`, the composed library
  } -> flakeOutputs
```

  Builds final flake outputs via `flake-parts` using the composed
  `lib`, so it requires a manifest-carrying, mkLib-built composition.
  flake-parts' `inputs` are the manifest's pinned `sources`, and the
  integration ties `self` the way Nix does for a flake: the
  evaluation's outputs with the root's source info (out path,
  revision, last-modified) beside them and `self.inputs` the sources,
  so flake-parts modules receive `self`, `self'` and `inputs` as they
  would under Nix's own flake evaluation. `moduleImports` selects over
  the `flake` class of `lib.caisson-core.modules`, the same registry
  every adapter selects from, so modules arriving by local
  registration, overlay contribution, or consumed project are all
  selectable. flake-parts itself resolves like every ecosystem, from
  `ecosystemSrc`, `defaultEcosystemSrc.flake-parts` or the pinned
  source named `flake-parts`, and is instantiated over the composed
  library. The `name` the composition declares sets flake-parts'
  `moduleLocation`, so exported modules deduplicate across revisions.
- `types.libOverlay`: a module-system option type for built library
  overlays. Its `check` verifies the structure recursively: an
  attrset with an `overlay` function and a (possibly absent)
  `imports` list whose entries are themselves valid `libOverlay`s.
  Used by options that carry overlays, such as
  `caisson.libOverlays.exported`.
- `types.manifest`: a structural option type for the caisson-core
  lib manifest (`{ inputs, modules, libOverlays, ecosystems, projects,
  systems }`). The export-side check: the core flake-parts module
  reads `lib.caisson-core.libManifest`
  through an option of this type before projecting the
  `flake.libOverlays` and `flake.modules` outputs.

### `caisson.nixos` (module class `nixos`)

- **Source:** `lib-overlays/nixos/default.nix`
- `mkModule : freeformModule -> module`: class-bound `mkModule`.
- `mkConfiguration : { ecosystemSrc, pkgSets, configModule, moduleImports?,
  specialArgs?, system? } -> nixosSystem`: evaluates
  `<ecosystemSrc>/nixos/lib/eval-config.nix` (a nixpkgs source tree)
  with the selected class modules, the config module, and a framework
  module pinning `nixpkgs.pkgs` to `pkgSets.pkgs`. Extra arguments
  pass through to `eval-config.nix`.
- `mkConfigurationFull`: as `mkConfiguration`, additionally passing nixpkgs'
  `module-list.nix` as `baseModules`.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`
  (see the conventions above); eval-config's `baseModules` is one of
  the arguments reachable that way.
- `compose : { context?, nixpkgsModule? } -> args -> { modules,
  specialArgs, checkedPkgSets, src }`: the composition of the class
  from the caisson arguments (the framework and selected modules, the
  config module, the package-set module, the resolved nixpkgs
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
integration composed beside it.

- `mkConfiguration : { ecosystemSrc, pkgSets, configModule,
  moduleImports?, specialArgs?, prefix? } -> evaluation`.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`
  (`prefix`, `modules`, `specialArgs`).

### `caisson.home-manager` (module class `homeManager`)

- **Source:** `lib-overlays/home-manager/default.nix`
- `mkModule : freeformModule -> module`.
- `mkConfiguration : { ecosystemSrc, pkgSets, configModule,
  moduleImports?, specialArgs?, osConfig?, check?,
  sourceMeta? } -> homeConfiguration`
  (`mkConfigurationWithEcosystemArgs` is the twin with `ecosystemArgs`;
  home-manager's `lib` argument is reachable that way): runs home-manager's own
  evaluator (`<ecosystemSrc>/modules`). Source metadata defaults
  derive from what actually composes: `homeManagerOutPath` from
  `ecosystemSrc` and `nixpkgsOutPath` from `pkgSets.pkgs.path`
  (`schemaVersion` 3).
- `mkStandaloneAdapter : { moduleImports?, ... } -> { homeModules,
  buildHome }`: the selected class modules as a list plus a
  `buildHome` closure over the same arguments.
- `mkNixosAdapter : { users, ecosystemSrc, hostName?, hostKind?,
  baseSystem?, sourceMeta?, moduleImports?, sharedModules?,
  useGlobalPkgs?, useUserPackages?, activationMode?,
  specialArgs?, ... } -> module (nixos class)`: embeds
  home-manager in a NixOS generation. `activationMode = "upstream"`
  uses home-manager's own NixOS module; `"user-service"` embeds
  standalone activation packages behind a `ConditionUser` user unit
  and leaves `users.users` untouched, which keeps it safe for systemd-homed hosts (one
  hosted user). Both write `/etc/caisson-home-manager/source.json`
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
module list comes from `caisson.home-manager.compose`; composing it
needs the home-manager integration composed beside it.

- `mkConfiguration : { ecosystemSrc?, pkgSets, configModule,
  moduleImports?, specialArgs?, osConfig?, check?, sourceMeta? }
  -> homeConfiguration`.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`.

### `caisson.nixpkgs`

- **Source:** `lib-overlays/nixpkgs/default.nix`
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
(`makeHive`, `defaults`, `meta.nixpkgs`). The word hive names one
thing here: the output colmena's binary reads, which the evaluator
step projects the evaluated configuration onto.

- `mkModule : freeformModule -> module`: class-bound `mkModule` for
  colmena modules.
- `mkConfiguration : { ecosystemSrc, configModule, moduleImports?,
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
  `mkNixosConfiguration` is refused. `pkgSets` on the colmena
  configuration only serves `colmena eval` (`introspect`).
  `mkNixosConfigurationWithEcosystemArgs`
  is the node constructor's twin, also a module argument. Every node
  receives colmena's `name` and `nodes` special arguments (the latter
  the whole hive, lazily, for cross-node references), so a module
  written for colmena's own evaluator works unchanged. Node names are
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
- `mkConfiguration : { ecosystemSrc, pkgSets, configModule, moduleImports?,
  specialArgs? } -> derivation`:
  `ecosystemSrc.lib.terranixConfiguration` against `pkgSets.pkgs`,
  with the selected class modules and the config module;
  `specialArgs` becomes terranix's `extraArgs`.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`
  (`system`, `pkgs`, `strip_nulls`, and the composed ones); `pkgSets`
  is optional there.

### `caisson.system-manager` (module class `systemManager`)

- **Source:** `lib-overlays/system-manager/default.nix`
- `mkModule : freeformModule -> module`.
- `mkConfiguration : { ecosystemSrc, configModule, moduleImports?,
  specialArgs?, pkgSets? } -> systemConfig`:
  `ecosystemSrc.lib.makeSystemConfig` with the selected class
  modules and the config module, plus a compatibility bridge for the current
  nixos-unstable restructuring of the NixOS nix module (each half
  self-retires; see the source comments).
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`
  (`overlays`, `allowUnsupportedNixpkgs`, and the composed ones).
