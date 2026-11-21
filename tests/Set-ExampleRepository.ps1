<#
.SYNOPSIS
    Makes a repository from the example site and takes it through the steps of the getting-started guide.

.DESCRIPTION
    The example site in examples/site is what the getting-started guide tells a reader to copy. This script
    does what that reader does, one commit at a time, so that a test can deploy after every step:

    First   Copies the example site into a new repository and commits it.
    Second  Publishes the post, changes a colour of the theme and removes the page.
    Third   Removes the tag and the post, which leaves the folders tags and posts without a file.

    The end-to-end test on your own machine and the workflow of this repository both use it. The example is
    tested exactly as it is that way, and cannot drift away from what the action does.

    A Ghost site keeps a theme once it has it, so a second run of a test would find the theme of the first run
    and upload nothing. The parameter Marker adds a line to the stylesheet in the first commit, which makes the
    theme of every run differ.

.EXAMPLE
    ./tests/Set-ExampleRepository.ps1 -Path ./fixture -Step First

    Makes the repository in the folder fixture, with the example site as its first commit.

.EXAMPLE
    ./tests/Set-ExampleRepository.ps1 -Path ./fixture -Step Second

    Adds the commit that publishes the post, changes the theme and removes the page.
#>
#Requires -Version 7.4
[CmdletBinding()]
[OutputType([void])]
param(
    # The folder of the repository. The first step creates it.
    [Parameter(Mandatory)]
    [string] $Path,

    # The step of the guide to take.
    [Parameter(Mandatory)]
    [ValidateSet('First', 'Second', 'Third')]
    [string] $Step,

    # Text for a comment in the stylesheet of the theme, in the first step.
    [string] $Marker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$encoding = [System.Text.UTF8Encoding]::new($false)
$example = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'examples/site'
$stylesheet = Join-Path -Path $Path -ChildPath 'theme/assets/css/screen.css'
$post = Join-Path -Path $Path -ChildPath 'posts/2026-11-21-hello-from-a-repository'

# Runs git in the repository and stops when it fails.
$git = {
    $output = & git -C $Path @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($args -join ' ') failed: $($output -join ' ')"
    }
}

switch ($Step) {
    'First' {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        # With -Force the folder .github comes along on Linux and macOS, where a name with a dot is hidden.
        Get-ChildItem -LiteralPath $example -Force | Copy-Item -Destination $Path -Recurse -Force

        if ($Marker) {
            $css = [System.IO.File]::ReadAllText($stylesheet, [System.Text.Encoding]::UTF8)
            [System.IO.File]::WriteAllText($stylesheet, "$css`n/* $Marker */`n", $encoding)
        }

        & $git init --quiet --initial-branch main
        & $git config user.name 'Test'
        & $git config user.email 'test@example.com'
        & $git config commit.gpgsign false
        & $git config core.autocrlf false
    }
    'Second' {
        $file = Join-Path -Path $post -ChildPath 'index.md'
        $text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($file, $text.Replace('status: draft', 'status: published'), $encoding)

        $css = [System.IO.File]::ReadAllText($stylesheet, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($stylesheet, $css.Replace('#1d6fa5', '#b83280'), $encoding)

        Remove-Item -LiteralPath (Join-Path -Path $Path -ChildPath 'pages/about-this-example') -Recurse -Force
    }
    'Third' {
        Remove-Item -LiteralPath (Join-Path -Path $Path -ChildPath 'tags/deploy-example.md') -Force
        Remove-Item -LiteralPath $post -Recurse -Force
    }
}

& $git add --all
& $git commit --quiet --message "The $($Step.ToLowerInvariant()) step of the guide"
