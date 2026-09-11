"""Run: python3 -m unittest discover -s dts -p 'test_*.py' -v.

Set WORKLOAD_BUILDER to a checkout and DTC/FDTGET for firmware integration.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from DTSGen import DTSGen

HERE = Path(__file__).resolve().parent
DTC = os.environ.get("DTC") or shutil.which("dtc")
FDTGET = os.environ.get("FDTGET") or shutil.which("fdtget")
BUILDER = os.environ.get("WORKLOAD_BUILDER")


def generate(*args, check=True):
    return subprocess.run([sys.executable, str(HERE / "generate-workload-builder-dts.py"),
                           *map(str, args)], text=True, capture_output=True, check=check)


class GeneratorTests(unittest.TestCase):
    def test_reservations_do_not_leak_between_instances(self):
        first = DTSGen()
        first.add_reserved_memory(0x80000000, 0x100000)
        self.assertNotIn("reserved-memory", DTSGen().gen_dts())

    def test_generated_rng_seed_is_annotated(self):
        self.assertIn('/* ASCII: "XIANGSHAN_NEMU_BOARD_RANDOM_SEED" */',
                      DTSGen().gen_dts())

    def test_existing_cli_timebase_is_applied(self):
        result = subprocess.run([sys.executable, str(HERE / "DTSGen.py"),
                                 "--timebase-freq", "1000000"],
                                check=True, text=True, capture_output=True)
        self.assertIn("timebase-frequency = <1000000>;", result.stdout)

    def test_vector_filter_preserves_rv64_prefix(self):
        text = generate("--profile", "qemu-nemu", "--no-vector").stdout
        self.assertRegex(text, r'riscv,isa = "rv64imafdch_')
        self.assertNotRegex(text, r'"(?:v|zv[^"]*)"')
        self.assertNotIn("sstc", text)

    def test_isa_override_is_replacement(self):
        text = generate("--isa-extensions", "i", "m", "a", "zicsr").stdout
        self.assertIn('riscv,isa-extensions = "i", "m", "a", "zicsr";', text)
        self.assertNotIn('"smcntrpmf"', text)

    def test_kunminghu_isa_configs(self):
        default = generate().stdout
        self.assertIn(
            'riscv,isa = "rv64imafdch_smstateen_sscofpmf_sstc_zicntr_zihpm_'
            'svpbmt_sdtrig_smcsrind_sscsrind_svade";', default)

        v2 = generate("--isa-config", "kunminghu-v2").stdout
        self.assertIn(
            'riscv,isa = "rv64imafdcvh_smstateen_sscofpmf_sstc_zicntr_zihpm_'
            'svpbmt_sdtrig_smcsrind_sscsrind_svade";', v2)
        self.assertIn('riscv,isa-base = "rv64i";', v2)
        value = re.search(r"riscv,isa-extensions = (?P<value>.*?);", v2, re.DOTALL)["value"]
        self.assertEqual(re.findall(r'"([^"]+)"', value), """
            i m a f d c h sdtrig sha shcounterenw shgatpa shlcofideleg
            shtvala shvsatpa shvstvala shvstvecd smcsrind smdbltrp smmpm
            smnpm smstateen ss1p13 ssccptr sscofpmf sscounterenw sscsrind
            ssdbltrp ssnpm sspm ssstateen ssstrict sstc sstvala sstvecd
            ssu64xl supm sv39 sv48 svade svbare svinval svnapot svpbmt
            za64rs zacas zawrs zba zbb zbc zbkb zbkc zbkx zbs zca zcb
            zcmop zfa zfh zfhmin zic64b ziccamoa ziccif zicclsm ziccrse
            zicntr zicond zicsr zifencei zihintntl zihintpause zihpm zimop
            zkn zknd zkne zknh zksed zksh zkt
        """.split())

    def test_invalid_configs_fail(self):
        for args in [
            ("--harts", "129"), ("--harts", "2"),
            ("--profile", "nemu", "--harts", "2"),
            ("--memory-size", "0"),
            ("--profile", "nemu", "--memory-size", "0x400000"),
            ("--profile", "qemu-nemu", "--harts", "2", "--memory-size", "0x8600000"),
            ("--isa-extensions", "i", "smaia"),
            ("--isa-extensions", "i", "zvbb"),
            ("--isa-extensions", "i", "v"),
            ("--profile", "nemu", "--isa-config", "kunminghu-v2"),
            ("--exclude-isa", "i"), ("--output", "wrong.dtb"),
        ]:
            with self.subTest(args=args):
                result = generate(*args, check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    @unittest.skipUnless(BUILDER, "WORKLOAD_BUILDER not set")
    def test_builder_wrapper_generation(self):
        script = Path(BUILDER) / "scripts/generate-nemu-board-dts.py"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, has_checkpoint in [
                    ("xiangshan-qemu-nemu-mem2g", False),
                    ("xiangshan-qemu-nemu-2hart-mem16g", True),
            ]:
                with self.subTest(name=name):
                    output = root / f"{name}.dts.in"
                    subprocess.run([sys.executable, str(script), "--name", name,
                                    "--output", str(output)], check=True)
                    text = output.read_text()
                    checkpoint = re.search(
                        r"checkpoint@80300000\s*\{(?P<body>.*?)\};", text, re.DOTALL)
                    self.assertEqual(checkpoint is not None, has_checkpoint)
                    if checkpoint:
                        self.assertIn(
                            "reg = <0x0 0x80300000 0x0 0x08300000>;",
                            checkpoint["body"])
                        self.assertIn("no-map;", checkpoint["body"])

            fpga_name = "xiangshan-fpga-noAIA-mem16g-novec"
            v3 = root / "v3.dts.in"
            subprocess.run([sys.executable, str(script), "--name", fpga_name,
                            "--output", str(v3)], check=True)
            explicit_v3 = root / "explicit-v3.dts.in"
            subprocess.run([sys.executable, str(script), "--name", fpga_name,
                            "--output", str(explicit_v3),
                            "--isa-config", "kunminghu-v3"], check=True)
            self.assertEqual(v3.read_text(), explicit_v3.read_text())

            v2 = root / "v2.dts.in"
            subprocess.run([sys.executable, str(script), "--name", fpga_name,
                            "--output", str(v2),
                            "--isa-config", "kunminghu-v2"], check=True)
            v2_text = v2.read_text()
            self.assertIn('riscv,isa = "rv64imafdch_', v2_text)
            self.assertIn('"ss1p13"', v2_text)
            self.assertNotIn('"v"', v2_text)

            vector_v2 = root / "vector-v2.dts.in"
            subprocess.run([
                sys.executable, str(script), "--name", "xiangshan-fpga-noAIA-mem16g",
                "--output", str(vector_v2), "--isa-config", "kunminghu-v2",
            ], check=True)
            self.assertIn('riscv,isa = "rv64imafdcvh_', vector_v2.read_text())
            self.assertIn('"v"', vector_v2.read_text())

            invalid_profile = subprocess.run([
                sys.executable, str(script), "--name", "xiangshan-qemu-nemu-mem2g",
                "--output", str(root / "qemu-v2.dts.in"),
                "--isa-config", "kunminghu-v2",
            ], text=True, capture_output=True)
            self.assertNotEqual(invalid_profile.returncode, 0)
            self.assertIn("--isa-config is supported by the FPGA noAIA profile only",
                          invalid_profile.stderr)

            custom = root / "custom.dts.in"
            custom.write_text("custom template\n")
            subprocess.run([
                sys.executable, str(script), "--name", "custom",
                "--output", str(custom), "--isa-config", "kunminghu-v2",
                "--preserve-existing-unsupported",
            ], check=True)
            self.assertEqual(custom.read_text(), "custom template\n")

            missing = root / "missing.dts.in"
            result = subprocess.run([
                sys.executable, str(script), "--name", "missing",
                "--output", str(missing), "--preserve-existing-unsupported",
            ], text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unsupported DTS basename: missing", result.stderr)

            custom_dir = root / "dts"
            custom_dir.mkdir()
            (custom_dir / "vendor-board.dts.in").write_text("vendor template\n")
            copied = root / "vendor-board.dts.in"
            subprocess.run([
                sys.executable, str(script), "--name", "vendor-board",
                "--output", str(copied), "--custom-template-dir", str(custom_dir),
            ], check=True)
            self.assertEqual(copied.read_text(), "vendor template\n")

            absent_dir = root / "absent-dts" / "absent-board.dts.in"
            absent = subprocess.run([
                sys.executable, str(script), "--name", "absent-board",
                "--output", str(absent_dir), "--custom-template-dir",
                str(custom_dir),
            ], text=True, capture_output=True)
            self.assertNotEqual(absent.returncode, 0)
            self.assertFalse(absent_dir.exists())

            recognized = root / "xiangshan.dts.in"
            recognized.write_text("stale generated template\n")
            subprocess.run([
                sys.executable, str(script), "--name", "xiangshan",
                "--output", str(recognized), "--preserve-existing-unsupported",
            ], check=True)
            self.assertTrue(recognized.read_text().startswith(
                "/* Generated by nemu_board for workload-builder. */"))

    @unittest.skipUnless(BUILDER, "WORKLOAD_BUILDER not set")
    def test_fpga_isa_matches_existing_template(self):
        original = (Path(BUILDER) / "dts/xiangshan-fpga-noAIA-novec.dts.in").read_text()
        output = generate().stdout
        def extensions(text):
            value = re.search(r"riscv,isa-extensions\s*=([^;]+);", text)[1]
            return set(re.findall(r'"([^"]+)"', value))
        self.assertEqual(extensions(original), extensions(output))
        self.assertEqual(re.search(r'riscv,isa = "[^"]+";', original)[0],
                         re.search(r'riscv,isa = "[^"]+";', output)[0])
        self.assertNotIn("riscv,cbop-block-size", output)
        self.assertIn("timebase-frequency = <1000000>;", output)
        soc = re.search(r"    soc \{\n(?P<body>.*)\n    \};", output, re.DOTALL)["body"]
        self.assertIn('compatible = "freechips,rocketchip-unknown-soc", "simple-bus";', soc)
        self.assertIn("clint: clint@38000000", soc)
        self.assertIn("plic: interrupt-controller@3c000000", soc)
        self.assertEqual(soc.count('reg-names = "control";'), 3)

    @unittest.skipUnless(DTC and FDTGET and BUILDER, "DTC, FDTGET and WORKLOAD_BUILDER required")
    def test_builder_isa_config_reaches_packed_dtb(self):
        name = "xiangshan-fpga-noAIA-mem16g-novec"
        dtbs = {}
        for isa_config, expected, absent in [
                (None, "zicbom", "zca"),
                ("kunminghu-v3", "zicbom", "zca"),
                ("kunminghu-v2", "zca", "zicbom")]:
            with self.subTest(isa_config=isa_config), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                templates = root / "templates"
                gcpt, kernel = root / "gcpt.bin", root / "Image"
                gcpt.write_bytes(b"GCPT" * 16)
                kernel.write_bytes(b"KERNEL" * 1024)
                sbi_dir = root / "sbi"
                sbi = sbi_dir / "build/platform/generic/firmware/fw_jump.bin"
                sbi.parent.mkdir(parents=True)
                sbi.write_bytes(b"SBI" * 128)
                workload = root / "workload"
                workload.mkdir()
                (workload / "rootfs.cpio").write_bytes(b"INITRAMFS" * 1024)
                env = dict(os.environ, DTC=str(DTC), DEFAULT_DTB=name,
                           MULTIHART="0", HARTS="1")
                for key in ("DTB_MEMORY_PROFILE", "DTB_MIN_MEMORY_BYTES",
                            "DTB_REQUIRED_MIN_MEMORY_BYTES", "FIRMWARE_OUTPUT"):
                    env.pop(key, None)
                if isa_config:
                    env["DTS_ISA_CONFIG"] = isa_config
                else:
                    env.pop("DTS_ISA_CONFIG", None)
                packed = subprocess.run(
                    ["bash", str(Path(BUILDER) / "scripts/build-firmware-linux.sh"),
                     str(gcpt), str(sbi_dir), str(templates), str(kernel), str(workload)],
                    env=env, text=True, capture_output=True)
                self.assertEqual(packed.returncode, 0, packed.stderr)
                dtb = workload / "dt" / f"{name}.dtb"
                extensions = subprocess.check_output(
                    [str(FDTGET), str(dtb), "/cpus/cpu@0", "riscv,isa-extensions"],
                    text=True).split()
                self.assertIn(expected, extensions)
                self.assertNotIn(absent, extensions)
                dtbs[isa_config] = dtb.read_bytes()
        self.assertEqual(dtbs[None], dtbs["kunminghu-v3"])
        self.assertNotEqual(dtbs[None], dtbs["kunminghu-v2"])

    @unittest.skipUnless(DTC and FDTGET and BUILDER, "DTC, FDTGET and WORKLOAD_BUILDER required")
    def test_real_builder_packs_generated_templates(self):
        for profile, harts, memory_gib in [
            ("fpga-noaia-novec", 1, 2), ("nemu", 1, None),
            ("qemu-nemu", 1, 8), ("qemu-nemu", 2, 16), ("qemu-nemu", 128, 64),
        ]:
            with self.subTest(profile=profile, harts=harts), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                templates = root / "templates"
                args = ["--profile", profile, "--harts", harts,
                        "--output", templates / "generated.dts.in"]
                if memory_gib:
                    args += ["--memory-gib", memory_gib]
                generate(*args)
                # Distinct small payloads exercise packaging, not CPU execution.
                gcpt, kernel = root / "gcpt.bin", root / "Image"
                gcpt.write_bytes(b"GCPT" * 16)
                kernel.write_bytes(b"KERNEL" * 1024)
                sbi_dir = root / "sbi"
                sbi = sbi_dir / "build/platform/generic/firmware/fw_jump.bin"
                sbi.parent.mkdir(parents=True)
                sbi.write_bytes(b"SBI" * 128)
                workload = root / "workload"
                workload.mkdir()
                initrd = workload / "rootfs.cpio"
                initrd.write_bytes(b"INITRAMFS" * 1024)
                env = dict(os.environ, DTC=str(DTC), DEFAULT_DTB="generated",
                           MULTIHART="1" if harts > 1 else "0", HARTS=str(harts))
                for key in ("DTB_MEMORY_PROFILE", "DTB_MIN_MEMORY_BYTES",
                            "DTB_REQUIRED_MIN_MEMORY_BYTES", "FIRMWARE_OUTPUT"):
                    env.pop(key, None)
                packed = subprocess.run(
                    ["bash", str(Path(BUILDER) / "scripts/build-firmware-linux.sh"),
                     str(gcpt), str(sbi_dir), str(templates), str(kernel), str(workload)],
                    env=env, text=True, capture_output=True)
                self.assertEqual(packed.returncode, 0, packed.stderr)
                dtb = workload / "dt/generated.dtb"
                def prop(node, name):
                    value = subprocess.check_output(
                        [str(FDTGET), "-t", "x", str(dtb), node, name], text=True)
                    return [int(cell, 16) for cell in value.split()]
                self.assertEqual(prop("/cpus", "timebase-frequency"), [1000000])
                size = (memory_gib << 30) if memory_gib else (128 << 20)
                self.assertEqual(prop("/memory@80000000", "reg"),
                                 [0, 0x80000000, size >> 32, size & 0xffffffff])
                cpus = subprocess.check_output(
                    [str(FDTGET), "-l", str(dtb), "/cpus"], text=True).split()
                self.assertEqual(len(cpus), harts)
                self.assertEqual(prop(f"/cpus/cpu@{harts - 1:x}", "reg"), [harts - 1])
                interrupt_parent = "/soc/" if profile == "fpga-noaia-novec" else "/"
                plic_name = ("interrupt-controller@3c000000"
                             if profile == "fpga-noaia-novec" else "plic@3c000000")
                for name, irqs in (("clint@38000000", (3, 7)), (plic_name, (11, 9))):
                    actual = prop(interrupt_parent + name, "interrupts-extended")
                    if name.startswith("plic") and profile == "nemu":
                        irqs = (9, 11)
                    self.assertEqual(actual[1::2], list(irqs) * harts)
                    expected_handles = []
                    for hart in range(harts):
                        handle = prop(f"/cpus/cpu@{hart:x}/interrupt-controller", "phandle")[0]
                        expected_handles.extend([handle, handle])
                    self.assertEqual(actual[0::2], expected_handles)
                if profile == "fpga-noaia-novec":
                    def strings(node, name):
                        value = subprocess.check_output(
                            [str(FDTGET), str(dtb), node, name], text=True)
                        return value.split()
                    self.assertEqual(strings("/soc", "compatible"),
                                     ["freechips,rocketchip-unknown-soc", "simple-bus"])
                    self.assertEqual(strings("/soc/clint@38000000", "reg-names"),
                                     ["control"])
                    self.assertEqual(strings(
                        "/soc/interrupt-controller@3c000000", "reg-names"),
                        ["control"])
                    self.assertEqual(prop("/cpus/cpu@0", "timebase-frequency"),
                                     [1000000])
                if harts > 1:
                    self.assertEqual(prop("/reserved-memory/checkpoint@80300000", "reg"),
                                     [0, 0x80300000, 0, 0x8300000])
                start = prop("/chosen", "linux,initrd-start")
                end = prop("/chosen", "linux,initrd-end")
                initrd_start = (start[0] << 32) | start[1]
                initrd_end = (end[0] << 32) | end[1]
                self.assertEqual(initrd_end - initrd_start, initrd.stat().st_size)
                with (workload / "fw_payload.bin").open("rb") as image:
                    self.assertEqual(image.read(gcpt.stat().st_size), gcpt.read_bytes())
                    image.seek(1024 * 1024)
                    self.assertEqual(image.read(sbi.stat().st_size), sbi.read_bytes())
                    image.seek(2048 * 1024)
                    self.assertEqual(image.read(dtb.stat().st_size), dtb.read_bytes())
                    image.seek(0x08600000 if harts > 1 else 0x00400000)
                    self.assertEqual(image.read(kernel.stat().st_size), kernel.read_bytes())
                    image.seek(initrd_start - 0x80000000)
                    self.assertEqual(image.read(), initrd.read_bytes())


if __name__ == "__main__":
    unittest.main()
