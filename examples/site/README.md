# An example site

This folder is a complete, small site for the action
[Deploy to Ghost](https://github.com/Gijsreyn/ghost-deploy-action). Copy it into a repository of your own to
deploy a custom theme, a tag, a page and a post to a Ghost site.

The [getting-started guide](../../docs/getting-started.md) walks through it step by step.

## What is in it

| Path | What it is |
| --- | --- |
| `.github/workflows/deploy.yml` | Deploys on every push to `main`, and removes what a push removed |
| `.github/workflows/preview.yml` | Shows for every pull request what merging would change |
| `theme/` | A small custom theme: five templates and one stylesheet, without a build step |
| `tags/deploy-example.md` | A tag, with its colour and its description |
| `pages/about-this-example/index.md` | A page |
| `posts/2026-11-21-hello-from-a-repository/` | A post, with a picture next to it |

The post and the page are drafts, so nothing is shown to visitors until you publish them. The theme is different:
it replaces the theme of the site as soon as it is deployed. Take the line `theme: theme` out of both workflows
to keep the theme that the site has.

The workflows do nothing while they are in this folder. GitHub only runs workflows from the folder
`.github/workflows` at the root of a repository, which is where they are once you have copied the site.

## What it needs

Two secrets in the repository that you copy it to:

- `GHOST_ADMIN_API_URL`: the address of your site.
- `GHOST_ADMIN_API_KEY`: the Admin API key of a custom integration of your site.

## How it is tested

The example is deployed to a real Ghost site by the tests of this action, exactly as it is. A theme or a file
that Ghost would refuse fails those tests.
