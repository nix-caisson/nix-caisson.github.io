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

- **Source:** caisson-core's `lib/` (`lifecycle.nix` for the
  machinery, `default.nix` for keyed composition and the resolver)

### `mkLib`

```
mkLib :
  { inputs            : attrs                              # the defining flake's inputs
  , baseLib           : lib                                # the base library, a plain argument
  , modules           ? (lib: { })
                      : lib -> attrsOf (attrsOf module)    # class -> name -> module
  , libOverlays       ? (mkLibOverlay: { })
                      : (freeformOverlay -> libOverlay) -> attrsOf libOverlay
  , libOverlayImports ? builtins.attrValues
                      : attrsOf libOverlay -> listOf libOverlay
  , ecosystems        ? { } : attrs                        # declared ecosystem sources, by exact name
  , projects          ? { } : attrs                        # consumed upstream contributions, by project name
  } -> lib
```

Builds a composed library by extending `baseLib` with the
`caisson-core` namespace injection and the selected registered
overlays, then two synthetic overlays: the local module registrations
(so local names win over overlay-borne contributions) and the
manifest. Nothing is looked up by input name: `baseLib` is a plain
argument, and the `caisson-core.mkLib` found in a composed library
defaults it to that composition's own base.

- `modules` receives the composed `lib` (usable through the fixpoint)
  and returns the class-keyed registration, typically built with
  helpers like `lib.caisson-core.mkModule` and
  `lib.caisson.flake-parts.mkModule`.
- `libOverlays` receives the input-closed `mkLibOverlay` helper and
  returns the registered overlays. Both arguments take exactly the
  function shape shown; passing anything else is an error.
- `libOverlayImports` selects which registered overlays apply to this
  flake's own `lib`; registration also feeds export, so the two can
  differ.
- `ecosystems` declares default ecosystem sources for this
  composition (`{ nixpkgs = inputs.nixpkgs; ... }`), keyed by the
  exact names the integrations resolve. mkLib only captures them into
  the manifest; the integrations interpret them.
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

### `mkLibOverlay`

```
mkLibOverlay : freeformOverlay -> libOverlay

freeformOverlay = path | (closure -> { imports ? listOf libOverlay
                                     ; overlay : overlayFn })
closure = { closure-inputs     : attrs
          ; mkLibOverlay       : freeformOverlay -> libOverlay
          ; mkModule           : string -> freeformModule -> module
          ; contributeModules  : attrs -> attrsOf (attrsOf module) -> attrs
          }
```

Applies the closure attrset to an overlay given as a function or a path
to one, and normalizes the result: the built `libOverlay` always carries
both keys, with `imports` defaulted to `[ ]`. Already-built overlays are
registered directly rather than wrapped.

The closure's `mkModule` is bound to the defining composition, so
modules contributed by an overlay close over the definer's inputs and
library. `contributeModules prev { <class>.<name> = module; }`
returns the `caisson-core.modules` registry merge for the overlay's
output (merge its result with any namespace contributions); it
is passed through the closure rather than the composed library because
an overlay's output attribute names must not depend on `final`.
Qualify contributed names with your project prefix
(`my-flake/my-service`); the composing flake's local registrations
apply last and win over same-named contributions. See
[Module classes](../concepts/module-classes.md) for the ways
modules enter the registry.

### `mkModule`

```
mkModule : string -> freeformModule -> module

freeformModule = path | (closure -> module)
closure = { closure-inputs        : attrs    # the defining flake's inputs
          ; closure-lib           : lib      # the defining flake's composed lib
          ; closure-self-modules  : attrs    # the defining flake's registrations
                                             #   in the same class
          ; mkModule              : freeformModule -> module   # bound to the class
          }
```

Factory for class-specific module normalizers. Given a class name, returns a normalizer that applies the closure attrset to a module given as a function or a path to one; the module takes the closure as its first arg list (`{ ... }:` when unused). Plain modules are imported/registered directly rather than wrapped. Path modules gain `_file` and a path-based dedup `key`.

