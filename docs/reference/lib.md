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
  `lifecycle`, `readers`): caisson-core is its own composition, and
  `mkLib` composes those same entries, keyed `caisson-core/<name>`,
  into every library it builds, so this namespace is one definition
  wherever it appears and each part is a registered entry a same-key
  entry replaces.

### `mkLib`

```
mkLib :
  { inputs            : attrs                              # the defining flake's inputs
  , modules           ? (lib: { })
                      : lib -> attrsOf (attrsOf module)    # class -> name -> module
  , configs           ? (lib: { })
                      : lib -> attrsOf (attrsOf module)    # class -> name -> configuration
  , libOverlays       ? (mkLibOverlay: { })
                      : (freeformOverlay -> libOverlay) -> attrsOf libOverlay
  , libOverlayImports ? builtins.attrValues
                      : attrsOf libOverlay -> listOf libOverlay
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
and the manifest. Nothing is looked up by input name.

- `modules` receives the composed `lib` (usable through the fixpoint)
  and returns the class-keyed registration, built with the
  integrations' `mkModule` helpers (`lib.caisson.nixos.mkModule`,
  `lib.caisson.flake-parts.mkModule`, and so on).
  `lib.caisson-core.mkModule "<class>"` is for a class no integration
  covers. `mkModules ./modules` derives the function from the
  conventional layout.
- `configs` receives the composed `lib` the same way and returns the
  configurations of the tree, keyed by module class then name, the
  layout `configs/<class>/<name>` on disk (colmena's class is
  `colmena`); `mkModules ./configs` reads that layout. They come back
  as `lib.caisson-core.configs.<class>.<name>`, so a top and a
  configuration that evaluates another beneath itself reach them by
  name rather than by a path out of their directory.
- `libOverlays` receives the input-closed `mkLibOverlay` helper and
  returns the registered overlays; `mkLibOverlays ./lib-overlays`
  derives it from the layout. All three arguments take exactly the
  function shape shown; passing anything else is an error.
- `libOverlayImports` selects which registered overlays apply to this
  flake's own `lib`; registration also feeds export, so the two can
  differ.
- `defaultEcosystemSrc` declares the tree's default source per
  ecosystem (`{ nixpkgs = inputs.nixpkgs; ... }`), keyed by the exact
  names the integrations resolve. mkLib captures them into the
  manifest and reads the `nixpkgs-lib` source from them (the
  `nixpkgs-lib` name, else `nixpkgs`); the integrations interpret the
  rest.
- `projects` consumes whole upstream contributions
  (`{ my-dep = inputs.my-dep; }`): each value carries `libOverlays`
  and class-keyed `modules` dictionaries, which a caisson-built
  flake's outputs already do. A project's overlays join the
  registered dictionary and its modules join the class registry under
  `<project>/<name>`, so the existing selections keep per-item
  choice: `libOverlayImports` decides which overlays apply, the
  registry selection at each use site decides which modules load, and
  a local registration beats a same-named project entry. Registering
  a single overlay by hand stays the way to cherry-pick or rename
  one.

### `mkModules`, `mkLibOverlays`

```
mkModules     : path -> lib -> attrsOf (attrsOf module)   # <dir>/<class>/<name>/default.nix
mkLibOverlays : path -> (freeformOverlay -> libOverlay) -> attrsOf libOverlay
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
declared classes. `mkLibOverlays` applies `mkLibOverlay`. An entry is
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
wraps another declares the same class with its own `mkModule` and
every reader of the class, `mkModules` first, registers through the
wrapper. `caisson-core` declares the class-free `generic` class
itself. An integration that evaluates a class another integration
owns (`caisson.nixos-minimal`) declares nothing here.

### `mkLibOverlay`

```
mkLibOverlay : freeformOverlay -> libOverlay

freeformOverlay = path | (closure -> { imports ? listOf libOverlay
                                     ; overlay : overlayFn })
closure = { closure-inputs     : attrs
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
closure = { closure-inputs        : attrs    # the defining flake's inputs
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

The class-keyed module registry of this composition: the flake's own
registrations merged with every overlay-borne contribution and every
consumed project's entries (`<project>/<name>`), locals winning on
name conflicts. Integration adapters read their class from here
(`caisson-core.modules.<class>`): every entry named `core` (`core`,
`<project>/core`) is the framework module of the class, forced into
every evaluation, and every entry named `default` is the default
default, what an evaluation gets when it passes no `moduleImports`.

### `manifest`

```
manifest : { inputs : attrs; modules : attrsOf (attrsOf module);
             configs : attrsOf (attrsOf module);
             libOverlays : attrsOf libOverlay;
             defaultEcosystemSrc : attrs; systems : nullOr (listOf str);
             projects : attrs }
