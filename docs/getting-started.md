# Getting started

A step-by-step first flake: create it, add a library overlay, register
a module, use an integration, then consume your flake from a second
one. The finished shape of each step also exists as a working flake
under `examples/literate-flake/` in the repository, with commentary.

## 1. A minimal caisson flake

Create a directory with this `flake.nix`:

```nix
{
  description = "my first caisson flake";

  inputs = {
    caisson.url = "github:nix-caisson/caisson";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs =
    inputs@{ caisson, ... }:
    let
      core = caisson.lib.caisson-core;
      lib = core.mkLib {
        inherit inputs;
        systems = [ "x86_64-linux" ];
        projects = {
          inherit caisson;
        };
        configs = core.mkModules ./configs;
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      name = "my-flake";
      configModule = lib.caisson-core.configs.flake.my-flake;
    };
}
```

`caisson-core.mkLib` composes a library: nixpkgs' lib, the machinery
under `lib.caisson-core`, and the overlays you register. `systems`,
the platforms the flake builds for, is declared here; flake-parts
reads it from the composition. Consuming
caisson as a project registers everything it exports, its
integrations included, which contributes `lib.caisson` (one namespace per integration
target); `lib.caisson.flake-parts.mkConfiguration` then evaluates
flake-parts with that library and your config module. flake-parts
comes from the `flake-parts` input of the flake, like every ecosystem
caisson wraps: the integration calls that source with the composed
library, so the evaluation runs on the same nixpkgs lib the rest of
the composition does.

The config module is the flake's own top-level configuration, and it
is registered rather than named by path: `core.mkModules ./configs`
reads `configs/<class>/<name>/default.nix` into the `configs`
registration, so the configuration comes back as
`lib.caisson-core.configs.flake.my-flake`. Create
`configs/flake/my-flake/default.nix`:

```nix
{ ... }:
{ pkgs, ... }:
{
  caisson.configInfo.configName = "my-flake";

  perSystem =
    { pkgs, ... }:
    {
      packages.default = pkgs.hello;
    };
}
```

Note the two argument lists: every registered file takes the closure
attrset (`{ closure-inputs, ... }`) first, then its ordinary module
arguments. That convention is the subject of
[Closed inputs](concepts/closed-inputs.md).

Check it:

```sh
nix flake check
nix build
```

## 2. Add a library overlay

An overlay contributes a namespace to the composed library. Create
`lib-overlays/default/default.nix`:

```nix
{ ... }:
{
  imports = [ ];
  overlay = final: prev: {
    my-flake = (prev.my-flake or { }) // {
      greet = name: "hello, ${name}";
    };
  };
}
```

Register it in `flake.nix` and export it, and turn on the lib export
in the config module. `core.mkLibOverlays ./lib-overlays` reads
`lib-overlays/<name>/default.nix` into the `libOverlays` registration:

```nix
      lib = core.mkLib {
        inherit inputs;
        projects = {
          inherit caisson;
        };
        configs = core.mkModules ./configs;
        libOverlays = core.mkLibOverlays ./lib-overlays;
      };
```

```nix
  caisson = {
    configInfo.configName = "my-flake";
    libOverlays.exported = libOverlays: { inherit (libOverlays) default; };
    lib.export.enabled = true;
  };
```

Now `lib.my-flake.greet` is available everywhere the composed library
flows: in the config module, in registered modules, and (with the
export enabled) to consumers as `flake.lib`. Use it in `perSystem`:

```nix
      packages.default = pkgs.writeText "greeting" (lib.my-flake.greet "Nix");
```

## 3. Register a module

Modules are class-keyed: `flake` modules feed flake-parts, and
integration classes (`nixos`, `homeManager`, ...) feed their module
systems. `core.mkModules ./modules` reads
`modules/<class>/<name>/default.nix` into the registration, the
first directory level being the class; register a flake-class module
by creating its directory:

```nix
      lib = core.mkLib {
        inherit inputs;
        projects = {
          inherit caisson;
        };
        modules = core.mkModules ./modules;
        configs = core.mkModules ./configs;
        libOverlays = core.mkLibOverlays ./lib-overlays;
      };
```

`modules/flake/default/default.nix`:

```nix
{ ... }:
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShell { packages = [ pkgs.nixfmt ]; };
    };
}
```

`mkConfiguration` applies the selected flake-class modules alongside the
config module: `moduleImports` returns the list to apply, like
`libOverlayImports`, and when it is omitted every registered entry
named `default` applies, here this flake's `default` and
`caisson/default` (the default module of caisson, which carries the
nixpkgs integration's module layer). The entries named `core` apply
to every evaluation of the class regardless.
[Module classes](concepts/module-classes.md) covers registration,
selection, and export.

## 4. Use an integration

Integrations bring the same conventions to other module ecosystems
and take their ecosystem as an explicit `ecosystemSrc`. A NixOS system,
in the config module's `perSystem` or at the top level:

```nix
  flake.nixosConfigurations.example = lib.caisson.nixos.mkConfiguration {
    ecosystemSrc = inputs.nixpkgs;
    pkgSets.pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
    configModule =
      { ... }:
      {
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        system.stateVersion = "25.05";
      };
  };
```

Instead of passing `ecosystemSrc` at every call, the `mkLib` call can
declare a default (`defaultEcosystemSrc.nixpkgs = inputs.nixpkgs`) and
the argument can be dropped; an explicit argument still wins, and the
entry named exactly `nixpkgs` in the `inputs` passed to `mkLib` is the
last fallback.

With caisson consumed as a project, its integration overlays are
already registered and applied, so `caisson.nixos` is present. To
compose only some of them, keep the project registration and select
per item over the combined dictionary:

```nix
        libOverlayImports = overlays: [
          overlays."caisson/flake-parts"
          overlays."caisson/nixos"
          overlays.default
        ];
```

Registering a single overlay by hand
(`nixos = caisson.libOverlays.nixos`) remains the way to cherry-pick
or rename one. The [library reference](reference/lib.md) documents
the integration namespaces.

## 5. Consume your flake from another flake

A consumer registers your exported overlay the same way:

```nix
{
  inputs = {
    caisson.url = "github:nix-caisson/caisson";
    my-flake.url = "github:you/my-flake";
  };

  outputs =
    inputs@{ caisson, my-flake, ... }:
    let
      core = caisson.lib.caisson-core;
      lib = core.mkLib {
        inherit inputs;
        projects = {
          inherit caisson my-flake;
        };
        configs = core.mkModules ./configs;
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      name = "consumer";
      configModule = lib.caisson-core.configs.flake.consumer;
    };
}
```

The consumer's composed library now has `lib.my-flake.greet`: the
project registration brings in the overlays you exported, each
overlay's `imports` chain guarantees anything it depends on composes
with it, and your exported modules land in the consumer's registry
under `my-flake/<name>`, selectable at each use site. Overlays that
contribute modules via `contributeModules` (see
[Module classes](concepts/module-classes.md)) deliver them the same
way. A consumer who wants only part of your project selects with
`libOverlayImports`, or registers single overlays from
`my-flake.libOverlays.<name>` by hand; the
`my-flake.modules.<class>.<name>` flake outputs remain for consumers
who import modules without composing anything.

## Where next

- [Closed inputs](concepts/closed-inputs.md), the convention every
  registered file follows.
- [How `lib` is composed](deep-dives/how-lib-is-composed.md): the
  whole composition pass, and composing with `caisson-core` directly.
- [Testing](./testing.md), including `callConsumerFlake` for testing
  consumer flakes without a push/lock cycle.
- [FAQ](faq.md) for the questions this page tends to raise.
