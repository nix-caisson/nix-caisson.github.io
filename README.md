# nix-caisson.github.io

The website for the [caisson](https://github.com/nix-caisson/caisson)
family, published at <https://nix-caisson.github.io/>.

| Path | Content |
|---|---|
| `site/` | The landing page (static HTML and CSS) and the files the built book is served next to |
| `docs/` | The mdBook source for the documentation, served at `/docs/` |
| `theme/` | The mdBook theme overrides |
| `assets/brand/` | Brand sources: emblem, wordmark, favicon, and social card, with the palette and usage rules; published at `/assets/brand/` |

`flake.nix`, `configs/` and `pkg-overlays/` make up the caisson flake
that builds the website as its `site` package. `tests/dependencies/`
pins the inputs of the checks and of the formatter.

The documentation describes the caisson revision it was last checked
against, and the framework repository does not carry it, so a change
in caisson that affects the documented behaviour is followed by a
change here.

## Building locally

```
nix build '.#site'
```

builds the website as Pages serves it into `result/`. The package
runs mdBook from the nixpkgs revision that `flake.lock` pins.

```
nix shell --inputs-from . 'nixpkgs#mdbook' -c mdbook serve
```

runs the same mdBook, builds the book into `site/docs/` and serves
it. Open the landing page from `site/index.html` directly; it links
to the book by relative path.

`nix flake check` builds the website and checks the formatting of the
Nix files. `nix fmt` formats them.

## Publishing

Every pull request and every push to `main` runs `nix flake check`
through `.github/workflows/check.yml`. Every push to `main` builds the
`site` package and deploys it to GitHub Pages through
`.github/workflows/pages.yml`.
