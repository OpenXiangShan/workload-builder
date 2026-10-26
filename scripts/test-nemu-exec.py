#!/usr/bin/env python3
"""Run the real fork/exec/wait launcher, replacing only the RISC-V trap."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TRAP = r'''#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static pid_t parent;
__attribute__((constructor)) static void init(void) { parent = getpid(); }
void trap(int code) {
    FILE *log = fopen(getenv("TRAP_LOG"), "a");
    if (!log) _exit(99);
    fprintf(log, "trap:%d\n", code);
    fclose(log);
    if (getpid() == parent) _exit(0);
    if (code == -1) _exit(1);
}
'''

with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    (tmp / "trap.c").write_text(TRAP)
    for profile in (0, 1):
        exe = tmp / f"nemu-exec-{profile}"
        subprocess.run([os.environ.get("CC", "cc"), "-Wall", "-Wextra", "-Werror",
                        f"-DNEMU_EXEC_PROFILE={profile}",
                        str(ROOT / "br2-external/package/nemu-exec/main.c"),
                        str(tmp / "trap.c"), "-o", str(exe)], check=True)
        for status in (0, 1):
            log = tmp / "events"
            log.write_text("")
            env = dict(os.environ, TRAP_LOG=str(log))
            subprocess.run([str(exe), "/bin/sh", "-c",
                            f'printf "workload\\n" >> "$TRAP_LOG"; exit {status}'],
                           env=env, check=True, timeout=5)
            expected = (["trap:256", "trap:257"] if profile else [])
            expected += ["workload", f"trap:{status << 8}"]
            assert log.read_text().splitlines() == expected, log.read_text()
        for command in ([], ["/this-command-does-not-exist"]):
            log.write_text("")
            subprocess.run([str(exe), *command], env=env, check=True, timeout=5)
            events = log.read_text().splitlines()
            assert "trap:-1" in events, events
    print("PASS: profiling enabled/disabled, actual exec, exit 0/1, missing command")