```

The composition's self-description, injected as its final overlay.
`inputs`, `defaultEcosystemSrc`, `systems`, `projects` and `configs`
are the `mkLib` arguments as given; `libOverlays` and `modules` are the
registered dictionaries, so consumed projects' entries appear under
`<project>/<name>` beside
the local registrations, with a local winning a name collision. An
mkLib composition self-describes: a consumer's composed library
carries the consumer's own manifest. Checks live on the export side
only (the flake-parts integration type-checks it and projects the
`flake.libOverlays` and `flake.modules` outputs from it, so an
`exported` selection can re-export a project-borne entry the same
way as a hand-registered one); producers validate their own
manifests in their own CI.

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

### `compose`, `resolve`, `callFlake`, `partitionExtraInputs`

Keyed composition (`compose`), the layered ecosystem-source
resolver (`resolve`), the flake caller (`callFlake { src, inputs }`:
a flake's outputs function applied to inputs given as values,
fetching nothing; the flake-parts integration instantiates
flake-parts through it) and the read-only-eval-safe partition
extra-inputs loader, re-exposed from caisson-core. See
[How `lib` is composed](../deep-dives/how-lib-is-composed.md) and
caisson-core's own documentation.

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
`caisson/default` for the `flake` class is caisson's contribution to
the default default: it imports `caisson/nixpkgs` below.

### `modules.flake."caisson/nixpkgs"`, `modules.flake."caisson/nixpkgs-interface"`

- **Source:** `modules/flake/nixpkgs/`,
  `modules/flake/nixpkgs-interface/`

The nixpkgs integration's flake modules. `nixpkgs-interface` declares
only the overlay registry, `caisson.nixpkgs.overlays.all`: an attrset
of named overlay-producing functions (each takes the flake's
`configName` and returns an overlay; `mkPackagesOverlay` and
`mkPolyfillOverlay` below build them). Registering an overlay does
nothing by itself; a sibling flake module imports the interface to
make an overlay available and leaves selection to the consumer.

`nixpkgs` imports the interface and adds the package-set machinery,
the `caisson.nixpkgs.*` options:

- `pkgSets.<name>`: a package-set definition: `pkgFunction` (a
  nixpkgs-style entry point, e.g. `import inputs.nixpkgs`) and
  `overlayImports` (a selection function from the registry to the
  overlays to apply, default all). Each set is reified per system and
  handed to `perSystem` modules as the `pkgSets` argument;
  `pkgSets.pkgs` also becomes the default `perSystem` `pkgs`.
- `config`: the nixpkgs config applied to every generated package set.
- `overlays.exported` and `overlays.export.enabled`: the selection
  from the registry published as the flake's `overlays` output.
- `pkgs.export.enabled`, `packages.export.enabled`: whether to export
  `legacyPackages`, and the flake's own package scope
  (`pkgs.<configName>`) as `packages`.

### `integrations`

- **Source:** `lib-overlays/integrations/default.nix`

What an integration is written from, the functions every integration
overlay shares; each integration imports this overlay by key, so
composing any integration composes it, and reads the functions
through `final`. When `mkIntegration` generates integrations from
declarations, these are its parts.

- `checkArgs : { context, accepted, hints?, open? } -> args -> args`:
  the closed signature of an entry point; refuses an argument outside
  `accepted` with a message naming the caisson argument to use (from
  `hints`) or the `WithEcosystemArgs` twin (`open`).
- `resolveEcosystemSrc : { name, context } -> { explicit?, manifest? } -> src`:
  the layered ecosystem-source resolution with the miss interpreted
  (see [Ecosystem sources](../concepts/ecosystem-sources.md)).
- `coreModules : registry -> listOf module`,
  `defaultModuleImports : registry -> listOf module`: every entry of a
  class registry named `core` (the framework module of the class) and
  every entry named `default` (the default default).

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
(`libOverlays.<ecosystem>`) and available as a keyed entry via
`lib.composition.entriesFor`. Composing one contributes its
`lib.caisson.<ecosystem>` namespace, documented below (the flake-parts
integration also contributes the `lib.flake-parts` mirror of
the flake-parts library, instantiated over the composed lib). Each
entry point takes its ecosystem as an `ecosystemSrc` argument, and
the integrations pin nothing themselves, flake-parts included.

An adapter's ecosystem source resolves in layers: the explicit
`ecosystemSrc` argument first, then the composition's declared
`defaultEcosystemSrc.<name>` (an mkLib argument, carried by the
manifest), then the entry named exactly `<name>` in the `inputs`
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
- `configModule`: the configuration's own top-level module, always a
  single module (compose several with `imports`); the framework's
  selected class modules are applied beside it.
- `specialArgs`: extra module arguments; the one name on every entry
  point, translated to the evaluator's own spelling where it differs
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
  them; nothing else is forwarded, and an unknown argument is an
  error naming the caisson argument to use where one exists. That
  keeps an evaluator argument from being silently overwritten
  (`modules`), silently dropped (anything the minimal evaluator does
  not take), or surfacing as a conflict inside the evaluator
  (`pkgs` beside the framework's `nixpkgs.pkgs`).
- The evaluator's own surface is reachable, deliberately, through
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
caisson is one), and later the layer that gathers child
configurations.

- `mkModule : freeformModule -> module`: the registration form for
  structural modules.
- `mkConfiguration`:

```
mkConfiguration :
  { configModule  : module                                  # structural class
  , moduleImports ? (every entry named default)
                  : attrsOf module -> listOf module          # selection from the structural class registry
  , name          ? null : nullOr string                    # default for caisson.configInfo.configName
  , specialArgs   ? { }
  , pkgSets       ? null : attrs                            # the pkgSets special argument
  } -> { value : config; outputs : { exports : attrs } }
