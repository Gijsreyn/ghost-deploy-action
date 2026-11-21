# Changelog

The changes of every version are on the
[releases page](https://github.com/Gijsreyn/ghost-deploy-action/releases). The notes there are written from the
commit messages when a version is released, so this file is not kept by hand. The versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## The first release

- The action. It deploys a theme and creates and updates tags, pages and posts on a Ghost site from the files of
  a repository, with the PowerShell module Ghost.
- `delete`, `delete-limit` and `base-ref`: remove the posts, pages and tags whose file was removed from the
  repository, with a limit per run.
- `dry-run`: change nothing and report what a real run would do.
- A summary on the page of the run, and the outputs `created`, `updated`, `removed`, `unchanged` and `changed`.
- An example site with a custom theme, in `examples/site`, and a getting-started guide that walks through it.
