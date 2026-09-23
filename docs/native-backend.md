---
title: Native Containerization Backend
nav_order: 8
---

# Native Containerization backend

`--backend native-experimental` launches a new workspace container through
Apple's Containerization Swift library. It is an explicit spike, not a new
default: `--backend cli` remains the stable path, and an explicitly selected
native launch never silently falls back to it.

Backend selection is independent of `--runtime`. The native backend receives
the same resolved image, mounts, environment, working directory, command, CPU,
memory, and I/O policy as the CLI adapter. `spawn --shell` launches a new
container and is supported. Operations on an existing CLI-managed container
remain CLI-only:

- `spawn exec <id> ...` and `spawn shell <id>`
- `spawn list` and `spawn stop <id>`
- image builds and management
- doctor probes

## Artifact ownership

The native backend does not open or mutate the `container` service's private
image store. The two implementations can otherwise become concurrent writers
to state whose ownership and locking contract is not public.
Its state root and temporary OCI export staging directory are user-only (mode
`0700`) because local image layers may contain private source or credentials.
Artifacts live under a Containerization-versioned directory because the
library reuses `initfs.ext4` without checking whether its reference changed.
Older caches remain available for explicit cleanup after an upgrade.

| Artifact | Source | Native ownership and lifetime |
|----------|--------|-------------------------------|
| OCI image | The local CLI image selected by spawn | Exported with `container image save`, securely extracted, then imported into `<state>/native-runtime/containerization-0.45.0/images`; refreshed when the inspected index digest changes |
| Linux kernel | The newest `vmlinux-*` installed by the CLI | Read in place, following Apple's Containerization examples; never copied or modified |
| initfs | `ghcr.io/apple/containerization/vminit:0.45.0` | Pulled by Containerization into the versioned image store and materialized there |
| cached rootfs | Imported image layers | Unpacked once into an immutable sparse ext4 image at `<state>/native-runtime/containerization-0.45.0/rootfs/<digest>.ext4` |
| launch rootfs | Cached rootfs | Copy-on-write clone under `<state>/native-runtime/containerization-0.45.0/images/containers/<id>/`, deleted after the launch |
| VM network | `VmnetNetwork` | Allocated per launch and released during container deletion |
| build caches | Existing host directories under `<state>/caches` | Unchanged; passed through the semantic mount plan and shared with the guest through VirtioFS |

A cross-process lock serializes mutations to the spawn-owned OCI, initfs, and
rootfs caches. It is released before the VM runs. Workspace build caches remain
ordinary bind-mounted directories and are not covered by this lock.

## API map

| Launch concern | Containerization API |
|----------------|----------------------|
| OCI import | `ImageStore.load(from:)` after `ContainerizationArchive.ArchiveReader` extraction |
| initfs and manager | `ContainerManager(kernel:initfsReference:imageStore:network:)` |
| root filesystem | `EXT4Unpacker`, then `Mount.clone(to:)` for each launch |
| workspace/cache mounts | `Mount.share(source:destination:options:)` |
| process and resources | `LinuxContainer.Configuration` process, CPU, and memory fields |
| lifecycle | `ContainerManager.create`, then `LinuxContainer.create/start/wait/stop` and `ContainerManager.delete` |
| terminal | `Terminal.current`, raw mode, resize events, and terminal process I/O |
| signals and init | Host dispatch signal sources, `LinuxContainer.kill`, and `configuration.useInit` |

`ResolvedLaunchPlan` intentionally contains none of the kernel, initfs, ext4,
or VM networking choices above. Those are adapter implementation details.

## Current spike limitations

- The first launch of a changed image pays an OCI export/import and ext4 unpack
  cost. Warm launches reuse the imported image and immutable rootfs.
- The ext4 rootfs is a 512 GB logical sparse file. For the current
  `spawn-base:latest`, the populated rootfs uses about 1.6 GB and the complete
  native cache about 2.4 GB of physical host storage; image contents and host
  filesystem behavior will change those figures.
- Native launches still require the CLI installation for the selected local
  image and installed kernel, even though the VM launch itself bypasses
  `container run`.
- The executable needs Apple's `com.apple.security.virtualization` entitlement.
  `make build` and `make install` ad-hoc sign the release binary with the
  checked-in `spawn.entitlements`; an unsigned `swift run spawn` build cannot
  launch this backend.
- Native artifacts have no garbage-collection command yet. This is the first
  follow-up before expanding native support: cached image and rootfs layers
  can occupy gigabytes, so reclamation and `spawn doctor` visibility should
  arrive together.
- Retained native containers are unsupported. A plan that requests one fails
  before artifact work begins.
- Native state is not yet included in `spawn doctor`; doctor remains a CLI
  readiness and workspace-resolution surface in this slice.
- Containerization 0.45.0's `AsyncSignalHandler.cancel()` recursively enters
  its own mutex through the stream termination callback. The adapter uses host
  dispatch signal sources until that upstream helper is safe to cancel.

The adapter enables init for every launch so termination signals reach the
workload and orphaned children are reaped. It forwards `SIGINT` and `SIGTERM`,
forwards `SIGWINCH` as a terminal resize, returns the workload's exit status,
and removes the per-launch container directory on both success and failure.
