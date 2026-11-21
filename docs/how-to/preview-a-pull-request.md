# Preview a pull request

This guide shows how to see what a pull request would change on the site before it is merged. The preview is a
dry run: nothing on the site is changed.

## Add a workflow for pull requests

Create `.github/workflows/preview.yml` with the same inputs as your deployment, and add `dry-run: true`.

```yaml
name: Preview the deployment

on:
  pull_request:
    paths:
      - theme/**
      - tags/**
      - pages/**
      - posts/**

permissions:
  contents: read

jobs:
  preview:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: Gijsreyn/ghost-deploy-action@v1
        with:
          api-url: ${{ secrets.GHOST_ADMIN_API_URL }}
          api-key: ${{ secrets.GHOST_ADMIN_API_KEY }}
          theme: theme
          tags: tags
          pages: pages
          posts: posts
          delete: true
          dry-run: true
```

Keep `delete: true` when your deployment has it. The preview then also lists what would be removed.

## Read the result

Open the pull request, choose **Checks**, and open the run **Preview the deployment**. The summary says what a
deployment of the merged result would do:

```text
This was a dry run for My site. Nothing was changed. A real run would do this:

To create: 1, to update: 1, to remove: 0. Unchanged: 14.

Kind  Action        Name            Slug      File
Post  Would create  A new post      new-post  posts/2026-11-28-new-post/index.md
Tag   Would update  Release notes   releases  tags/releases.md
```

A file that the site refuses, such as one with a field that does not exist, makes the preview fail with the name
of the file. That is the other use of a preview: a mistake shows before the merge.

## Use the result in a later step

The outputs of the action count what would be done. This step fails a pull request that would remove something:

```yaml
      - uses: Gijsreyn/ghost-deploy-action@v1
        id: preview
        with:
          api-url: ${{ secrets.GHOST_ADMIN_API_URL }}
          api-key: ${{ secrets.GHOST_ADMIN_API_KEY }}
          posts: posts
          delete: true
          dry-run: true

      - if: steps.preview.outputs.removed != '0'
        run: |
          echo "This pull request removes content from the site."
          exit 1
```

## Pull requests from forks

GitHub does not give the secrets of a repository to a pull request from a fork. The action then stops with this
message:

```text
The input api-key is empty. Give it the Admin API key of the site, as a secret. A pull request from a fork does
not get the secrets of a repository, so it cannot run this action.
```

The event `pull_request_target` does give a run the secrets. It also runs with the rights of your repository
while it handles files from somebody else. Read
[what GitHub says about that event](https://docs.github.com/en/actions/reference/security/secure-use) before you
use it for a preview.

## Related

- [Delete removed content](delete-removed-content.md) explains what `delete: true` compares.
- The [reference](../reference.md#outputs) lists the outputs.
