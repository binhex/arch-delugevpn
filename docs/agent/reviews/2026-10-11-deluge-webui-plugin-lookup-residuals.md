# Deluge WebUI plugin lookup patch - code review residuals

| Field | Value |
| --- | --- |
| Branch | `master` (mirrored on `libtorrentv1`) |
| Commit | `master` `ffcac7e`, `libtorrentv1` `9e4b851` |
| Round reached | 10 |
| Circuit breaker cap | `CIRCUIT_BREAKER_ROUNDS = 10` |
| Reviewer A | `opencode-go/deepseek-v4.1-flash:max` |
| Reviewer B | `opencode-go/minimax-m3:max` |

Scope under review: the build-time patch that normalises the three `WebPlugin` component
lookups in `deluge/ui/web/pluginmanager.py` so mixed-case plugins (Label, Scheduler, YaRSS2,
...) keep their Web UI on images built from Arch's `deluge` package, plus its regression test
and the `workflow-test` CI job.

## Findings from round 10

| # | Severity | File:line | Description | Status |
| --- | --- | --- | --- | --- |
| 1 | MEDIUM | `build/root/install.sh:218-219` (python at `191-199`) | A patched file whose AST verification could not run returned `0 0` and was reported as `[warn] no lookup matching ... patch not applied` while the build continued, shipping a patched but unverified file | applied, not independently re-reviewed |
| 2 | LOW | `build/root/install.sh:193-199` | `UnicodeDecodeError` was outside the caught tuple, so an undecodable file aborted `install.sh` with a raw traceback under `set -e`; a parse failure was misreported as "no lookup matching" | applied, not independently re-reviewed |
| 3 | LOW | `build/root/install.sh:170-190` | The AST counter matched raw source text, so a comment inside a multi-line argument span could be read as normalisation (a raw lookup reported as already normalised) | applied, not independently re-reviewed |
| 4 | LOW | `build/root/install.sh:157-159` | The sed gate is a line-based, comment-insensitive `grep -qF`, and that flag decides crit versus warn: a file whose real lookups are correct but spelled equivalently-but-unrecognised, together with any raw literal in a comment, can abort a correct build | not fixed (deliberate fail-closed; see residual risks) |
| 5 | LOW | `build/root/install.sh:191` | The AST loop stopped at the first matching argument per call, so a call carrying two `WebPlugin` arguments undercounted | applied, not independently re-reviewed |
| 6 | LOW | `build/root/install.sh:194` | Substring classification could accept a pathological normalisation chain (for example a trailing `.upper()`) as already normalised | not fixed (documented; no upstream precedent) |
| 7 | LOW | `tests/test-deluge-webui-plugin-patch.sh:158-162, 566-577` | The commented-out fixture only discriminated a comment-blind line counter; no fixture covered two lookups on one line or the inline-helper registration form | applied, not independently re-reviewed |
| 8 | LOW | `build/root/install.sh:134` | `awk` class-span edge cases (a decorator on its own line, a nested class) fall through to "registration shape not recognised" | not fixed (fails safe: nothing is patched) |
| 9 | LOW | `.github/workflows/workflow-test.yml` `on.pull_request` | Parity is skipped for pull requests, so the first push after a PR merge is red until the sibling branch advances | not fixed (documented in the workflow header) |

## Verification gap

Round 10 is the circuit-breaker round. Every finding above was **applied after the reviewers'
final pass and was never independently re-reviewed** - that is what the cap means. The direct
evidence available for the fixes is local only:

- `bash tests/test-deluge-webui-plugin-patch.sh build/root/install.sh` -> 41/41 PASS, exit 0, on
  both `master` and `libtorrentv1`
- Manual regression for finding 1: an unparseable file that was patched now emits
  `[crit] could not parse ... exiting build process...` and exits non-zero
- `shellcheck` unchanged from the pre-change baseline (`1 x SC1091 + 2 x SC2086`, both
  pre-existing); `bash -n` clean; workflow YAML valid and its embedded shell shellcheck-clean;
  the patch block, the regression test and the workflow are byte-identical across branches

## Residual risks carried forward

- **No end-to-end image build.** This environment has no usable docker socket (uid 99,
  `docker info` exits 1), so the only proof that Label's Web UI and AutoRemovePlus load on a
  built image is the next tagged build.
- **The loader classification rests on file shapes that are not in this repo.** The fixtures
  mirror the block's own constants. A packaged `pluginbase.py` that normalises with a different
  spelling degrades to a warning (the original bug survives with a green build), and - per
  finding 4 - an equivalent-but-unrecognised formula plus a raw literal in a comment can abort
  a correct build.
- Findings 4, 6, 8 and 9 remain as accepted, documented limitations.
