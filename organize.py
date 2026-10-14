#!/usr/bin/env python3
"""Files new items from Downloads/Desktop/Documents into ~/2026/<MM_Month>/<Project>/.

Classification is done by the `claude` CLI. Run with --dry-run to see the plan without moving.
Every move is appended to _move_log.tsv (undo with _undo_moves.sh).
"""
import calendar, datetime, json, os, shutil, subprocess, sys, time

H = os.path.expanduser('~')
ROOT = os.path.join(H, '2026')
CLAUDE = os.path.join(H, '.local/bin/claude')
WATCH = ['Downloads', 'Desktop', 'Documents']
KEEP = {'Documents/Codex', 'Documents/Adobe'}                      # never touched
PARTIAL = ('.crdownload', '.download', '.part', '.tmp')
MIN_AGE = 10 * 60                               # skip files still being written/downloaded
DRY = '--dry-run' in sys.argv

SKEL = (['01_Research', '02_Inspiration']
        + ['03_Assets/' + x for x in 'Images Icons Illustrations Logos Fonts Templates'.split()]
        + ['04_Working_Files/V0%d' % i for i in range(1, 6)]
        + ['05_Exports/' + x for x in 'JPG PNG PDF SVG'.split()]
        + ['06_Mockups', '07_Final', '99_Archive'])


def existing_projects():
    projects = {}
    for month in sorted(os.listdir(ROOT)):
        mpath = os.path.join(ROOT, month)
        if month[:2].isdigit() and os.path.isdir(mpath):
            for p in os.listdir(mpath):
                if os.path.isdir(os.path.join(mpath, p)):
                    projects[p] = os.path.join(mpath, p)
    return projects


def versions_summary(path):
    wf = os.path.join(path, '04_Working_Files')
    used = [v for v in sorted(os.listdir(wf)) if os.listdir(os.path.join(wf, v))] if os.path.isdir(wf) else []
    return ','.join(used) or 'none'


def candidates():
    now = time.time()
    for base in WATCH:
        try:
            names = sorted(os.listdir(os.path.join(H, base)))
        except PermissionError:
            print(f'Skipping ~/{base}: macOS blocked access (System Settings > Privacy & Security > Files and Folders)')
            continue
        for n in names:
            rel = f'{base}/{n}'
            full = os.path.join(H, rel)
            if n.startswith('.') or rel in KEEP or n.endswith(PARTIAL):
                continue
            if now - os.path.getmtime(full) < MIN_AGE:
                continue
            yield rel, ('dir' if os.path.isdir(full) else 'file'), time.strftime('%Y-%m-%d', time.localtime(os.path.getmtime(full)))


def classify(items, projects):
    proj_lines = '\n'.join(f'- {p} (working versions used: {versions_summary(path)})' for p, path in sorted(projects.items()))
    prompt = f"""You file a design student's new files into project folders.
Existing projects (reuse one whenever the file belongs to it; exact name):
{proj_lines}

Output ONLY JSON Lines, one per input row, same order, no prose or code fences:
{{"path":"<exact input path>","project":"<Project_Name>","dest":"<bucket>"}}
A new project gets a short Title_Case_With_Underscores name.
dest is exactly one of: 01_Research, 02_Inspiration, 03_Assets/Images, 03_Assets/Icons, 03_Assets/Illustrations,
03_Assets/Logos, 03_Assets/Fonts, 03_Assets/Templates, 04_Working_Files/V01..V05 (editable drafts: .psd/.pptx/.key/.docx/.ai/.fig;
use the next version after those already used, cap V05), 05_Exports/JPG, 05_Exports/PNG, 05_Exports/PDF, 05_Exports/SVG,
06_Mockups, 07_Final (explicitly final/delivered), 99_Archive (duplicates like "(1)", zips of folders that also exist).
Web reference images/ads/posters collected for study go to 02_Inspiration.
Non-project items use project "-" and dest PERSONAL (IDs, receipts, personal photos, music, wallpapers, WhatsApp files),
INSTALLER (.dmg/.pkg installers, tool zips), or UNSURE (cannot tell; includes generic screenshots).

Input TSV (path, kind, modified):
""" + '\n'.join('\t'.join(i) for i in items)
    out = subprocess.run([CLAUDE, '-p'], input=prompt, capture_output=True, text=True, timeout=900, cwd=H)
    plan = []
    for line in out.stdout.splitlines():
        line = line.strip()
        if line.startswith('{'):
            try:
                plan.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return plan


def main():
    items = list(candidates())
    if '--list' in sys.argv:
        for i in items:
            print(f'WAITING\t{i[0]}')
        return
    if not items:
        return
    projects = existing_projects()
    plan = classify(items, projects)
    valid = {i[0] for i in items}
    month = datetime.date.today().month
    new_month_dir = os.path.join(ROOT, '%02d_%s' % (month, calendar.month_name[month]))
    log = open(os.path.join(ROOT, '_move_log.tsv'), 'a')
    for p in plan:
        rel, proj, dest = p.get('path'), p.get('project', '-'), p.get('dest', 'UNSURE')
        if rel not in valid:
            continue
        src = os.path.join(H, rel)
        if proj == '-' or not (dest in SKEL):
            d = {'PERSONAL': os.path.join(H, 'Personal'), 'INSTALLER': os.path.join(H, 'Installers')}.get(dest, os.path.join(ROOT, '_To_Review'))
        else:
            pdir = projects.get(proj) or os.path.join(new_month_dir, proj)
            if not DRY:
                for s in SKEL:
                    os.makedirs(os.path.join(pdir, s), exist_ok=True)
            projects[proj] = pdir
            d = os.path.join(pdir, dest)
        name = os.path.basename(src).strip() or 'item'
        dst = os.path.join(d, name)
        base, ext = os.path.splitext(name)
        i = 2
        while os.path.exists(dst):
            dst = os.path.join(d, f'{base} ({i}){ext}')
            i += 1
        print(f'{rel}  ->  {os.path.relpath(dst, H)}')
        if not DRY:
            os.makedirs(d, exist_ok=True)
            shutil.move(src, dst)
            log.write(f'{src}\t{dst}\n')


if __name__ == '__main__':
    main()
