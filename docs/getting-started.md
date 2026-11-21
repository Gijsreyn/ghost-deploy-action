# Getting started

In this tutorial you deploy a small site to Ghost from a repository of your own. You start with the example
site of this action, which has a custom theme, a tag, a page and a post. At the end you have published the post,
changed the theme and removed the page, all with a push.

It takes about twenty minutes.

## What you need

- **A Ghost site that you can experiment on.** The tutorial replaces the theme of the site. Use a new site or
  a [local one](https://docs.ghost.org/install/local), not a site that people read.
- **Access to Ghost Admin** of that site, to create an integration.
- **A GitHub account** and git on your machine.

A site that GitHub cannot reach, such as one on `localhost`, cannot be deployed to from a workflow. Use a site
with a public address for this tutorial.

A custom integration and a custom theme need a Ghost plan that allows them. A site that you host yourself always
does.

## 1. Make a repository from the example

Create a new, empty repository on GitHub. Then copy the example site into it. Replace `<you>` with your account
and `<site>` with the name of the repository.

```bash
git clone https://github.com/Gijsreyn/ghost-deploy-action.git
git clone https://github.com/<you>/<site>.git

cp -r ghost-deploy-action/examples/site/. <site>/
cd <site>
```

Your repository now looks like this:

```text
.github/workflows/
  deploy.yml          Runs on every push to main
  preview.yml         Runs for every pull request
theme/                A small custom theme
tags/
  deploy-example.md   One tag
pages/
  about-this-example/
    index.md          One page
posts/
  2026-11-21-hello-from-a-repository/
    index.md          One post
    images/cover.png  Its picture
README.md             What the example is
```

The folders `tags`, `pages` and `posts` each have a `README.md` as well. A file with that name is never deployed.
It says what the folder is for, and it keeps the folder in the repository when its last file is removed.

The post and the page are drafts. Visitors of your site see neither until you publish them.

Do not push yet. The workflow needs to know your site first.

## 2. Create an integration in Ghost

An integration gives the action a key for your site.

1. Open Ghost Admin and go to **Settings**, then **Integrations**.
2. Choose **Add custom integration** and name it `GitHub`.
3. Keep the page open. You need the **Admin API key** and the **API URL** in the next step.

## 3. Give the repository the key

1. Open your repository on GitHub and go to **Settings**, then **Secrets and variables**, then **Actions**.
2. Choose **New repository secret**. Name it `GHOST_ADMIN_API_URL` and paste the API URL.
3. Add a second secret. Name it `GHOST_ADMIN_API_KEY` and paste the Admin API key.

The workflow in `.github/workflows/deploy.yml` reads these two secrets:

```yaml
- name: Deploy to Ghost
  uses: Gijsreyn/ghost-deploy-action@v1
  with:
    api-url: ${{ secrets.GHOST_ADMIN_API_URL }}
    api-key: ${{ secrets.GHOST_ADMIN_API_KEY }}
    theme: theme
    tags: tags
    pages: pages
    posts: posts
    delete: true
```

## 4. Deploy

Commit everything and push.

```bash
git add --all
git commit --message "Start from the example site"
git push
```

Open the tab **Actions** of your repository and choose the run **Deploy to Ghost**. When it is done, its
summary looks like this:

```text
Deploy to Ghost

The files were deployed to My site.

Created: 3, updated: 1, removed: 0. Unchanged: 0.

Kind   Action   Name                        Slug                     File
Theme  Updated  ghost-deploy-example 1.0.0                           theme
Tag    Created  Deploy example              deploy-example           tags/deploy-example.md
Page   Created  About this example          about-this-example       pages/about-this-example/index.md
Post   Created  Hello from a repository     hello-from-a-repository  posts/2026-11-21-hello-from-a-repository/index.md
```

Now look at the site:

- The home page has the new theme.
- Ghost Admin has the post **Hello from a repository** and the page **About this example**. Both are drafts,
  so visitors do not see them yet.
- The post has its picture, and the tag **Deploy example**.

You have deployed a site from a repository.

## 5. Publish the post

Open `posts/2026-11-21-hello-from-a-repository/index.md`. The lines between the dashes are the fields of the
post. Change the status:

```yaml
status: published
```

Commit and push.

```bash
git commit --all --message "Publish the first post"
git push
```

The summary of this run has one row:

```text
Created: 0, updated: 1, removed: 0. Unchanged: 3.

Kind  Action   Name                     Slug                     File
Post  Updated  Hello from a repository  hello-from-a-repository  posts/2026-11-21-hello-from-a-repository/index.md
```

The theme, the tag and the page did not change, so nothing was sent for them. The post is on the home page of
the site now.

## 6. Change the theme

Open `theme/assets/css/screen.css` and change the colour of the links, near the top of the file:

```css
--color-accent: var(--ghost-accent-color, #b83280);
```

Commit and push.

```bash
git commit --all --message "Change the colour of the links"
git push
```

This run uploads the theme again and activates it. The other three are unchanged.

## 7. Remove the page

Remove the folder of the page, commit and push.

```bash
git rm -r pages/about-this-example
git commit --message "Remove the example page"
git push
```

The summary shows that the page was removed from the site as well:

```text
Created: 0, updated: 0, removed: 1. Unchanged: 3.

Kind  Action   Name                Slug                File
Page  Removed  About this example  about-this-example  pages/about-this-example/index.md
```

This happened because the workflow sets `delete: true`. The action compared this push with the one before it,
saw that the file was gone, and removed its page. A page that was written in Ghost Admin has no file and is
never touched.

## What you have now

- A repository that holds a theme and the content of a site.
- A workflow that deploys every push, and only sends what changed.
- A second workflow, `preview.yml`, that shows for every pull request what merging would change.

## Where to go next

- Write a post of your own. Copy the folder of the example post, give it a new name and change the file. The
  module Ghost documents [every field a post can have](https://github.com/Gijsreyn/ghost-sdk-powershell#posts-from-markdown-files).
- [Preview a pull request](how-to/preview-a-pull-request.md) before it is merged.
- Read [Delete removed content](how-to/delete-removed-content.md) before you rename a post.
- Look up the inputs in the [reference](reference.md).
