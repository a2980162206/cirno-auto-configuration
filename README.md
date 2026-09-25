# cirno-script
Cirno 一键脚本是单文件零依赖的 Android root 运维脚本。它用内嵌 awk 做 JSON 引擎，读写 Cirno 两份配置，支持查字段、增删、同步包列表、清空、规范化 UID。核心是 commit()：写前校验 JSON，非法即放弃；自动备份轮转 20 份；用 cat> 原地覆盖保留 inode，因 Cirno 只监听 MODIFY，换 inode 会让热更新失效；写后 restorecon、chown、chmod 并自检权限与 SELinux 标签。hotcheck 靠日志增量轮询，确认 App 是否真收到热更新。另有菜单、体检、备份回滚、幽灵包检测，并自动提权、强制 mksh 运行。优化版保持逻辑与输出兼容，仅重构 Shell 样板，AWK 逻辑未动。
