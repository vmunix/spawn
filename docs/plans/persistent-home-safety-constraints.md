# Persistent Home Safety Constraints

Status: deferred design constraints, not an implementation plan.

These rulings were established while reviewing the superseded copy-on-write
home plan. Any future persistent-home design must preserve them. The deleted
plan's task sequence and interfaces are stale; these findings are not.

## Access remains launch-scoped

A persistent home must never absorb host git, GitHub CLI, or SSH credentials.
Doing so would make `--access minimal|git|trusted` unenforceable after the first
wider run. It would also let an untrusted run plant `~/.ssh/config` for a later
`trusted` run to honor.

Keep credential exposure in ephemeral mounts selected for the current launch.
Nested bind mounts at `/home/coder` and paths such as `/home/coder/.ssh` were
verified to work with Apple `container` 1.2.2. Re-verify this when changing the
minimum runtime version or backend; do not replace it with persistent copies
merely because nested mounts are assumed unsupported.

## Seeding needs explicit update semantics

Mounting a host directory at `/home/coder` completely shadows the image home,
including installed agent binaries. A managed image therefore needs an
explicit, validated home-seeding contract before a persistent home is mounted.

`cp -n` and `cp --no-clobber` never update an existing file, so they cannot make
image updates appear in an existing home. `cp -a` also reports failures when
VirtioFS rejects timestamp preservation; masking its exit status would hide real
seed failures. A future design needs deliberate merge semantics plus an
image-digest-keyed sentinel, with failures surfaced rather than ignored.

## Image compatibility is a launch precondition

Upgrading the host binary without rebuilding compatible managed images must
fail before mounting the persistent home. Otherwise the mount can shadow an
older image that has no skeleton or seeding entrypoint, producing an empty home
and errors such as `claude: command not found` with no useful diagnosis.

Managed images need a versioned compatibility stamp. Both launch and
`spawn doctor` must validate it and give a rebuild instruction. Workspace and
custom images have unknown layouts and must retain their existing home behavior
unless they explicitly adopt the same contract.

