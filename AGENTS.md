# Instructions for coding agents

This repository is a GitHub Action, `Deploy to Ghost`. It deploys a theme, tags, pages and posts from a
repository to a [Ghost](https://ghost.org) site. It is a composite action that runs PowerShell 7 and lets the
PowerShell module [Ghost](https://github.com/Gijsreyn/ghost-sdk-powershell) do the work.

## Commands

Run them from the root of the repository, with PowerShell 7.4 or later.

```powershell
./build/install.ps1                                   # once: Pester and PSScriptAnalyzer
./build/Invoke-RunTests.ps1                           # unit tests and PSScriptAnalyzer
./build/Invoke-Analyzer.ps1 | Where-Object Findings   # PSScriptAnalyzer only, which is faster
./tests/Invoke-EndToEnd.ps1 -ModulePath <folder>      # the action against a Ghost site on this machine
```

- The work is done when `./build/Invoke-RunTests.ps1` passes without a single failure. A PSScriptAnalyzer
  finding of any severity is a failure.
- Run `./tests/Invoke-EndToEnd.ps1` as well when you changed a script in `src`, the example site or the module
  version. It installs a Ghost site in `./.local-ghost`, which git ignores, and needs Node.js 22 or 24. The
  first run takes a few minutes.
- Without `-ModulePath` the end-to-end test takes the module from the PowerShell Gallery, in the version that
  `action.yml` names. With it, it uses a checkout of the module.

## Ask first

Ask before you do any of these:

- Send anything to a Ghost site that is not on this machine. That includes a dry run and a request that only
  reads. The end-to-end test refuses a site that is not on `localhost`.
- Change the default of `module-version` in `action.yml`. It decides which module every user gets.
- Push to `main`, create a tag or a release, or move the tag `v1`. A push to `main` with a `fix` or a `feat`
  commit publishes the action.
- Make a commit that releases a major version, with a `!` or with `BREAKING CHANGE`. No workflow follows the
  tag `v2` until the documentation names it.
- Change `release/.releaserc.yml`, a version in `release/package.json` or the job `release` of the workflow.
  They decide what is published, and with which tools.
- Change `PSScriptAnalyzerSettings.psd1` or suppress a rule.

## The parts

| Path                              | What it is                                                                       |
|-----------------------------------|----------------------------------------------------------------------------------|
| `action.yml`                      | The inputs and outputs, and the one step that runs the script                    |
| `src/Invoke-GhostDeploy.ps1`      | The script that the step runs                                                    |
| `src/*.ps1`                       | One function per file, with the name of the file. The script loads them all      |
| `tests/Unit`                      | Pester tests                                                                     |
| `tests/Stubs/Ghost`               | A stand-in for the module Ghost, which the unit tests load through `module-path` |
| `tests/Invoke-EndToEnd.ps1`       | The test against a real Ghost site                                               |
| `tests/Set-ExampleRepository.ps1` | Makes a repository from the example site, one commit per step of the guide       |
| `examples/site`                   | A complete site to copy: a theme, a tag, a page, a post and two workflows        |
| `docs`                            | The documentation                                                                |
| `.github/workflows/ci.yml`        | The workflow `CI`: the tests, and after a push to `main` the release             |
| `release`                         | semantic-release: its settings, and the versions that the workflow installs      |
| `build/Update-MajorTag.ps1`       | Moves the tag `v1` to the newest release                                         |

## How a run works

`action.yml` passes every input to the script as an environment variable that starts with `GHOST_DEPLOY_`. The
script then goes through these functions:

| Step                                                | What it does                                                               |
|-----------------------------------------------------|----------------------------------------------------------------------------|
| `Get-DeployInput`                                   | Reads the variables and checks them                                        |
| `Import-GhostModule`                                | Saves the pinned version of the module in a folder of the run and loads it |
| `Resolve-BaseCommit`                                | With `delete`, finds the commit to compare with                            |
| `Export-PreviousFile`                               | Writes the Markdown files of that commit to a folder of the run            |
| `Sync-GhostTheme` and the three other Sync commands | The module creates, updates and removes                                    |
| `ConvertTo-DeployRow`                               | Turns every result into a row for the report                               |
| `Write-DeployReport`                                | Writes the summary and the outputs                                         |

## Rules

- **The action stays thin.** A new ability goes into the module Ghost first, where it is tested against a Ghost
  site. The action passes an input to it. Do not rebuild in this repository what the module knows, such as how
  a file gets its slug.
- **An input is named in three places.** `action.yml` declares it and passes it on as `GHOST_DEPLOY_<NAME>`,
  and `Get-DeployInput` reads it. `tests/Unit/Action.Tests.ps1` fails when one of the three is missing. Add the
  input to `docs/reference.md` as well.
- **No input in the text of a script.** In `action.yml`, an input goes into `env:` and never into `run:`.
- **Every command that changes the site gets `-WhatIf:$dryRun -Confirm:$false`.** The `-WhatIf` of a script
  does not reach the commands of a module. Without it a dry run changes the site.
- **The key is never written.** Not to the log, the summary, a file or a command line.
- **No path through text.** Ask git about a folder with `Invoke-Git`, and do not compare a path that git
  printed with one that PowerShell made. Windows has more than one way to write the same folder.
- **One function per file**, with comment-based help and a comment above every parameter.
- **No functions in a test file.** Keep a helper in a script block, `$script:Name = { param($Value) ... }`, and
  call it with `&`. Use `$script:` for a variable that is set in `BeforeAll` and read in `It`.
- **A test that makes a git repository removes it in `AfterAll`.** Git makes its files read-only, and Pester
  cannot delete those on Windows.
- **The example site is tested as it is.** `tests/Set-ExampleRepository.ps1` copies `examples/site` and the
  end-to-end test deploys it. Change the steps in that script, the checks in `tests/Invoke-EndToEnd.ps1` and
  `docs/getting-started.md` together.

## Formatting

Four spaces, lines of 120 characters at most, the opening brace on the same line, `else` and `catch` on a new
line after the closing brace, `=` signs aligned in a hashtable, single quotes for a string without variables.
`Invoke-Formatter` with the settings of the repository repairs most of it:

```powershell
$file = 'src/Get-DeployInput.ps1'
$text = Get-Content -LiteralPath $file -Raw
Invoke-Formatter -ScriptDefinition $text -Settings ./PSScriptAnalyzerSettings.psd1 |
    Set-Content -LiteralPath $file -NoNewline
```

It does not shorten a long line. In comment-based help, do not start a line with a dot followed by a word, such
as `.md files`. PowerShell reads that as a keyword and the help is lost.

## Writing

These rules are for the documentation and for comments in code, comment-based help included.

- **Follow the documentation-writer skill** of
  [github/awesome-copilot](https://github.com/github/awesome-copilot/blob/f10fdb8b2660ce85c98f220b2f1ca24653768a5c/skills/documentation-writer/SKILL.md),
  which is the Diátaxis approach. Every document has one type, one reader and one goal:

  | Document                  | Type                                                          |
  |---------------------------|---------------------------------------------------------------|
  | `docs/getting-started.md` | Tutorial: a lesson that ends in a working site                |
  | `docs/how-to/*.md`        | How-to guide: the steps for one problem                       |
  | `docs/reference.md`       | Reference: facts to look up, without advice                   |
  | `docs/explanation.md`     | Explanation: why it works this way, without steps             |
  | `README.md`               | The front page: what it is, one example, and where to read on |

  Do not mix the types. A reason belongs in the explanation and a list of inputs in the reference. For a new
  document, settle its type, its reader, its goal and its outline before you write it.
- **Use few semicolons and few dashes.** A semicolon or a dash that joins two thoughts becomes two sentences.
  Names such as `-WhatIf` and `api-url`, and the syntax of YAML and Markdown, stay as they are.
- **Write for somebody who runs a Ghost site and has written a workflow before.** PowerShell is not assumed.
- **Show only what was run.** An example in a document comes from a file that the tests use, or was tried on a
  site on this machine.

## Commit messages and releases

Nobody gives the action a version by hand. After a push to `main`, when the tests passed, the job `release` of
the workflow `CI` runs [semantic-release](https://github.com/semantic-release/semantic-release) in the folder
`release`. It reads the commits since the last release and works out the next version from their messages. It
makes the tag `v<major>.<minor>.<patch>` and the release on GitHub, with notes from the same messages. Then
`build/Update-MajorTag.ps1` moves the tag `v1` to that release.

So the message of a commit decides what is published. Every commit follows
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

| The message starts with                   | It releases                     | Use it for                     |
|-------------------------------------------|---------------------------------|--------------------------------|
| `fix:` or `perf:`                         | A patch, 1.2.0 to 1.2.1         | A repair that a user notices   |
| `feat:`                                   | A minor version, 1.2.0 to 1.3.0 | A new input, output or ability |
| `feat!:`, `fix!:` or `BREAKING CHANGE:`   | A major version, 1.2.0 to 2.0.0 | A workflow has to change       |
| Another type, such as `docs:` or `chore:` | Nothing                         | What a user does not notice    |

- The text after the type becomes a line of the release notes, as it is. Write it for somebody who uses the
  action: `feat: add the input theme-name`, and not `feat: extend Get-DeployInput`.
- A new default of `module-version` is a `feat`. Every user gets another module with it.
- `BREAKING CHANGE:` starts a line of its own below the message. The text after it says what a workflow has to
  change, and the notes show it under a heading of its own.
- After a squash merge only the message of the merged commit counts. Give it a type as well.
- A commit that releases nothing is not in the notes. `CHANGELOG.md` only points to the releases and gets no
  line per change.
- The Marketplace is not part of the job. Whether a release is listed there is a checkbox on the page of that
  release on GitHub, which is for the maintainer.

## What cannot be tested on your own machine

Only GitHub runs `action.yml`. These are checked by the workflow `CI` and not before:

- That the step finds the script through `GITHUB_ACTION_PATH`, and that its exit code fails the step.
- The inputs and outputs as GitHub passes them.
- The event of a real push or pull request, and the fetch of a commit in a clone that `actions/checkout` made.
- How the summary and the errors look on the page of a run.
- The job `release`: that semantic-release may push a tag and make a release with the token of the run, and
  what that release looks like. `tests/Unit/Release.Tests.ps1` covers the script that moves `v1`, and that the
  settings, the lock file and the workflow agree.

Say so when you report on a change to one of them. Do not report it as tested.
