# Working on Orbit

- After pushing Windows changes to `main`, always release them: bump the patch version in
  `windows/package.json` and its lockfile (`npm version patch --no-git-tag-version` inside
  `windows`) and push to `main`, so Windows CI publishes the new GitHub release.
