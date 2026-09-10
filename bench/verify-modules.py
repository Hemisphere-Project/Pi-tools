#!/usr/bin/env python3
"""module.ini referential integrity — the else branch setup/installer.py lacks.

`install_module()` links bins and installs services, timers and udev rules under
`if os.path.isfile(src):` with no else. A module.ini naming a file that is not in
the repo therefore installs nothing, prints nothing, and returns success — the
box comes up missing a unit and the install log is clean. Same shape for
`script = yes` with no install.sh: the standard path silently takes over.

So, per module.ini (parsed with configparser, exactly as the installer does):

  * every path in files.bins / files.services / files.timers / files.udev_rules
    exists in the module directory
  * `script = yes` implies an install.sh
  * `npm = yes` implies a package.json (utils.npm_install runs npm there)
  * platforms names only tokens check_platform knows — anything else is not a
    platform, it is a module that silently skips on every machine

and across the set:

  * every name in MODULE_GROUPS / CORE_MODULES has a module.ini (the installer
    errors on this, but at install time, in the field, on one box)
  * a module.ini reachable from neither is reported as an ORPHAN — a WARNING,
    not a failure: unreachable-from-the-installer is a real finding, but it is a
    judgement about intent, and a gate that refuses every commit until someone
    resolves it would freeze the repo over a question nobody asked.

files.dirs / files.enable / files.mask name paths and units on the TARGET, not
in the repo, and are deliberately not checked here.

Not checked either: that the files do the right thing. That is layer 1's floor
and, past it, a bench.
"""

import ast
import configparser
import os
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else '.')
INSTALLER = os.path.join(ROOT, 'setup', 'installer.py')

# check_platform() tests these two and nothing else.
PLATFORMS = {'pi', 'x86'}

# Keys whose values are paths inside the module directory.
PATH_KEYS = ('bins', 'services', 'timers', 'udev_rules')

errors = []
warnings = []


def installer_literals():
    """Read MODULE_GROUPS / CORE_MODULES out of installer.py without importing
    it — the import pulls in the whole setup package and a bench has no reason
    to load it."""
    with open(INSTALLER, encoding='utf-8') as fh:
        tree = ast.parse(fh.read(), INSTALLER)
    found = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id in ('MODULE_GROUPS', 'CORE_MODULES'):
                found[target.id] = ast.literal_eval(node.value)
    return found


try:
    literals = installer_literals()
    groups = literals['MODULE_GROUPS']
    core = literals['CORE_MODULES']
except (OSError, SyntaxError, ValueError, KeyError) as exc:
    print(f'FAIL  cannot read MODULE_GROUPS/CORE_MODULES from setup/installer.py: {exc}')
    sys.exit(1)

declared = set(core)
for _key, _desc, names, _default in groups:
    declared.update(names)

present = set()
for entry in sorted(os.listdir(ROOT)):
    module_dir = os.path.join(ROOT, entry)
    ini_path = os.path.join(module_dir, 'module.ini')
    if not os.path.isfile(ini_path):
        continue
    present.add(entry)

    ini = configparser.ConfigParser()
    try:
        ini.read(ini_path)
    except configparser.Error as exc:
        errors.append(f'{entry}/module.ini does not parse: {exc}')
        continue

    platforms = ini.get('module', 'platforms', fallback='pi,x86')
    unknown = {p.strip() for p in platforms.split(',') if p.strip()} - PLATFORMS
    if unknown:
        errors.append(
            f'{entry}/module.ini: platforms {sorted(unknown)} — '
            f'not in {sorted(PLATFORMS)}, so the module installs nowhere')

    if ini.getboolean('install', 'script', fallback=False) \
            and not os.path.isfile(os.path.join(module_dir, 'install.sh')):
        errors.append(f'{entry}/module.ini: script = yes but {entry}/install.sh is missing')

    if ini.getboolean('files', 'npm', fallback=False) \
            and not os.path.isfile(os.path.join(module_dir, 'package.json')):
        errors.append(f'{entry}/module.ini: npm = yes but {entry}/package.json is missing')

    for key in PATH_KEYS:
        if not ini.has_option('files', key):
            continue
        for ref in ini.get('files', key).split():
            if not os.path.isfile(os.path.join(module_dir, ref)):
                errors.append(f'{entry}/module.ini: {key} names {ref}, which does not exist')

for name in sorted(declared - present):
    errors.append(f'installer lists module {name!r}, which has no module.ini')

for name in sorted(present - declared):
    warnings.append(
        f'{name}/module.ini is in neither MODULE_GROUPS nor CORE_MODULES — '
        f'setup/installer.py can never install it')

for line in errors:
    print(f'FAIL  {line}')
for line in warnings:
    print(f'warn  {line}')

if not errors:
    print(f'ok    {len(present)} module.ini, every file they name exists'
          + (f' ({len(warnings)} warning(s))' if warnings else ''))

sys.exit(1 if errors else 0)
