# Development

```bash
make build      # build psyb0t/mql-compiler:dev, :v<VERSION> and :latest
make test       # compile tests/fixtures with the built image and check the results
make test-all   # make test plus a real release install from Docker Hub (what CI runs)
make lint       # shellcheck and shfmt on the scripts, hadolint on the Dockerfile
make format     # rewrite the scripts with shfmt
make sec        # gitleaks secrets scan, hadolint, grype vulnerability scan of the image
make install    # build :dev and install the command from this checkout
make uninstall  # remove the installed command
make version    # print the version; V=X.Y.Z sets it
make help       # every target
```

Every tool runs from a digest-pinned image, so the host needs Docker and Make and nothing else. `make test` installs the toolchain into `.testing/cache` the first time and reuses it after. `make test` also runs a real `--update`, so it reinstalls the toolchain once per run, and covers the installer, the GitHub Action's script and the failure paths. CI runs `make lint` and `make test-all`, runs the GitHub Action against the freshly built image, builds and pushes the image with a Grype scan on every push, and ships the skill to ClawHub on release tags.

[Back to the README](../README.md).
