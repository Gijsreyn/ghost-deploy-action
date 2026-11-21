# Deploy a theme

This guide shows how to put a Ghost theme on a site from a workflow. The theme can be a folder, a zip file that
a build makes, or a theme in another repository.

The theme is uploaded and activated only when the site does not show it yet. A push that does not touch the
theme sends nothing.

## A theme in a folder

Give the input `theme` the folder that holds the `package.json` of the theme.

```yaml
- uses: actions/checkout@v7

- uses: Gijsreyn/ghost-deploy-action@v1
  with:
    api-url: ${{ secrets.GHOST_ADMIN_API_URL }}
    api-key: ${{ secrets.GHOST_ADMIN_API_KEY }}
    theme: theme
```

For a repository that is the theme itself, the folder is the repository:

```yaml
    theme: .
```

The folder is packed for you. These are left out: `node_modules`, `dist`, every file or folder whose name
starts with a dot, and zip files.

## A theme that needs a build

Build the theme first and give the action the zip file.

```yaml
- uses: actions/checkout@v7

- uses: actions/setup-node@v7
  with:
    node-version: 22

- run: |
    npm ci
    npm run zip

- uses: Gijsreyn/ghost-deploy-action@v1
  with:
    api-url: ${{ secrets.GHOST_ADMIN_API_URL }}
    api-key: ${{ secrets.GHOST_ADMIN_API_KEY }}
    theme: dist/my-theme.zip
```

Use the command and the path that your theme has for this. The two above are the ones of the themes that Ghost
publishes.

## A theme in another repository

Check both repositories out, each in a folder of its own.

```yaml
- uses: actions/checkout@v7
  with:
    path: site

- uses: actions/checkout@v7
  with:
    repository: <owner>/<theme>
    path: theme

- uses: Gijsreyn/ghost-deploy-action@v1
  with:
    api-url: ${{ secrets.GHOST_ADMIN_API_URL }}
    api-key: ${{ secrets.GHOST_ADMIN_API_KEY }}
    theme: theme
    posts: site/posts
```

A private theme repository needs a `token` for the second checkout.

## Choose the name on the site

Ghost stores a theme under a name. That is the `name` in the `package.json` of the theme. Give the input
`theme-name` another name to store it under, for example to try a branch next to the real theme:

```yaml
    theme: theme
    theme-name: my-theme-preview
```

A theme that is uploaded under a name that the site already has replaces that theme.

## Check the result

The summary of the run has a row for the theme.

| Action | What happened |
| --- | --- |
| Updated | The theme was uploaded and activated |
| Unchanged | The site already showed this theme. Nothing was sent |
| Would update | A dry run. A real run would upload and activate the theme |

## When the upload fails

Ghost checks a theme when it is uploaded and refuses one with errors. The run then fails, and the message lists
what Ghost found. Fix those and push again. The theme that was active stays active.

## When the theme is uploaded on every run

The action knows which theme the site shows from a small file that it adds to the theme, and that the site then
serves at `/assets/ghost-theme-fingerprint.txt`. Two things follow:

- The first run for a site always uploads, because the theme that is there did not come from the action.
- A site that asks visitors for a password does not serve that file to the action. The theme is then uploaded on
  every run.

## What a theme deployment does not do

- It does not remove a theme. Ghost does not let an integration do that.
- It does not upload `routes.yaml`. Upload a changed routes file in Ghost Admin.
- It does not change the settings of the theme under **Settings**, **Design**.
