# Draft: nix-darwin issue: the default `nix.daemonProcessType = "Standard"` makes builds use only the efficiency cores

Status: **draft, not submitted.** Search for an existing issue first (none found on 2026-10-09).

---

**Title:** Default `nix.daemonProcessType = "Standard"` confines builds to efficiency cores on Apple Silicon (7× slower)

**Description:**

On an M3 Max (12 P + 4 E cores, macOS 26, Nix 2.34.8, nix-darwin 26.05), builds were mostly
running on the 4 efficiency cores. htop showed CPUs 0–3 at ~85% and the rest mostly idle, even
though `cores = 0` and hadrian/make were running with `-j16`.

A minimal benchmark: 16 copies of a CPU-bound shell loop
(`i=0; while [ $i -lt 1500000 ]; do i=$((i+1)); done`):

| | wall time |
|---|---|
| run directly as the user | 6 s |
| run inside a `runCommand` build, daemon with `ProcessType` Standard (the default) | 42 s |
| run inside a `runCommand` build, after `nix.daemonProcessType = "Interactive"` | 6 s |

`NIX_BUILD_CORES` was 16 in all cases.

The option's documentation does say that `Standard` "will apply light resource limits, throttling
its CPU usage and I/O bandwidth" and that the limits propagate to build processes. In practice
on Apple Silicon this seems to mean "efficiency cores only", which is a much bigger effect than
"light". The default was changed from `Interactive` to `Standard` in 08edc0e19a (#490, 2022),
which says nothing about the performance impact. nix-community's darwin builders already set
`Interactive`.

Suggestions: either default back to `Interactive` (or `Adaptive`), or at least document the
effect prominently, e.g. "on Apple Silicon, `Standard` restricts builds to the efficiency cores".

Also note: switching the option restarts the daemon, but the per-connection workers of builds
that are already running survive the restart and keep the old limits. Those builds have to be
restarted to benefit.

_Measurements done with help from an AI assistant (Claude Code); I verified the numbers._
