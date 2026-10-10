# Security rules

Prefix: SEC.

The image downloads and runs Windows executables from the internet and compiles code from the user's disk. The repository is public.

## Downloaded installers

- **SEC1:** An installer runs only after `verify_installer` accepts it: a valid Authenticode signature, digest and chain against the system CA bundle, with the signing certificate's (not a chain or timestamp certificate's) common name starting with `SIGNER_PATTERN` (MetaQuotes), checked by `require_signer`. Only a failed revocation-list fetch (`CRL_FETCH_FAILURE`) may be retried and then checked with `-ignore-crl`, logged at `WARN` with `reason=crl_unreachable`. A bad digest, an untrusted chain, a revoked certificate or another signer fails at once. Never weaken or skip this check, and never add a flag to skip it.
- **SEC2:** Installer URLs default to RoboForex's MetaQuotes-hosted setups and can only be changed through `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL`. Any URL still goes through SEC1.
- **SEC3:** No MetaQuotes binary, `.ex4` or `.ex5` is committed or baked into the image. `.gitignore` ignores `*.ex4` and `*.ex5`; `.dockerignore` admits only `entrypoint.sh` to the build context.

## The container

- **SEC4:** The image runs as UID 1000 (`USER 1000:1000`), and the wrapper passes the caller's UID and GID with `--user`. Never run the compile as root, and never add `--privileged`, host networking or the Docker socket to the wrapper's `docker run`. `--init` (tini as PID 1) stays: it forwards signals and reaps Wine's leftover processes.
- **SEC5:** The wrapper mounts only what a compile needs (ARC7) and the cache volume. It refuses to mount `/`, and it refuses a path that does not exist instead of letting Docker create it.
- **SEC6:** Nothing writes into the user's tree except the `.ex4`/`.ex5` next to each source (ARC8). A `--mt4-terminal`/`--mt5-terminal` folder is mounted read-only; a real terminal folder holds the user's saved broker logins (`Config/accounts.dat`), so it is never mounted writable, copied into the cache, or read beyond MetaEditor and the `MQL4`/`MQL5` folder.

## Pins and supply chain

- **SEC7:** Pin every third-party dependency: the `debian:trixie-slim` base image by digest, the lint and scan images in the `Makefile` (shellcheck, shfmt, hadolint, gitleaks, grype) by version and digest, and third-party GitHub Actions by commit SHA, in the workflows and in `action.yml` alike (`actions/cache`). Never loosen a pin. The maintainer's reusable workflows (`psyb0t/reusable-github-workflows/...@master`) are deliberately unpinned so a fix reaches every caller.
- **SEC8:** `make sec` passes before a release: gitleaks on the working tree, hadolint at warning level, and grype on the image failing on fixed vulnerabilities at `GRYPE_SEVERITY` (high by default).
- **SEC9:** Review an outside contribution's `Makefile`, `Dockerfile`, `.github/workflows/`, `install.sh`, `wrapper.sh`, `entrypoint.sh` and `tests/test.sh` changes before running any of it. `make test` and `make lint` run that code with Docker access. Read the diff first.
- **SEC10:** New third-party components in the image are listed in `THIRD_PARTY.md` with their license.

## Secrets

- **SEC11:** The project needs no credentials at run time. CI uses `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` and the ClawHub token as GitHub secrets. Never print, commit or paste a secret, and never put a token in a URL, a test or a fixture. `.gitleaks.toml` allowlists only the ignored `.testing` and `.secaudit` folders; do not widen it.
