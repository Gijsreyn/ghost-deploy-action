# How it works, and why

This document explains the design of the action: what it is made of, how it decides what to change, and why it
removes content the way it does. It is background. For steps to follow, see the
[getting-started guide](getting-started.md) and the how-to guides.

## A thin layer around a module

The action does very little itself. The work is done by the PowerShell module
[Ghost](https://github.com/Gijsreyn/ghost-sdk-powershell), which has a command for each kind of content:
`Sync-GhostTheme`, `Sync-GhostTag`, `Sync-GhostPage` and `Sync-GhostPost`. The script of the action reads the
inputs, calls those four commands in order, and writes the summary.

There were two other ways to build it.

A JavaScript action is the most common kind on the Marketplace. It would have meant writing everything a second
time: reading the fields of a file, turning Markdown into what Ghost stores, uploading pictures once, and
comparing a file with the site. Two implementations of the same rules drift apart.

A Docker action packs the tool and everything it needs into an image. GitHub only runs those on Linux runners,
and every release has to build and publish an image.

A composite action that runs PowerShell avoids both. PowerShell is on the Linux, Windows and macOS runners that
GitHub hosts. The module is installed in a folder of the run, in the exact version that the release of the
action names, so a run today and a run in a year use the same code.

The split has a second benefit. Everything the action can do, the module can do without it. The same commands
deploy a site from a laptop or from another build system. A new feature goes into the module first, where it is
tested against a real Ghost site, and the action only passes an input to it.

## Only what differs is sent

A run does not push the repository to the site. For every file it reads what the site has and compares.

- A post, page or tag is found by its slug. When the site has none with that slug, it is created. When the file
  differs from what the site has, it is updated. Otherwise nothing is sent.
- A field that the file does not mention is left as it is on the site. A file with only a title and a text does
  not reset the tags or the picture that somebody set in Ghost Admin.
- A theme is compared by a fingerprint of its files. The action adds that fingerprint to the theme as a small
  file, and the site serves it like any other file of the theme. Reading that address tells which theme the site
  shows. Ghost does not let an integration ask which themes a site has, so this is the way to know.

This is why the action can run on every push, and why a run that failed needs no special handling for changes.
The next run compares everything again and sends what is still different.

## The order

Tags go first, then pages, then posts. A post that names a tag that does not exist makes Ghost create that tag
with nothing but its name. With the tags in place first, the tag already has its description and its colour when
the post arrives.

The theme goes before all of them, so that a post never needs a template that the site does not have yet.

## Removing follows the files that were removed

Creating and updating can look at the present alone: here is a file, what does the site have? Removing cannot.
A site usually has content that never was in the repository: posts from before the repository existed, and
pages that somebody wrote in Ghost Admin. "On the site, but not in the repository" describes all of that.

So the action does not mirror the repository. It removes a post, page or tag only when its file was removed. It
compares the files of the run with those of an earlier commit, and removes what a file described then and no
file describes now. Content without a file was in neither commit, so it can never be removed.

The price is that removing depends on history, and changing does not. A removal belongs to the push that
removed the file. When that push is not deployed, a later push does not carry the removal along. That is the
reason for the input `base-ref` and for the guide on
[recovering after a failed run](how-to/recover-after-a-failed-run.md).

Three smaller choices follow from the same caution.

- **It is off unless you turn it on.** Removing cannot be undone, and a workflow that was copied from an example
  should not remove anything by surprise.
- **There is a limit.** A push that removes a whole folder by accident would otherwise take every post with it.
  The run counts the removed files first and stops before it changes anything when there are too many.
- **A commit that cannot be found stops the run.** Going on without it would deploy the changes and silently
  skip the removals, which nobody would notice until much later.

## Slugs, not file names

A post is known to Ghost by its slug, and the action follows that. Two files are the same post when they have
the same slug, wherever they are. Moving a file to another folder is therefore not a removal.

The other side is that a rename is one. A folder with a new name has a new slug, and to Ghost that is a
different post. With `delete` on, the old one is removed. This is deliberate. Guessing that two files are "the
same post under a new name" would sometimes be wrong, and the wrong guess would overwrite a post.

## A dry run reports instead of guessing

With `dry-run`, every command does the comparison and stops before it changes anything. The result is not a
guess from the files alone. It is what the site would be asked to do, given what the site has right now.

That makes a pull request reviewable in a way that a diff of Markdown files is not. The summary says that this
change creates one post, updates a tag and removes a page.

## What Ghost does not allow

Some things are missing because Ghost does not let an integration do them.

- A theme can be uploaded and activated, and nothing else. An integration cannot list themes, delete one, or
  upload `routes.yaml`.
- The settings of a theme, under **Settings**, **Design**, need the token of a staff user. The action only takes
  the key of an integration, which can do less and is the safer thing to put in a secret.
- A picture cannot be removed through the API. A picture that is no longer used stays on the site.

## The key

The Admin API key is the only secret. The action reads it from an environment variable, puts it in a form that
PowerShell does not print, and takes it out of the environment before it starts git or any other program. It is
never part of a command line and never written to the log or the summary.

The inputs reach the script as environment variables and not as text in the script itself. An input can
therefore never be run as code, whatever it contains.
