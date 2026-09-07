# Testing

The conventions and tools for testing a caisson flake, as used by this
repository's own test suite (`tests/` here is a worked example of all
of it).

## Unit tests

`tests/unit/` holds pure evaluation tests, wired into `checks`; this
repository runs them with nix-unit. Anything that can be asserted by
evaluating `lib` belongs here.

## Integration tests: consumption from the outside

The strongest test of a flake framework is what a consumer experiences,
so integration tests are **nested flakes** under `tests/integration/`
that take the project as an input and assert that composition behaves
as documented. They are written as completely normal flakes:

```nix
{
  inputs = {
    # Standalone equivalent (without shared deps infrastructure):
    #   nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #   flake-parts.url = "github:hercules-ci/flake-parts";
    #   parent.url = "github:example/my-flake";

    deps.url = "path:../../dependencies";
    parent.url = "path:../../..";

    nixpkgs.follows = "deps/nixpkgs";
    flake-parts.follows = "deps/flake-parts";
  };

  outputs = inputs@{ parent, ... }: {
    # consume `parent` the way any downstream flake would
  };
}
```

## tests/dependencies

A small lock-bearing flake whose only job is to pin the inputs that
tests (and formatters) need, so the main `flake.lock` stays free of
test-only pins. `partitionExtraInputs` feeds it to the checks
partition.

## Evaluating the nested flakes

Hand-threading a nested flake's inputs (the recursive self fixpoint,
the resolved input graph) is the genuinely hard part, and
`callConsumerFlake` owns it. In the parent's checks:

```nix
let
  consumerPool = {
    inherit (inputs) flake-parts nixpkgs;
    deps = inputs.self;      # the tests/dependencies flake
    parent = self;           # the flake under test
  };

  minimalConsumer = lib.my-flake.callConsumerFlake {
    path = self.outPath + "/tests/integration/minimal-consumer";
    pool = consumerPool;
  };
in
{
  checks = minimalConsumer.checks.${system};
}
```

The nested flake's declared inputs resolve by name (`overrides` first,
then `follows` chains, then the pool), and an unresolvable input throws
an error naming it and what to do. The contract is deliberately
explicit, in the same spirit as closed inputs: nothing is fetched, no
lock is read, and you supply exactly the input graph you mean the test
to see. One consumer's outputs can feed another's `overrides`, so
chains of consumers (a flake consuming a flake that consumes yours) are
plain data flow.

See [`callConsumerFlake`](reference/lib.md#callconsumerflake) for the
full signature.

## Gating evaluation cost

Beyond correctness, `checks` can gate what evaluation *costs*; see
[Evaluation weight](eval-weight.md).
