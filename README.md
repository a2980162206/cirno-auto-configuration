# Cirno One-Click Script

**English** | [中文](README_zh.md)

Single-file, zero-dependency config manager for Cirno. Root is all you need — no Termux / Python / busybox required.

```sh
sh Cirno一键脚本.sh          # one-shot: fix perms + doctor + sync + reload
sh Cirno一键脚本.sh menu     # interactive menu
sh Cirno一键脚本.sh help     # full command list
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

## FAQ

- **Synced but nothing changed** → run `hotcheck`: no event = inode swapped / process gone; event present but read fails → `fix-perm`
- **Toggles won't respond** → entries must be `pkg#0`, run `normalize`
- **No packages detected** → verify root
- **Arrays all empty** → don't run it with bash; the script must run under mksh (it will `exec /system/bin/sh` itself)
