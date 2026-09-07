# nix-caisson.github.io

The website for the [caisson](https://github.com/nix-caisson/caisson)
family, published at <https://nix-caisson.github.io/>.

| Path | Content |
|---|---|
| `site/` | The landing page (static HTML and CSS) and the files the built book is served next to |
| `docs/` | The mdBook source for the documentation, served at `/docs/` |
| `theme/` | The mdBook theme overrides |
| `assets/brand/` | Brand sources: emblem, wordmark, favicon, and social card, with the palette and usage rules; published at `/assets/brand/` |

The documentation describes the caisson revision it was last checked
against, and the framework repository does not carry it, so a change
in caisson that affects the documented behaviour is followed by a
change here.

## Building locally

```
nix run 'nixpkgs#mdbook' -- serve
```

builds the book into `site/docs/` and serves it. Open the landing
page from `site/index.html` directly; it links to the book by
relative path.

## Publishing

Every push to `main` builds the book and deploys `site/` to GitHub
Pages through `.github/workflows/pages.yml`.
