# Cirno One-Click Script

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

---

# Cirno 一键脚本（中文）

单文件、零依赖的 Cirno 配置管理工具。有 root 就能跑，不需要 Termux / Python / busybox。

```sh
sh Cirno一键脚本.sh          # 一键全套：修权限+体检+同步+重启
sh Cirno一键脚本.sh menu     # 交互菜单
sh Cirno一键脚本.sh help     # 全部命令
```

## 解决的三个坑

| 坑 | 表现 | 处理 |
|---|---|---|
| 权限/属主/SELinux 不对 | `Read Config 失败` | 写入后自动 `restorecon` + `660` + `1000:1000` 并自检 |
| 用 mv/rename 换文件 | 改了配置 App 没反应 | `cat >` 原地覆盖，保留 inode |
| 写真实 UID（`包名#10270`） | 界面开关不动 | 统一 `包名#0`，`normalize` 可一键转换 |

## 路径

| 变量 | 路径 |
|---|---|
| `APP` | `/data/system/Cirno/ApplicationSettings.json` |
| `GLB` | `/data/system/Cirno/GlobalSettings.json` |
| `BAK` | `/data/adb/cirno/backup` |
| `LOG` | `/data/system/Cirno/log/current.log` |

JSON 读写靠启动时写到 `/data/local/tmp/.cirno_j.awk` 的内置 awk 引擎，所以零依赖。

写入流程：校验 JSON → 取日志基线 → 备份 → 记 inode → `cat >` 覆盖 → `restorecon`/`chmod`/`chown` → 比对 inode → 自检权限。非法 JSON 直接放弃，绝不产生半个文件。

## 命令

**同步**

```sh
sync                  # 列出所有 #uid 字段及数量
sync net              # 三个常用字段（覆盖）
sync merge            # 三个常用字段（只追加）
sync uid              # 同 merge
sync dry              # 预览
sync pick             # 交互选字段
sync <字段> [选项...]
```

选项：`--all` 含系统包 · `--merge` 只追加 · `--dry-run/-n` 预览 · `--no-reload` 写后不重启 · `--all-fields` 全字段 · `--bw` 带黑白名单 · `--uid` 真实UID（不推荐）

> `all`/`merge`/`uid`/`dry` 都隐含 `--auto`，默认只同步 `blockAutostartApps`、`networkMessageApps`、`networkSpeedApps` 三个字段。黑白名单默认跳过（人工点名语义），要同步加 `--bw`。

**浏览**

```sh
fields / get / bulksync / bulkclear
```

选择语法：`3` / `1 3 5` / `1,3,5` / `1-4` / `blackApps` / `黑名单` / `net`(模糊) / `a` / `q`

**编辑**

```sh
validate [app|global] · show [app|global] [字段] · keys [app|global]
add <字段> <包名...> · del <字段> <包名...>
set [app|global] <字段> <JSON值> · unset [app|global] <字段>
```

**维护**

```sh
doctor · diff [字段] · normalize · fix-perm · hotcheck [秒] · log [行数] · reload
backups · rollback [n]
```

每次写入前自动备份，保留最近 20 份。

## 常见问题

- **同步了没变化** → 跑 `hotcheck`：无事件=inode 被换/进程不在；有事件但读取失败 → `fix-perm`
- **开关点不动** → 配置得是 `包名#0`，跑 `normalize`
- **没抓到包** → 确认 root
- **数组全空** → 别用 bash 跑，脚本必须走 mksh（会自动 `exec /system/bin/sh`）
