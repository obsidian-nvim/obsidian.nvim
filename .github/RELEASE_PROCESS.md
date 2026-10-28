# GitHub Release Process

## Release

1. Update the version in `lua/obsidian/version.lua`.
2. Run `make docgen` and `make user-docs`, review the generated changes, and commit them before tagging.
3. Run `./scripts/release.sh`. This updates the changelog/module files, commits the changes, and creates and pushes a version tag.
4. The `Main` workflow builds the documentation from that tag before publishing the GitHub release. Stable releases then deploy the built artifact to GitHub Pages. Prerelease tags (for example, `v3.0.0-rc.1`) publish a prerelease without replacing the stable documentation.

## Retry a failed deployment

- For a transient failure or a corrected Pages/environment setting, open **Actions → Main → the failed run → Re-run failed jobs**. Do not delete the release or tag just to retry Pages.
- If the Pages artifact has expired, use **Re-run all jobs** to rebuild it before deploying.
- Reruns use the original tag's commit. If source content or workflow code needs a fix, commit the fix and publish a new version tag instead of moving an existing release tag.

The site is published on stable releases, not prereleases or every commit to `main`. The old GitHub Wiki is no longer synchronized; after confirming the Pages site is live, archive or disable the wiki in repository settings and replace any remaining external links to it.
