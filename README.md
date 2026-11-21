# Deploy to Ghost

A GitHub Action that keeps a [Ghost](https://ghost.org) site in line with a repository. It deploys a theme and
creates, updates and removes tags, pages and posts from Markdown files. Only what differs from the site is sent,
so it can run on every push.

```yaml
name: Deploy to Ghost

on:
  push:
    branches: [main]

jobs:
  deploy:
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
```

Every run ends with a summary on the page of the run. It lists what was created, updated and removed.

## What it does

- **Theme.** A folder or a zip file is uploaded and activated when the site does not show that theme yet.
- **Tags, pages and posts.** Each one is a Markdown file with its fields at the top. A file that differs from
  the site is sent. A picture next to a post or a page is uploaded once.
- **Removed files.** With `delete: true`, a post, page or tag is removed from the site when its file was removed
  from the repository. Content that never had a file is not touched.
- **Dry run.** With `dry-run: true` nothing is changed. The summary says what a real run would do, which makes a
  preview for a pull request.

A kind without an input is left alone. A repository with only a theme, or only posts, works the same way.

## Documentation

| You want to                                                  | Read                                                                    |
|--------------------------------------------------------------|-------------------------------------------------------------------------|
| Deploy a whole site for the first time, step by step         | [Getting started](docs/getting-started.md)                              |
| See what a pull request would change                         | [Preview a pull request](docs/how-to/preview-a-pull-request.md)         |
| Have a removed file remove its post, page or tag             | [Delete removed content](docs/how-to/delete-removed-content.md)         |
| Ship a theme from a folder, a zip file or another repository | [Deploy a theme](docs/how-to/deploy-a-theme.md)                         |
| Get the site back in step after a run failed                 | [Recover after a failed run](docs/how-to/recover-after-a-failed-run.md) |
| Look up an input, an output or a limit                       | [Reference](docs/reference.md)                                          |
| Understand why the action works the way it does              | [How it works, and why](docs/explanation.md)                            |

The folder [examples/site](examples/site) is a complete site to copy: a small custom theme, a tag, a page, a post
and the two workflows that deploy and preview them.

## Requirements

- A Ghost site that runs Ghost 5.0 or later, with a custom integration. Its Admin API key is the input `api-key`.
- A runner with PowerShell 7.4 or later and git. The runners that GitHub hosts for Ubuntu, Windows and macOS have
  both.

## Built on the module Ghost

The action is a thin layer around the PowerShell module
[Ghost](https://github.com/Gijsreyn/ghost-sdk-powershell). The module reads the files and talks to the site. The
action adds what a workflow needs: the inputs, the comparison with an earlier commit, and the summary. The same
commands work on your own machine and in other build systems.
