# Reference

The inputs, the outputs and the behaviour of the action `Gijsreyn/ghost-deploy-action`.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `api-url` | Yes | | The address of the Ghost site, such as `https://example.org`. An address without `https://` gets it. |
| `api-key` | Yes | | The Admin API key of a custom integration of the site. Pass it as a secret. |
| `theme` | No | | The folder or the zip file of a theme. Without it the theme is left alone. |
| `theme-name` | No | | The name to store the theme under. Without it the `name` in the `package.json` of the theme is used. |
| `tags` | No | | The folder with a Markdown file per tag. Without it the tags are left alone. |
| `pages` | No | | The folder with the Markdown files of the pages. Without it the pages are left alone. |
| `posts` | No | | The folder with the Markdown files of the posts. Without it the posts are left alone. |
| `delete` | No | `false` | `true` removes the posts, pages and tags whose file was removed from the repository. |
| `delete-limit` | No | `10` | The number of removed Markdown files that one run may act on. |
| `base-ref` | No | | The commit to compare the files with, to find the removed ones. |
| `dry-run` | No | `false` | `true` changes nothing and reports what a real run would do. |
| `module-version` | No | `0.6.0` | The version of the PowerShell module Ghost to use. |
| `module-path` | No | | The folder of a copy of the module Ghost to use instead of a version from the PowerShell Gallery. |

At least one of `theme`, `tags`, `pages` and `posts` has to be given.

A path is read from the working directory of the job, which is the root of the checkout unless the workflow says
otherwise. `tags`, `pages` and `posts` are folders. `theme` is a folder or a zip file.

`delete` and `dry-run` take the text `true` or `false`. Any other text stops the run.

## Outputs

| Output | Description |
| --- | --- |
| `created` | How many tags, pages and posts were created. |
| `updated` | How many themes, tags, pages and posts were updated. |
| `removed` | How many tags, pages and posts were removed. |
| `unchanged` | How many themes, tags, pages and posts were the same as their file. |
| `changed` | `true` when `created`, `updated` or `removed` is not zero, and `false` otherwise. |

In a dry run the outputs count what a real run would do.

A theme is never counted as created. Uploading a theme counts as updated, also the first time.

## The files

| Kind | Layout | The slug comes from |
| --- | --- | --- |
| Post | `posts/<name>.md` or `posts/<name>/index.md`, in any folder below `posts` | `slug` in the fields, or else `<name>` without a date at its start |
| Page | `pages/<name>.md` or `pages/<name>/index.md`, in any folder below `pages` | The same |
| Tag | `tags/<name>.md`, directly in `tags` | `slug` in the fields, or else `<name>` |
| Theme | A folder with a `package.json`, or a zip file | Not applicable |

A file with the name `README.md` is never a post, a page or a tag.

The fields of a file, the way pictures are handled and the rules for a slug are those of the module Ghost. Its
documentation describes them:

- [Posts from Markdown files](https://github.com/Gijsreyn/ghost-sdk-powershell#posts-from-markdown-files)
- [Pages from Markdown files](https://github.com/Gijsreyn/ghost-sdk-powershell#pages-from-markdown-files)
- [Tags from files](https://github.com/Gijsreyn/ghost-sdk-powershell#tags-from-files)

## What a run does, in order

1. Reads and checks the inputs.
2. Loads the module Ghost and connects to the site.
3. With `delete`, finds the commit to compare with and counts the removed files. A count above `delete-limit`
   stops the run here.
4. Checks that every folder of content exists.
5. Deploys the theme.
6. Deploys the tags, then the pages, then the posts. With `delete`, each kind removes what its removed files
   described, after it created and updated.
7. Writes the summary and the outputs.

Nothing is sent to the site before step 5, apart from the requests that read it. In a dry run nothing is sent
that changes the site at all.

## The commit to compare with

`delete` compares the files of the run with those of an earlier commit.

| Event | The commit to compare with |
| --- | --- |
| `push` | The commit that the branch pointed to before the push |
| `pull_request`, `pull_request_target` | The commit of the branch that the pull request goes into |
| Any other, such as `workflow_dispatch` and `schedule` | None. Nothing is removed, and a notice says so |
| The first push of a new branch | None. Nothing is removed, and a notice says so |

The input `base-ref` wins over the event. It takes a commit, or a name that git can resolve to one in the clone
of the job, such as `HEAD~1` with a `fetch-depth` of 2 or more.

A commit that is not in the clone is fetched from `origin`, as one commit.

## The actions in the summary

| Action | Meaning |
| --- | --- |
| Created | A tag, page or post that the site did not have was created |
| Updated | The file differed from the site, and the site was changed. For a theme: uploaded and activated |
| Removed | The file was removed from the repository, and its tag, page or post was removed from the site |
| Would create, Would update, Would remove | The same, in a dry run. Nothing was changed |

Everything that was the same as its file is counted under **Unchanged** and has no row.

## When a run fails

A run fails, with exit code 1 and an error on the page of the run, in these cases.

Before anything is changed:

- `api-url` or `api-key` is empty. An empty key is what a pull request from a fork gets.
- None of `theme`, `tags`, `pages` and `posts` is given.
- `delete` or `dry-run` is not `true` or `false`, or `delete-limit` is not a whole number of zero or more.
- The module Ghost cannot be taken from the PowerShell Gallery, or is older than 0.6.0.
- The site refuses the key.
- `delete` is `true` and the commit to compare with is not in the clone and cannot be fetched.
- `delete` is `true` and more Markdown files were removed than `delete-limit` allows.
- A folder of content does not exist.

While it deploys:

- Ghost refuses the theme. The message lists the errors that Ghost found.
- A file cannot be read or Ghost refuses it. The message names the file. The files before it were deployed.
  Nothing is removed for that kind, and the kinds after it are not deployed in that run.

The summary of a failed run lists what was done until then. The next run that succeeds sends the rest.

## Limits

- A rename of a file or folder, or a changed `slug`, removes the old post and creates a new one when `delete`
  is on. Without `delete` the old post stays next to the new one.
- A post and a page cannot swap in one push. See
  [Delete removed content](how-to/delete-removed-content.md#what-counts-as-removed).
- A run that failed does not get its removals from a later push. See
  [Recover after a failed run](how-to/recover-after-a-failed-run.md).
- A theme is never removed, `routes.yaml` is not uploaded, and the settings of a theme are not changed.
- A picture that is no longer used stays on the site. Ghost cannot remove a picture through its API.
- An email is never sent for a post.
- Members, tiers and the settings of the site are not deployed.

## Requirements

- Ghost 5.0 or later.
- A runner with PowerShell 7.4 or later and git. The action runs on Linux, Windows and macOS.
- Access from the runner to the site and, unless `module-path` is used, to the PowerShell Gallery.

## Versions

`Gijsreyn/ghost-deploy-action@v1` follows the newest release of version 1. A full commit id after the `@` gives a
run that never changes, which GitHub recommends for actions that get a secret.

Each release of the action names one version of the module Ghost in `module-version`. A run installs exactly
that version, in a folder of the run.

The versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). A release that asks for a change
in a workflow gets a new major version and a tag of its own, such as `v2`. The
[releases page](https://github.com/Gijsreyn/ghost-deploy-action/releases) lists the changes of every version.
