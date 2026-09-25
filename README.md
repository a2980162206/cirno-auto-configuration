# Cirno 一键脚本

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
