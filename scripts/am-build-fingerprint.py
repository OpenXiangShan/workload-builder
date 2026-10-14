#!/usr/bin/env python3
"""Content fingerprint for an AM build, excluding copied/generated build trees."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def tree(path):
    root = Path(path).resolve(strict=True)
    entries = {}
    for directory, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in ('.git', 'build', '__pycache__'))
        for name in sorted(files):
            file = Path(directory) / name
            if name == '.git':
                continue
            entries[str(file.relative_to(root))] = digest(file)
    return entries


def fingerprint(am_source, workload, download):
    settings = {name: os.environ.get(name, '') for name in
                ('AM_ARCH', 'ARCH', 'CPPFLAGS', 'CFLAGS', 'CXXFLAGS', 'ASFLAGS', 'LDFLAGS',
                 'CC_OPT', 'MARCH', 'mainargs', 'SYSROOT_DIR')}
    cross = os.environ['CROSS_COMPILE']
    tools = {}
    for suffix in ('gcc', 'g++', 'as', 'ld', 'ar', 'objcopy', 'objdump'):
        found = shutil.which(cross + suffix)
        if not found:
            raise RuntimeError('missing toolchain executable ' + cross + suffix)
        file = Path(found).resolve(strict=True)
        # Buildroot wrappers select the compiler using argv[0], not their resolved basename.
        version = subprocess.run([found, '--version'], check=True, capture_output=True).stdout.decode(errors='replace')
        tools[suffix] = {'command': found, 'path': str(file), 'sha256': digest(file), 'version': version}
        real = Path(found + '.br_real')
        if real.is_file():
            tools[suffix]['wrapped'] = {'path': str(real.resolve()), 'sha256': digest(real)}
    gcc = shutil.which(cross + 'gcc')
    for name in ('cc1', 'cc1plus', 'libgcc.a'):
        option = '-print-file-name=' if name == 'libgcc.a' else '-print-prog-name='
        found = subprocess.run([gcc, option + name], check=True, capture_output=True, text=True).stdout.strip()
        if not Path(found).is_file():
            found = shutil.which(found) or found
        file = Path(found).resolve(strict=True)
        tools[name] = {'path': str(file), 'sha256': digest(file)}
    data = {'format': 1, 'settings': settings, 'tools': tools,
            'am': tree(am_source), 'workload': tree(workload), 'download': tree(download)}
    data['helper'] = digest(Path(__file__))
    data['runner'] = digest(Path(__file__).with_name('build-workload-am.sh'))
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def package_fingerprint(package):
    files = tree(package)
    if not files:
        raise RuntimeError('AM package contains no artifacts')
    return hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--package')
    parser.add_argument('inputs', nargs='*')
    args = parser.parse_args()
    if args.package and not args.inputs:
        print(package_fingerprint(args.package))
    elif not args.package and len(args.inputs) == 3:
        print(fingerprint(*args.inputs))
    else:
        parser.error('provide AM source, workload and download, or --package PATH')
