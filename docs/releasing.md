# Making a release

A release is a tag `vX.Y.Z`. Pushing it runs `.github/workflows/release.yml`,
which builds the static `b4h-tool` for x86_64 and aarch64 Linux and publishes
the release that the installer downloads from:
`b4h-tool-linux-amd64`, `b4h-tool-linux-arm64`, `SHA256SUMS` and
`THIRD-PARTY-LICENSES.txt`.

bash4humans and b4h-tool share one version number. The workflow stops unless
the tag equals all three of:

- `B4H_VERSION` in `b4h.bash`
- `version` in `tools/b4h-tool/Cargo.toml` (then `cargo build` to update `Cargo.lock`)
- `B4H_TOOL_VERSION` in `versions.conf`

## Steps

1. Run the checks that CI cannot (they need zsh and Powerlevel10k; see
   `tests/README.md`): `tests/p10k/all.sh` and `tests/p10k/wizard.sh`.
2. Set the three version numbers to X.Y.Z and empty the two pins
   `B4H_TOOL_SHA256_amd64` / `_arm64` in `versions.conf` (the new binaries
   do not exist yet; until they are pinned, the installer checks a download
   against the release's `SHA256SUMS`). Commit, push, wait for CI.
3. `git tag -a vX.Y.Z -m 'bash4humans X.Y.Z' && git push origin vX.Y.Z`
4. When the release workflow has finished, copy the two SHA-256 sums from the
   release's `SHA256SUMS` into `B4H_TOOL_SHA256_amd64` / `_arm64` in
   `versions.conf`, commit and push. From then on a download must match the
   sum in the repository, not only the one next to the binary.

Between steps 3 and 4 a new install finds no binary for a moment and builds
b4h-tool with cargo if it can (or goes without it: b4h-tool is optional).

## Upstream pins

`versions.conf` pins ble.sh (a commit), fzf, bash-completion and gitstatus
(versions with SHA-256 sums). To move one: change the line, check the sum
against the upstream release, run the checks above. `b4h update` on an
installed copy fetches what changed.
