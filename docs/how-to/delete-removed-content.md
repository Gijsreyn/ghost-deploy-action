# Delete removed content

This guide shows how to have a post, a page or a tag removed from the site when its file is removed from the
repository. Without it, a removed file leaves its post, page or tag on the site.

Removing cannot be undone. Read [What counts as removed](#what-counts-as-removed) before you turn it on.

## Turn it on

Add `delete: true` to the step that deploys.

```yaml
- uses: Gijsreyn/ghost-deploy-action@v1
  with:
    api-url: ${{ secrets.GHOST_ADMIN_API_URL }}
    api-key: ${{ secrets.GHOST_ADMIN_API_KEY }}
    tags: tags
    pages: pages
    posts: posts
    delete: true
```

From the next push on, a file that the push removes takes its post, page or tag with it. The summary of the run
has a row with the action **Removed** for each one.

## Check what would be removed first

Run once with `dry-run: true`. Nothing is changed, and the summary lists the rows with **Would remove**.
[Preview a pull request](preview-a-pull-request.md) does this for every pull request.

## Set the limit

A run stops before it changes anything when the push removed more Markdown files than `delete-limit` allows.
The default is 10. It is there for the push that removes a whole folder by accident.

```yaml
    delete: true
    delete-limit: 50
```

The message of a run that stops names the files. This is a run with a limit of 2:

```text
Error: 3 files were removed since commit <commit>: pages/contact/index.md, posts/old-news.md, tags/archive.md.
The input delete-limit allows 2. Give delete-limit a higher number for this run when that is what you want.
Nothing was changed.
```

Raise the limit for the run that is meant to remove that much, and put it back afterwards.

## Keep a folder that becomes empty

Git does not keep a folder without files. When the last post is removed, the folder `posts` is gone from the
next checkout. The action handles that for the run that removes the post. A later run fails, because the input
`posts` then names a folder that does not exist.

Put a `README.md` in each folder of content. It keeps the folder, and a file with that name is never taken for
a post, a page or a tag.

## What counts as removed

The action compares the files of the push with the files of the commit before the push. Only a post, page or
tag that had a file in that earlier commit can be removed. Content that was written in Ghost Admin never had a
file, so it is never touched.

A post, page or tag is known by its slug, which comes from the name of its file or folder, or from `slug` in its
fields. That has three consequences:

- **A file that moves keeps its post.** Moving `posts/my-post.md` to `posts/2026/my-post.md` changes nothing,
  because the slug is the same.
- **A rename removes the post and creates a new one.** Renaming the folder `my-post` to `my-new-post` changes
  the slug. The post with the old slug is removed, with its comments, and a new post is created. Change the
  address of a post in Ghost Admin first, and then rename the folder to match, to keep the post.
- **A post that becomes a page takes two pushes.** A post and a page cannot have the same slug at the same time.
  Remove the post in one push and add the page in the next.

A tag that is removed while posts in the repository still name it comes back. The next deployment of such a post
creates the tag again, with nothing but its name. Take the tag out of the posts in the same push.

## Which runs remove something

| The run was started by | Compared with |
| --- | --- |
| A push | The commit before the push |
| A pull request | The branch that the pull request goes into |
| A schedule, or by hand | Nothing. The run removes nothing and says so in a notice |

Give the input `base-ref` a commit to compare with another one. [Recover after a failed
run](recover-after-a-failed-run.md) uses that.

The workflow does not need the whole history. The action fetches the one commit it compares with. That fetch uses
the access that `actions/checkout` leaves behind. If your workflow sets `persist-credentials: false` for a
private repository, set `fetch-depth: 0` as well, so that the commit is already there.

## Themes

A theme is never removed. Ghost does not let an integration delete one. Remove a theme that is no longer used
in Ghost Admin.
