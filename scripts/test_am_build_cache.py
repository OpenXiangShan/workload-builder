#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
RUNNER = SCRIPTS / 'build-workload-am.sh'


class BuildCacheTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='am-cache-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.am = self.root / 'am-source'
        self.workload = self.root / 'hello'
        self.build = self.root / 'output'
        self.tools = self.root / 'tools'
        for directory in (self.am, self.workload, self.build / 'download', self.tools):
            directory.mkdir(parents=True)
        (self.am / 'startup.S').write_text('startup-v1\n')
        (self.am / 'build').mkdir()
        (self.am / 'build' / 'stale.o').write_text('must not be copied into the build\n')
        (self.build / 'download' / 'sentinel').touch()
        (self.workload / 'build.sh').write_text('''#!/usr/bin/env bash
set -euo pipefail
test ! -e "$AM_HOME/build/stale.o"
python3 - <<'PY'
import json, os
from pathlib import Path
root = Path(os.environ['WORKLOAD_BUILD_DIR'])
count = root / 'build-count'
count.write_text(str(int(count.read_text()) + 1 if count.exists() else 1))
if os.environ.get('FAIL_BUILD') == '1':
    raise SystemExit(7)
package = Path(os.environ['PKG_DIR'])
payload = {name: os.environ.get(name, '') for name in
           ('AM_ARCH', 'CPPFLAGS', 'CFLAGS', 'ASFLAGS', 'LDFLAGS', 'MARCH', 'mainargs')}
payload['source'] = (Path(os.environ['AM_HOME']) / 'startup.S').read_text()
(package / 'hello.bin').write_text(json.dumps(payload, sort_keys=True))
(package / 'hello.elf').write_text('elf')
PY
''')
        (self.tools / 'cc1').write_text('compiler-frontend-v1')
        (self.tools / 'cc1plus').write_text('cxx-frontend-v1')
        (self.tools / 'libgcc.a').write_text('compiler-library-v1')
        wrapper = self.tools / 'wrapper'
        wrapper.write_text('''#!/usr/bin/env python3
from pathlib import Path
import sys
name = Path(sys.argv[0]).name
if not name.startswith('test-'):
    raise SystemExit('wrapper basename lost')
arg = sys.argv[1]
if arg == '--version':
    print(name + ' test compiler v1')
elif arg.startswith(('-print-prog-name=', '-print-file-name=')):
    print(Path(sys.argv[0]).parent / arg.split('=', 1)[1])
else:
    raise SystemExit(2)
''')
        wrapper.chmod(0o755)
        for suffix in ('gcc', 'g++', 'as', 'ld', 'ar', 'objcopy', 'objdump'):
            (self.tools / ('test-' + suffix)).symlink_to(wrapper.name)
        (self.tools / 'test-gcc.br_real').write_text('wrapped-driver-v1')
        self.env = {key: value for key, value in os.environ.items() if key not in
                    ('ARCH', 'AM_ARCH', 'CPPFLAGS', 'CFLAGS', 'CXXFLAGS', 'ASFLAGS', 'LDFLAGS',
                     'MARCH', 'CC_OPT', 'mainargs', 'CROSS_COMPILE', 'MAKEFLAGS')}
        self.env.update(CROSS_COMPILE=str(self.tools / 'test-'), AM_ARCH='riscv64-nutshell')

    def run_build(self, **settings):
        return subprocess.run(['bash', str(RUNNER), str(self.workload), str(self.build), str(self.am)],
                              env=dict(self.env, **settings), text=True, capture_output=True, timeout=30)

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def count(self):
        return int((self.build / 'build-count').read_text())

    def test_cache_hit_preserves_artifact_and_sentinel(self):
        self.assert_success(self.run_build())
        artifact = self.build / 'package' / 'hello.bin'
        times = (artifact.stat().st_mtime_ns, (self.build / 'sentinel').stat().st_mtime_ns)
        result = self.run_build()
        self.assert_success(result)
        self.assertIn('AM build cache hit:', result.stdout)
        self.assertEqual(self.count(), 1)
        self.assertEqual(times, (artifact.stat().st_mtime_ns, (self.build / 'sentinel').stat().st_mtime_ns))

    def test_source_content_changes_with_equal_timestamp(self):
        self.assert_success(self.run_build())
        source = self.am / 'startup.S'
        old = source.stat()
        source.write_text('startup-v2\n')
        os.utime(source, ns=(old.st_atime_ns, old.st_mtime_ns))
        self.assert_success(self.run_build())
        self.assertEqual(self.count(), 2)
        self.assertIn('startup-v2', (self.build / 'package' / 'hello.bin').read_text())

    def test_architecture_and_options_invalidate(self):
        self.assert_success(self.run_build())
        settings = {}
        for name, value in [('AM_ARCH', 'riscv64-xs'), ('CPPFLAGS', '-DUART16550=1 -DOTHER=2'),
                            ('CFLAGS', '-DTEST=1'), ('CXXFLAGS', '-DCPP=1'), ('ASFLAGS', '-DASM=1'),
                            ('LDFLAGS', '--gc-sections'), ('MARCH', 'rv64imac_zicsr'),
                            ('CC_OPT', '-O3'), ('mainargs', 'hello world')]:
            settings[name] = value
            self.assert_success(self.run_build(**settings))
        self.assertEqual(self.count(), 10)
        payload = json.loads((self.build / 'package' / 'hello.bin').read_text())
        self.assertEqual(payload['CPPFLAGS'], '-DUART16550=1 -DOTHER=2')

    def test_toolchain_content_invalidation_and_wrapper_argv0(self):
        self.assert_success(self.run_build())
        for name in ('wrapper', 'cc1', 'cc1plus', 'libgcc.a', 'test-gcc.br_real'):
            file = self.tools / name
            file.write_text(file.read_text() + '\n')
            self.assert_success(self.run_build())
        self.assertEqual(self.count(), 6)

    def test_build_and_git_metadata_do_not_invalidate(self):
        self.assert_success(self.run_build())
        (self.am / 'build' / 'stale.o').write_text('new generated output')
        (self.am / '.git').write_text('gitdir: unrelated metadata')
        result = self.run_build()
        self.assert_success(result)
        self.assertIn('cache hit:', result.stdout)
        self.assertEqual(self.count(), 1)

    def test_workload_and_download_content_invalidate(self):
        self.assert_success(self.run_build())
        (self.workload / 'build.sh').write_text((self.workload / 'build.sh').read_text() + '\n')
        self.assert_success(self.run_build())
        (self.build / 'download' / 'input.txt').write_text('downloaded source')
        self.assert_success(self.run_build())
        self.assertEqual(self.count(), 3)

    def test_missing_or_corrupt_package_rebuilds(self):
        self.assert_success(self.run_build())
        (self.build / 'package' / 'hello.elf').unlink()
        self.assert_success(self.run_build())
        (self.build / 'package' / 'hello.bin').write_text('corrupt')
        self.assert_success(self.run_build())
        self.assertEqual(self.count(), 3)
        self.assertEqual((self.build / 'package' / 'hello.elf').read_text(), 'elf')

    def test_failed_build_is_never_cached(self):
        self.assert_success(self.run_build())
        old = (self.build / '.am-build-fingerprint').read_text()
        self.assertEqual(self.run_build(CPPFLAGS='-DNEW=1', FAIL_BUILD='1').returncode, 7)
        self.assertEqual((self.build / '.am-build-fingerprint').read_text(), old)
        self.assert_success(self.run_build(CPPFLAGS='-DNEW=1'))
        self.assertEqual(self.count(), 3)

    def test_missing_tool_fails_before_cache_hit(self):
        self.assert_success(self.run_build())
        (self.tools / 'test-objcopy').unlink()
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing toolchain executable', result.stderr)
        self.assertEqual(self.count(), 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