The `mkModule` closure member is bound to the same class, so nested module composition stays in that class.

### `modules`

```
modules : attrsOf (attrsOf module)    # class -> name -> module
```

The class-keyed module registry of this composition: the flake's own
registrations merged with every overlay-borne contribution, locals
winning on name conflicts. Integration adapters read their class from
here (`caisson-core.modules.<class>`) as the default module
selection.

### `manifest`

```
manifest : { inputs : attrs; modules : attrsOf (attrsOf module);
             libOverlays : attrsOf libOverlay; ecosystems : attrs;
             projects : attrs }
```

The composition's self-description, injected as its final overlay.
`inputs`, `ecosystems`, and `projects` are the `mkLib` arguments as
given; `libOverlays` and `modules` are the registered dictionaries,
so consumed projects' entries appear under `<project>/<name>` beside
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

### `compose`, `resolve`, `partitionExtraInputs`

Keyed composition (`compose`), the layered ecosystem-source
resolver (`resolve`), and the read-only-eval-safe partition
extra-inputs loader, re-exposed from caisson-core. See
[How `lib` is composed](../deep-dives/how-lib-is-composed.md) and
caisson-core's own documentation.

## The caisson namespace

`lib.caisson` holds one namespace per integration target
(`lib.caisson.flake-parts`, `lib.caisson.nixos`, and so on; see
[Integration namespaces](#integration-namespaces)), plus the
pkgs-dependent tooling documented at the end of this section.
caisson's registered flake modules are listed here too.

### `modules.flake."caisson/partitions"`

flake-parts' partitions module, registered and exported in caisson's
flake class so a consumer selects it from the registry
(`moduleImports = modules: [ modules."caisson/partitions" ... ]`)
rather than declaring a flake-parts input for it.

### `modules.flake."caisson/nixpkgs"`, `modules.flake."caisson/nixpkgs-interface"`

- **Source:** `modules/flake-parts/nixpkgs/`,
  `modules/flake-parts/nixpkgs-interface/`

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
flake-parts' own library). Each entry
point takes its ecosystem as an `ecosystemSrc` argument, and
the integrations pin nothing themselves, with one exception:
flake-parts, whose pin is caisson's own hidden input.

An adapter's ecosystem source resolves in layers: the explicit
`ecosystemSrc` argument first, then the composition's declared
`ecosystems.<name>` (an mkLib argument, carried by the
manifest), then an input of the composing flake named exactly
`<name>`. The names are `nixpkgs` (the nixos integration),
`home-manager`, `colmena`, `terranix`, and `system-manager`. A full
miss throws at the adapter, naming the three places; a composition
built without mkLib (no manifest) accepts only the explicit argument.
Common conventions:

- Every integration exports `mkConfiguration` (evaluate the target's
  module system with the selected class modules), and every
  integration with a module class of its own also exports `mkModule`
  (the class-bound form of `caisson-core.mkModule`); colmena has
  none, its nodes being NixOS configurations. Target-specific
  variants and helpers sit beside them under the same namespace.
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
  the `mkConfigurationWithEcosystemArgs` twin of each entry point (nixos
  also has `mkConfigurationMinimalWithEcosystemArgs`). It takes the same
  arguments plus `ecosystemArgs`, an attrset merged over the composed
  evaluator call verbatim, last: anything the evaluator accepts can
  be set or replaced there, including what caisson composed
  (`modules`, `specialArgs`, the package set). The name is the
  contract: from there on the evaluator's semantics are the caller's
  to know.
- `moduleImports`: a selection function over the corresponding class
  registry (`lib.caisson-core.modules.<class>`), returning the list
  of modules to apply; the default, `builtins.attrValues`, applies
  all registered modules. The list shape matches `libOverlayImports`;
  for order-sensitive list-typed options, prefer `mkOrder` over
  selection position.
- Framework-provided special arguments compose first; the caller's
  win on conflict.

### `caisson.flake-parts` (module class `flake`)

- **Source:** `lib-overlays/flake-parts/default.nix`
- `mkModule : freeformModule -> module`: class-bound `mkModule`, the
  convenience form of `caisson-core.mkModule "flake"` for flake-parts
  modules.
- `mkConfiguration`:

```
mkConfiguration :
  { configModule  : module                                  # flake class
  , moduleImports ? builtins.attrValues
                  : attrsOf module -> listOf module          # selection from the flake class registry
  , name          ? null : nullOr string                    # rev-independent module identity
  , specialArgs   ? { }                                     # beside `lib`, the composed library
  , pkgSets       ? null                                    # the `pkgSets` special argument
  } -> flakeOutputs
```

  Builds final flake outputs via `flake-parts` using the composed
  `lib`: the flake's `inputs` come from `lib.caisson-core.manifest`
  (so `mkConfiguration` requires a manifest-carrying, mkLib-built
  composition), and `moduleImports` selects over the `flake` class
  of `lib.caisson-core.modules`, the same registry every adapter
  selects from, so modules arriving by local registration, overlay
  contribution, or consumed project are all selectable. The
  flake-parts pin is caisson's own, closed over at the integration's
  definition; consumers declare no flake-parts input. `name` sets
  flake-parts' `moduleLocation` (so exported modules deduplicate
  across revs) and defaults `caisson.configInfo.configName`.
- `types.libOverlay`: a module-system option type for built library
  overlays. Its `check` verifies the structure recursively: an
  attrset with an `overlay` function and a (possibly absent)
  `imports` list whose entries are themselves valid `libOverlay`s.
  Used by options that carry overlays, such as
  `caisson.libOverlays.exported`.
- `types.manifest`: a structural option type for the caisson-core
  manifest (`{ inputs, modules, libOverlays }`). The export-side
  check: the core flake-parts module reads `lib.caisson-core.manifest`
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
- `mkConfigurationMinimal : { ecosystemSrc, pkgSets, configModule,
  moduleImports?, specialArgs?, prefix? }`: bare `evalModules` from
  `<ecosystemSrc>/nixos/lib`; no NixOS base modules, so the config
  module declares any options it uses, and the package set arrives as
  the `pkgs` module argument rather than through `nixpkgs.pkgs`.
- `mkConfigurationWithEcosystemArgs`, `mkConfigurationMinimalWithEcosystemArgs`:
  the twins with `ecosystemArgs` (see the conventions above);
  eval-config's `baseModules` is one of the arguments reachable that
  way.

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
- `mkConfigurationMinimal`: `mkConfiguration` with
  `minimal = true`.
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

### `caisson.colmena`

- **Source:** `lib-overlays/colmena/default.nix`
- `mkConfiguration : { ecosystemSrc, pkgSets, configModule,
  moduleImports?, specialArgs?, meta?, nodes? } -> hive`:
  `ecosystemSrc.lib.makeHive` over a hive whose nodes are NixOS
  configurations composed exactly as `caisson.nixos.mkConfiguration`
  composes them (one shared definition): the selected nixos-class
  modules, the hive-wide `configModule` and the framework's
  package-set module are the hive's `defaults`; each
  `nodes.<name> = { configModule, deployment? }` adds the node's own
  module and its `deployment` settings. Colmena is handed the package
  set's identity (`path`, `lib`, `stdenv`) with empty `overlays` and
  `config`, so the nodes take the instance through `nixpkgs.pkgs`
  like every other caisson NixOS evaluation. A node's toplevel is the
  derivation `caisson.nixos.mkConfiguration` builds from the same
  modules. `meta` carries colmena's hive metadata (`name`,
  `description`, `machinesFile`, `allowApplyAll`); its `nixpkgs`,
  `specialArgs` and per-node forms are composed by the integration and
  refused. There is no colmena module class: colmena modules are
  nixos-class modules.
- `mkConfigurationWithEcosystemArgs`: the twin with `ecosystemArgs`,
  merged over the hive attrset itself (`meta.nodeNixpkgs` and
  `meta.nodeSpecialArgs` live there).

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