```

Evaluates the framework module (every `core` of the class, the one of
caisson read through the integration's closure), the selected
structural modules and the config module with `evalModules` over the
composed library. `value` is
the evaluated configuration; `outputs.exports` is `caisson.exports`,
the `lib`, `libOverlays` and `modules` the selectors chose.

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
  , moduleImports ? (every entry named default)
                  : attrsOf module -> listOf module          # selection from the flake class registry
  , name          ? null : nullOr string                    # rev-independent module identity
  , specialArgs   ? { }                                     # beside `lib`, the composed library
  , pkgSets       ? null                                    # the `pkgSets` special argument
  } -> flakeOutputs
```

  Builds final flake outputs via `flake-parts` using the composed
  `lib`: the flake's `inputs` come from `lib.caisson-core.libManifest`
  (so `mkConfiguration` requires a manifest-carrying, mkLib-built
  composition), and `moduleImports` selects over the `flake` class
  of `lib.caisson-core.modules`, the same registry every adapter
  selects from, so modules arriving by local registration, overlay
  contribution, or consumed project are all selectable. flake-parts
  itself resolves like every ecosystem, from `ecosystemSrc`,
  `defaultEcosystemSrc.flake-parts` or the input named `flake-parts`,
  and is instantiated over the composed library. `name` sets
  flake-parts' `moduleLocation` (so exported modules deduplicate
  across revs) and defaults `caisson.configInfo.configName`.
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
  moduleImports?, specialArgs?, osConfig?, check?, minimal?,
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

### `caisson.colmena` (module class `colmena`)

- **Source:** `lib-overlays/colmena/default.nix`
- `mkModule : freeformModule -> module`: class-bound `mkModule` for
  hive modules.
- `mkConfiguration : { ecosystemSrc, configModule, moduleImports?,
  specialArgs?, pkgSets? } -> hive`: evaluates the hive module with
  the selected colmena-class modules and projects it onto colmena's
  hive schema (`__schema`, `nodes`, `toplevel`, `deploymentConfig`,
  `evalSelected`, ...), the attributes colmena's binary reads. The
  hive module declares `meta` (`name`, `description`, `machinesFile`,
  `allowApplyAll`) and `nodes.<name>`, and receives
  `mkNixosConfiguration` as a module argument, closed over the hive's
  colmena source: `caisson.nixos.mkConfiguration`'s signature and
  composition over the host's module plus colmena's public node
  modules (`deploymentOptions`, `keyChownModule`, `keyServiceModule`,
  `assertionModule`). Its `ecosystemSrc` is nixpkgs, as for any NixOS
  configuration; set `deployment.*` in the host's module. A node is an
  ordinary NixOS configuration that also declares `deployment`; a
  consumer that exports it as `nixosConfigurations.<host>` reads it
  back from `hive.nodes`, one evaluation for `nixos-rebuild` and
  `colmena apply`. The schema version is asserted against the
  ecosystem source's own `makeHive`, so a colmena revision that moves
  it fails at evaluation; a node that did not come from
  `mkNixosConfiguration` is refused. `pkgSets` on the hive only serves
  `colmena eval` (`introspect`). `mkNixosConfigurationWithEcosystemArgs`
  is the node constructor's twin, also a module argument. Every node
  receives colmena's `name` and `nodes` special arguments (the latter
  the whole hive, lazily, for cross-node references), so a module
  written for colmena's own evaluator works unchanged. Node names are
  free: `meta`, `defaults` and `network`, reserved in colmena's flat
  hive, are ordinary names under `nodes`. The only constraint is
  colmena's `--on` filter grammar: a name containing a comma, starting
  with `@`, or empty could never be selected, and is refused at hive
  evaluation.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the schema attrset itself.

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
