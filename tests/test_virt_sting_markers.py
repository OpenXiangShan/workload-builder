"""Exercise the generated Host launcher with Guest UART output."""
import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/build-virtual-workload.py"
spec = importlib.util.spec_from_file_location("bvw", SCRIPT)
bvw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bvw)


class VirtStingMarkerTests(unittest.TestCase):
    def run_guest(self, output, sting, baremetal=False):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            qemu = root / "qemu"
            qemu.write_text("#!/bin/sh\nprintf '%s\\n' \"$GUEST_OUTPUT\"\n")
            qemu.chmod(0o755)
            trap = root / "nemu-trap"
            trap.write_text('#!/bin/sh\nexit "$1"\n')
            trap.chmod(0o755)
            parameter = root / "sting_5006b_shutdown"
            parameter.write_text("1\n")
            script = root / "init.sh"
            script.write_text(
                bvw.host_init_script(1, "8G", baremetal=baremetal or sting, sting=sting).replace(
                    "/sys/module/kvm/parameters/sting_5006b_shutdown", str(parameter)
                )
            )
            subprocess.run(["sh", "-n", str(script)], check=True)
            env = dict(os.environ, VIRT_RUN_DIR=str(root / "run"),
                       VIRT_KMSG=str(root / "kmsg"), VIRT_QEMU_BIN=str(qemu),
                       VIRT_NEMU_TRAP=str(trap), VIRT_TEST_NO_POWEROFF="1",
                       GUEST_OUTPUT=output)
            result = subprocess.run(["sh", str(script)], env=env,
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(parameter.read_text(), "0\n" if sting else "1\n")
            return result.returncode

    def test_sting_requires_uart_status(self):
        for output, status in (
            ("STING Test Status: PASS\r", 0),
            ("VIRT_WORKLOAD_EXIT=0\nSTING Test Status: PASS", 0),
            ("VIRT_WORKLOAD_EXIT=0", 1),
            ("STING Test Status: FAIL", 1),
            ("ERROR MESSAGE STARTS", 1),
            ("unrelated Status: PASS", 1),
        ):
            with self.subTest(output=output):
                self.assertEqual(self.run_guest(output, True), status)

    def test_linux_uses_exit_marker(self):
        for output, status in (
            ("VIRT_WORKLOAD_EXIT=0", 0),
            ("VIRT_WORKLOAD_EXIT=7", 7),
            ("STING Test Status: PASS", 1),
            ("VIRT_WORKLOAD_EXIT=0\nVIRT_WORKLOAD_EXIT=0", 1),
        ):
            with self.subTest(output=output):
                self.assertEqual(self.run_guest(output, False), status)

    def test_sting_uses_kvm_m_mode(self):
        argv = bvw.qemu_argv(1, "8G", baremetal=True, sting=True)
        self.assertEqual(argv[argv.index("-machine") + 1],
                         "virt,aia=none,kvm-m-mode=on,kvm-nested=on")
        self.assertEqual(argv[argv.index("-accel") + 1], "kvm")
        self.assertEqual(argv[argv.index("-serial") + 1], "none")
        self.assertNotIn("-initrd", argv)

    def test_normal_baremetal_uses_original_contract(self):
        for output, status in (
            ("VIRT_WORKLOAD_EXIT=0", 0),
            ("VIRT_WORKLOAD_EXIT=7", 7),
            ("STING Test Status: PASS", 1),
        ):
            with self.subTest(output=output):
                self.assertEqual(self.run_guest(output, False, baremetal=True), status)
        argv = bvw.qemu_argv(1, "8G", baremetal=True)
        self.assertEqual(argv[argv.index("-machine") + 1], "virt,aia=none")
        self.assertEqual(argv[argv.index("-serial") + 1], "stdio")
        self.assertNotIn("-initrd", argv)


if __name__ == "__main__":
    unittest.main()
