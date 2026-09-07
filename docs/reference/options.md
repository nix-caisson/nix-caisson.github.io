# Module Options Reference

This reference documents the caisson framework's module options. All descriptions are sourced from the Nix-native `description` fields in the module code.

For `lib.caisson` functions, see [Library Reference](./lib.md).

## Options

### `caisson.configInfo.configName`

- **Type:** `nullOr str`
- **Default:** `null`
- **Source:** `modules/flake-parts/default/caisson/configInfo.nix`

The canonical name of this flake. Used in doc/version strings and as a default namespace name for exports. Some export options (e.g. `caisson.lib.export.enabled`) require this to be set.

### `caisson.lib.export.enabled`

- **Type:** `bool`
- **Default:** `false`
- **Source:** `modules/flake-parts/default/caisson/lib.nix`

Whether to enable lib export. When enabled, publishes the selection made by `caisson.lib.exported` as `flake.lib`.

### `caisson.lib.exported`

- **Type:** `function -> lazyAttrsOf raw`
- **Default:** `composedLib: composedLib.${configName}` (requires `configInfo.configName`)
- **Source:** `modules/flake-parts/default/caisson/lib.nix`

Function that selects which parts of the composed library to publish as the flake's `lib` output. The default exports the flake's own namespace; caisson itself sets `composedLib: { inherit (composedLib) caisson caisson-core; }` so flake-level and composed-level addresses match.

### `caisson.manifest`

- **Type:** `caisson.types.manifest` (read-only)
- **Default:** the composed library's `caisson-core.manifest`
- **Source:** `modules/flake-parts/core/caisson/manifest.nix`

The composition's manifest: `inputs`, `ecosystems`, and `projects` as given to `mkLib`, plus the registered `libOverlays` and `modules` dictionaries (project entries under `<project>/<name>`, locals winning). Reading it type-checks the manifest; the `flake.modules` and `flake.libOverlays` projections are drawn from it.

### `caisson.modules`

- **Type:** `attrsOf (submodule { export.enabled; exported; })`
- **Default:** `{}`
- **Source:** `modules/flake-parts/core/caisson/modules.nix`

Export settings for each registered module class. Each class key defines:

- `export.enabled` (`bool`, default `true`)
- `exported` (`function -> attrsOf deferredModule`, default `modules: { }`)

The selected modules are published under `flake.modules.<class>`. For the `"flake"`
class specifically, the same modules are also mirrored to `flake.flakeModules`.

### `caisson.modules.<class>.export.enabled`

- **Type:** `bool`
- **Default:** `true`
- **Source:** `modules/flake-parts/core/caisson/modules.nix`

Whether to export modules for a given class.

### `caisson.modules.<class>.exported`

- **Type:** `function -> attrsOf deferredModule`
- **Default:** `modules: { }`
- **Source:** `modules/flake-parts/core/caisson/modules.nix`

Function that selects which modules in a class to publish under `flake.modules.<class>`.

### `caisson.libOverlays.export.enabled`

- **Type:** `bool`
- **Default:** `true`
- **Source:** `modules/flake-parts/core/caisson/libOverlays.nix`

Whether to enable lib overlay export. When enabled, publishes the overlays selected by `caisson.libOverlays.exported` under `flake.libOverlays`.

### `caisson.libOverlays.exported`

- **Type:** `function -> attrsOf libOverlay`
- **Default:** `overlays: { }`
- **Source:** `modules/flake-parts/core/caisson/libOverlays.nix`

Function that selects which registered library overlays to export as flake outputs. Receives the set of overlays registered via `mkLib` and returns the subset to publish under `flake.libOverlays`.
