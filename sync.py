"""Copy the library into each addon's Libs/EverythingUI/. A dry run unless --write is given.

    python sync.py                  # every addon in addons.py
    python sync.py EQOT             # one addon
    python sync.py EQOT --write
"""
import difflib
import os
import re
import sys

import addons

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = os.path.dirname(os.path.abspath(__file__))
DEST = os.path.join('Libs', 'EverythingUI')
XML = 'EverythingUI.xml'
MAIN = 'EverythingUI.lua'
TEXT_EXTS = ('.lua', '.xml', '.txt', '.md')
SKIP_NAMES = {'Thumbs.db', 'Desktop.ini', '.DS_Store'}
MINOR_RE = re.compile(rb'^local MAJOR, MINOR = "EverythingUI-1\.0", (\d+)\s*$', re.M)
SCRIPT_RE = re.compile(r'<Script\s+file="([^"]+)"')


def read(path):
    with open(path, 'rb') as f:
        return f.read()


def is_text(rel):
    return rel.endswith(TEXT_EXTS) or os.path.basename(rel) == 'LICENSE'


def comparable(path, rel):
    # Everything Quests checks text out as CRLF and the other hosts as LF, so line endings
    # alone must not read as a change or trip the MINOR guard.
    data = read(path)
    return data.replace(b'\r\n', b'\n') if is_text(rel) else data


def walk(base):
    out = []
    for dirpath, dirnames, names in os.walk(base):
        dirnames.sort()
        for name in sorted(names):
            if name in SKIP_NAMES or name.startswith('.'):
                continue
            out.append(os.path.relpath(os.path.join(dirpath, name), base).replace(os.sep, '/'))
    return out


def payload():
    xml = read(os.path.join(ROOT, XML)).decode('utf-8')
    files = [XML] + [s.replace('\\', '/') for s in SCRIPT_RE.findall(xml)] + ['LICENSE']
    files += ['Media/' + rel for rel in walk(os.path.join(ROOT, 'Media'))]
    missing = [rel for rel in files if not os.path.isfile(os.path.join(ROOT, rel))]
    return files, missing


def minor_in(folder):
    m = MINOR_RE.search(read(os.path.join(folder, MAIN)))
    return int(m.group(1)) if m else None


def unified(target_path, source_path, rel):
    old = read(target_path).decode('utf-8', 'replace').splitlines()
    new = read(source_path).decode('utf-8', 'replace').splitlines()
    return difflib.unified_diff(old, new, 'target/' + rel, 'source/' + rel, lineterm='')


def prune(base):
    for dirpath, _, _ in sorted(os.walk(base), key=lambda w: -len(w[0])):
        if dirpath != base and not os.listdir(dirpath):
            os.rmdir(dirpath)


def sync_one(key, files, src_minor, write):
    cfg = addons.ADDONS[key]
    target = os.path.join(cfg['path'], DEST)
    print('%s  %s' % (key, target))
    if not os.path.isdir(cfg['path']):
        print('  repo not found')
        return False, False

    has_copy = os.path.isfile(os.path.join(target, MAIN))
    tgt_minor = minor_in(target) if has_copy else None
    print('  minor: source %d, target %s' % (
        src_minor, ('unreadable' if tgt_minor is None else tgt_minor) if has_copy else 'none'))

    added, changed = [], []
    for rel in files:
        tp = os.path.join(target, rel)
        if not os.path.isfile(tp):
            added.append(rel)
        elif comparable(tp, rel) != comparable(os.path.join(ROOT, rel), rel):
            changed.append(rel)
    wanted = set(files)
    removed = [rel for rel in walk(target) if rel not in wanted] if os.path.isdir(target) else []

    if not (added or changed or removed):
        print('  no difference')
        return True, False

    for rel in added:
        print('  + ' + rel)
    for rel in changed:
        print('  ~ ' + rel)
    for rel in removed:
        print('  - ' + rel)
    for rel in changed:
        if is_text(rel):
            for line in unified(os.path.join(target, rel), os.path.join(ROOT, rel), rel):
                print('    ' + line)

    if has_copy and (tgt_minor is None or src_minor <= tgt_minor):
        print('  REFUSED: the library differs but MINOR %d is not above the target\'s %s. '
              'Raise MINOR in %s first.' % (src_minor, tgt_minor, MAIN))
        return False, True

    if write:
        for rel in added + changed:
            dest = os.path.join(target, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, 'wb') as f:
                f.write(read(os.path.join(ROOT, rel)))
        for rel in removed:
            os.remove(os.path.join(target, rel))
        prune(target)
        print('  written: %d added, %d changed, %d removed' % (len(added), len(changed), len(removed)))
    return True, True


def main(argv):
    write = '--write' in argv
    args = [a for a in argv if a != '--write']
    by_lower = {k.lower(): k for k in addons.ADDONS}
    keys = []
    for a in args:
        if a.lower() not in by_lower:
            print('unknown addon %r. Known: %s' % (a, ', '.join(addons.ADDONS)))
            return 2
        keys.append(by_lower[a.lower()])
    keys = keys or list(addons.ADDONS)

    src_minor = minor_in(ROOT)
    if src_minor is None:
        print('cannot read MINOR from %s' % MAIN)
        return 1
    files, missing = payload()
    if missing:
        for rel in missing:
            print('missing from the library: ' + rel)
        return 1
    print('source minor %d, %d files' % (src_minor, len(files)))

    all_ok, pending = True, False
    for key in keys:
        print('')
        ok, differs = sync_one(key, files, src_minor, write)
        all_ok = all_ok and ok
        pending = pending or (differs and ok and not write)

    if pending:
        print('\nDRY RUN - re-run with --write to apply')
    return 0 if all_ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
