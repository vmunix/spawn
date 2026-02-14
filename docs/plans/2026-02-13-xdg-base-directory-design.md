# XDG Base Directory Support

## Summary

Migrate from `~/.spawn` to XDG Base Directory standard paths, respecting `XDG_CONFIG_HOME` and `XDG_STATE_HOME` environment variables.

## Path Mapping

| Old | New (default) | XDG Variable | Category |
|---|---|---|---|
| `~/.spawn/env` | `~/.config/spawn/env` | `XDG_CONFIG_HOME` | Config |
| `~/.spawn/state/git/` | `~/.local/state/spawn/git/` | `XDG_STATE_HOME` | State |
| `~/.spawn/state/ssh/` | `~/.local/state/spawn/ssh/` | `XDG_STATE_HOME` | State |
| `~/.spawn/state/<agent>/` | `~/.local/state/spawn/<agent>/` | `XDG_STATE_HOME` | State |

## Approach

New `Paths.swift` module with `configDir` and `stateDir` computed properties. Consumers (`MountResolver`, `EnvLoader`) call `Paths` instead of hardcoding `~/.spawn`.

## Decisions

- No migration from old paths. Clean break.
- `.spawn.toml` (per-repo config) is unchanged.
- Directories auto-created on access.
