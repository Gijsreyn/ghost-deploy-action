# Recover after a failed run

This guide shows how to get the site back in step with the repository after a deployment failed or was skipped.

What you need to do depends on one question: was a file removed in the push that did not get deployed?

## Nothing was removed

Fix what the failed run complained about and push. Or run the workflow again.

Every run compares each file with the site and sends what differs. It does not matter which push a change was
in. A change that an earlier run did not get to is sent by the next run that succeeds.

## The run failed and nothing was pushed since

Run the same job again.

1. Open the failed run under **Actions**.
2. Choose **Re-run failed jobs**.

A run that is started again compares the same two commits as the first time. A file that was removed in that
push still takes its post, page or tag with it.

## A file was removed and other pushes came after

A removal is the one thing that a later run does not catch up on. Every push is compared with the commit just
before it. The push that removed the file is no longer the one being compared.

Start a run by hand and tell it where to compare from.

1. Find the last commit that was deployed without errors. It is the commit of the last green run under
   **Actions**.
2. Start the workflow by hand with that commit in `base-ref`.

The workflow needs an input for that. The example workflow has one:

```yaml
on:
  workflow_dispatch:
    inputs:
      base-ref:
        description: Remove what was removed from the repository since this commit
        required: false
        type: string

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: Gijsreyn/ghost-deploy-action@v1
        with:
          api-url: ${{ secrets.GHOST_ADMIN_API_URL }}
          api-key: ${{ secrets.GHOST_ADMIN_API_KEY }}
          posts: posts
          delete: true
          base-ref: ${{ inputs.base-ref }}
```

The run removes everything whose file was removed between that commit and the newest one. Use `dry-run: true`
first when you want to see the list before anything is removed.

## A run was cancelled while it waited

A workflow with a `concurrency` group runs one deployment at a time. GitHub keeps one run waiting. When a third
push arrives, the run that waited is cancelled and the newest one takes its place.

That is fine for files that changed. It is the same situation as above for files that were removed in the push
of the cancelled run. Recover in the same way, with `base-ref`.

## The run says that the commit to compare with could not be fetched

```text
Error: The commit to compare with, '<commit>' from the commit before this push, is not in this clone and could
not be fetched. Check out with fetch-depth: 0, or give the input base-ref a commit that exists.
```

This happens after a push that rewrote the history of the branch, when the earlier commit no longer exists on
GitHub. The run stops before it changes anything.

Start a run by hand. Without `base-ref` it deploys every file and removes nothing. With a commit that still
exists in `base-ref` it also removes what was removed since then.

## Prevent it

- Keep `cancel-in-progress: false` in the `concurrency` group of the deployment. A deployment that is cancelled
  halfway leaves the site between two states.
- Add a [preview for pull requests](preview-a-pull-request.md). A file that Ghost refuses then fails the pull
  request, and not the deployment.
