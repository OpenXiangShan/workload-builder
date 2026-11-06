# speedometer

Speedometer 3.1 running in a Debian riscv64 Firefox, driven to completion
without any interaction and wired to NEMU's SimPoint profiler.

Build it through the top-level `make speedometer-image`, which passes the
benchmark configuration and clears the packed rootfs first. Building
`linux/speedometer` directly here also works, but the rootfs rule keys off this
directory rather than the run parameters, so a changed `SPEEDOMETER_*` value
will not rebuild the image on its own.

The full flow, the time model, the score projection and the checkpoint recipe
are documented in [docs/speedometer](../../../../docs/speedometer/README.md).

## Not in the default build

`make`, `make workloads` and `make tarball` skip this workload; `rules.mk`
registers the target without adding it to those sets. The image is assembled
from Debian packages fetched at build time, around 110 MB per build, and Debian
removes superseded packages from the pool. A pinned package being rebuilt
upstream turns the download into a 404, which would otherwise fail builds that
have nothing to do with this workload. Regenerating `links.txt` is the fix when
that happens.

## What ends up in the image

| Path in the image | Contents |
|-------------------|----------|
| `/opt/debian` | self-contained Debian tree; the browser runs chrooted into it |
| `/opt/debian/profile` | Firefox profile holding `user.js` |
| `/srv/speedometer` | the benchmark payload, served over loopback |
| `/usr/local/bin/bench-httpd` | static server and NEMU control endpoints |
| `/speedometer/boot.sh` | brings up loopback, mounts the chroot, starts both |
| `/speedometer/build.meta` | which browser, payload and URL this image runs |

## Files here

- `links.txt` — pinned Debian packages and the Speedometer archive, with
  checksums. Regenerate the package half with
  `scripts/speedometer/resolve_debian_closure.py`.
- `build.sh` — unpacks the packages, assembles the chroot, injects the harness
  hook, cross-compiles the server and writes the boot glue.
- `rules.mk` — registers `linux/speedometer` while keeping it out of the
  default build set.
- `inittab` — mounts the pseudo-filesystems and runs `boot.sh`.
- `files/bench-httpd.c` — the server. Also builds for the host, where the NEMU
  debug call degrades to a log line, so the serving logic can be exercised
  against a real Speedometer tree without booting a guest.
- `files/harness-hook.mjs` — wraps the benchmark client's lifecycle callbacks to
  mark the profiled region and report results.
- `files/user.js` — browser preferences; see the comments in the file for why
  each group is needed.
- `files/boot.sh` — guest startup, templated with the port and benchmark URL.

## Variables

`SPEEDOMETER_ITERATIONS` (default 10), `SPEEDOMETER_SUITES` (comma-separated,
empty runs the default set), `SPEEDOMETER_VIEWPORT`, `SPEEDOMETER_PORT`,
`SPEEDOMETER_LOG_REQUESTS` (`1` logs every HTTP request to the console; useful
during bring-up, noise in an archive run).

## Two things that will break it

`nemu-exec` must not be used. It sends debug call `0x100`, which masks the timer
interrupt, and the browser needs the timer tick to make progress. `boot.sh`
lets the server issue `0x101` on its own instead.

The pinned Debian versions expire, and quickly: sid rebuilds packages
constantly and removes the superseded files. A stale `links.txt` fails to
download rather than drifting silently. Regenerate it with
`scripts/speedometer/resolve_debian_closure.py` in the playground repository,
keeping the last line, which pins the Speedometer payload rather than a Debian
package.
