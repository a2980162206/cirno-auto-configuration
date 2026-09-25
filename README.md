# Cirno One-Click Script

**English** | [中文](README_zh.md)

A one-click tombstone (background-freeze) configuration script for Cirno. It auto-collects the package names of installed apps and writes them into Cirno's config files. **Root is all it needs** — no Termux, no Python, no busybox, and no manual steps at all.

## Download

- [Release v1.0.1](https://github.com/a2980162206/cirno-auto-configuration/releases/latest)
- Direct: [`cirno.sh`](https://github.com/a2980162206/cirno-auto-configuration/releases/download/v1.0.1/cirno.sh) · [`Cirno-yijian-jiaoben.sh`](https://github.com/a2980162206/cirno-auto-configuration/releases/download/v1.0.1/Cirno-yijian-jiaoben.sh) (same content)
- In-repo copies: [`cirno.sh`](cirno.sh) · [`Cirno一键脚本.sh`](Cirno%E4%B8%80%E9%94%AE%E8%84%9A%E6%9C%AC.sh)

## Install & Run

```sh
# 1. push the script to the phone
adb push cirno.sh /data/local/tmp/cirno.sh

# 2. run as root — that's it
su -c "sh /data/local/tmp/cirno.sh"
```

Once run, the script detects installed packages, fixes permissions / owner / SELinux labels, validates JSON, backs up, writes, and reloads Cirno. Nothing else to do by hand.

```sh
sh cirno.sh          # one-shot: fix perms + doctor + sync + reload
sh cirno.sh menu     # interactive menu
sh cirno.sh help     # full command list
```

## The Three Pitfalls It Solves

| Pitfall | Symptom | Fix |
|---|---|---|
| Wrong permission / owner / SELinux label | `Read Config failed` | After write: `restorecon` + `660` + `1000:1000`, then self-check |
| Using `mv`/`rename` to swap the file | Config changed but the app ignores it | `cat >` in-place overwrite, keeps the inode |
| Writing real UIDs (`pkg#10270`) | Toggles in the UI won't move | Always `pkg#0`; `normalize` converts in one shot |

## Paths

| Variable | Path |
|---|---|
| `APP` | `/data/system/Cirno/ApplicationSettings.json` |
| `GLB` | `/data/system/Cirno/GlobalSettings.json` |
| `BAK` | `/data/adb/cirno/backup` |
| `LOG` | `/data/system/Cirno/log/current.log` |

JSON read/write is handled by a built-in awk engine dumped to `/data/local/tmp/.cirno_j.awk` at startup — that is why it has zero dependencies.

Write pipeline: validate JSON → take log baseline → backup → record inode → `cat >` overwrite → `restorecon`/`chmod`/`chown` → compare inode → self-check permissions. Invalid JSON is aborted outright, never leaving a half-written file.

## Commands

**Sync**

```sh
sync                  # list every #uid field with counts
sync net              # the three common fields (overwrite)
sync merge            # the three common fields (append only)
sync uid              # alias of merge
sync dry              # preview
sync pick             # pick fields interactively
sync <field> [options...]
```

Options: `--all` include system packages · `--merge` append only · `--dry-run/-n` preview · `--no-reload` skip restart after write · `--all-fields` every field · `--bw` include black/white lists · `--uid` real UID (not recommended)

> `all`/`merge`/`uid`/`dry` all imply `--auto`, which by default only syncs `blockAutostartApps`, `networkMessageApps`, `networkSpeedApps`. Black/white lists are skipped by default (they are hand-picked semantics) — add `--bw` to include them.

**Browse**

```sh
fields / get / bulksync / bulkclear
```

Selection syntax: `3` / `1 3 5` / `1,3,5` / `1-4` / `blackApps` / `黑名单` / `net` (fuzzy) / `a` / `q`

**Edit**

```sh
validate [app|global] · show [app|global] [field] · keys [app|global]
add <field> <pkg...> · del <field> <pkg...>
set [app|global] <field> <JSON value> · unset [app|global] <field>
```

**Maintenance**

```sh
doctor · diff [field] · normalize · fix-perm · hotcheck [seconds] · log [lines] · reload
backups · rollback [n]
```

Every write is auto-backed up, keeping the latest 20 copies.

## Requirements

- Android with **root** (Magisk / KernelSU)
- Cirno installed
- `mksh` — the script re-execs `/system/bin/sh` by itself, so do **not** run it with bash

## FAQ

- **Synced but nothing changed** → run `hotcheck`: no event = inode swapped / process gone; event present but read fails → `fix-perm`
- **Toggles won't respond** → entries must be `pkg#0`, run `normalize`
- **No packages detected** → verify root
- **Arrays all empty** → don't run it with bash; the script must run under mksh (it will `exec /system/bin/sh` itself)

## License

GNU GPL v3.0 — see [LICENSE](LICENSE).
