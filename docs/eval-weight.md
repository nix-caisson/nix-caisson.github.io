# Evaluation Weight

`lib.caisson.eval-weight` measures what an evaluation costs and can
gate that cost in `checks`, so a framework regression is caught by CI
rather than noticed as slowness later. This repository uses it to gate
its own overhead; the numbers quoted in these docs come from it.

## How it measures

A scenario runs a pinned Nix evaluator inside a derivation sandbox
against explicitly wired inputs and captures the evaluator's own
statistics. The deterministic counters (thunks, values, environments,
function and primop calls, total allocations) are reproducible for a
fixed lock set and Nix version, so they can be gated. CPU and
wall-clock time are machine-dependent, so they are always reported but
not gated.

Three semantic counters are derived from the same run, keyed to stable anchors in the
evaluated source rather than line numbers:

- `nixpkgsEvals`: full nixpkgs instantiations
- `nixpkgsLibEvals`: nixpkgs-lib bootstraps (distinct lib sources)
- `moduleSystemEvals`: `evalModules` runs, including submodules

These are gated **exactly**, with no growth allowance: one extra
nixpkgs instantiation *is* the regression.

## mkCheck

```nix
checks.eval-weight = lib.caisson.eval-weight.mkCheck {
  inherit pkgs;
  name = "my-flake";

  scenarios = {
    raw-flake-parts = {
      entry = self.outPath + "/tests/eval-weight/raw-flake-parts.nix";
      args = { /* store paths and system for the entry */ };
    };
    minimal-consumer = {
      entry = self.outPath + "/tests/eval-weight/minimal-consumer.nix";
      args = { /* ... */ };
    };
  };

  gates = [
    # framework overhead, isolated from ecosystem churn
    {
      name = "my-flake-overhead";
      minuend = "minimal-consumer";
      subtrahend = "raw-flake-parts";
    }
    # loose ceiling on the whole consumer
    {
      name = "minimal-consumer-total";
      scenario = "minimal-consumer";
      maxGrowth = 0.25;
    }
  ];

  baseline =
    builtins.fromJSON (builtins.readFile ./tests/eval-weight/baseline.json);
};
```

- **scenarios**: `entry` is a self-contained file imported inside the
  sandbox and applied to `args` (store paths arrive as absolute-path
  strings); the resulting value is forced strictly, so the entry decides
  exactly what evaluation gets measured. Entries that need to evaluate a
  flake import the shared `call-flake.nix` kernel from a store path in
  `args`, the same kernel under
  [`callConsumerFlake`](reference/lib.md#callconsumerflake).
- **gates**: one per scenario by default. A subtraction gate measures
  the *difference* between two scenarios, which is the important trick:
  a 2× regression in framework machinery is invisible in a
  whole-nixpkgs total but obvious in the delta.
- **baseline**: `null` runs in measure-only bootstrap mode: metrics
  are printed, including a paste-ready baseline, and the check passes.
  Commit the pasted baseline (this repository keeps it at
  `tests/eval-weight/baseline.json`) and subsequent runs gate against
  it: deterministic metrics may grow up to `maxGrowth` (10% by
  default; exact metrics not at all), and marked shrinkage logs a
  note suggesting the baseline be tightened.

## The workflow

1. Write an entry per scenario under `tests/eval-weight/`.
2. Run once with `baseline = null`; paste the printed baseline into
   `tests/eval-weight/baseline.json`.
3. Wire `mkCheck` into `checks` with the committed baseline.
4. When a gate fails, the report shows which metric moved and by how
   much; either fix the regression or, for intended changes, update
   the baseline in the same change, where review can see both.
