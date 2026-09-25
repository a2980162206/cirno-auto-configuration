#!/system/bin/sh
# Cirno 一键脚本 (单文件 / 零依赖版)
# 不需要 Termux、不需要 Python、不需要 busybox；只要 root，丢到任何 Android 手机都能直接跑
#
# 用法:
#   sh Cirno一键脚本.sh              一键全套(修权限+体检+同步+重启)
#   sh Cirno一键脚本.sh menu         交互菜单
#   sh Cirno一键脚本.sh doctor       体检
#   sh Cirno一键脚本.sh sync dry     预览同步
#   sh Cirno一键脚本.sh help         全部命令

APP=/data/system/Cirno/ApplicationSettings.json
GLB=/data/system/Cirno/GlobalSettings.json
DIR=/data/system/Cirno
BAK=/data/adb/cirno/backup
LOG=$DIR/log/current.log
JW=/data/local/tmp/.cirno_j.awk
TMPD=/data/local/tmp

# 颜色
if [ -t 1 ]; then
    R=$(printf '\033[31m'); G=$(printf '\033[32m'); Y=$(printf '\033[33m')
    B=$(printf '\033[36m'); D=$(printf '\033[2m'); N=$(printf '\033[0m')
else
    R=; G=; Y=; B=; D=; N=
fi

die()  { echo "$R✗ $1$N"; exit 1; }
ok()   { echo "$G✓ $1$N"; }
info() { echo "$B· $1$N"; }
warn() { echo "$Y! $1$N"; }

# 自动提权
SELF="$0"
case "$SELF" in /*) ;; *) SELF="$(pwd)/$SELF" ;; esac

# 强制用 Android 自带 mksh 运行：bash/dash 不支持 mksh 的 set -A 数组语法，
# 用它们跑会导致数组全部为空（表现为"找不到字段""没抓到任何包""没选中任何字段"）
if [ -z "$KSH_VERSION" ] && [ -x /system/bin/sh ]; then
    exec /system/bin/sh "$SELF" "$@"
fi

if [ "$(id -u)" != "0" ]; then
    if command -v su >/dev/null 2>&1; then
        QA=""
        for a in "$@"; do QA="$QA '$a'"; done
        exec su -c "sh '$SELF' $QA"
    fi
    die "需要 root 权限"
fi

# 写 awk 引擎
write_awk() {
    cat > "$JW" <<'AWKEOF'
# Cirno JSON 引擎 (awk)
function skipws(p) { while (p <= N && substr(txt,p,1) ~ /[ \t\r\n]/) p++; return p }

function scanstr(p,   ch,s) {
    s = ""; p++
    while (p <= N) {
        ch = substr(txt,p,1)
        if (ch == "\\") { s = s ch substr(txt,p+1,1); p += 2; continue }
        if (ch == "\"") { str = s; return p+1 }
        s = s ch; p++
    }
    return -1
}

function matchval(p,   c,ch,d,ins) {
    c = substr(txt,p,1)
    if (c == "\"") return scanstr(p)
    if (c == "[" || c == "{") {
        d = 0; ins = 0
        while (p <= N) {
            ch = substr(txt,p,1)
            if (ins) {
                if (ch == "\\") { p += 2; continue }
                if (ch == "\"") ins = 0
                p++; continue
            }
            if (ch == "\"") { ins = 1; p++; continue }
            if (ch == "[" || ch == "{") d++
            else if (ch == "]" || ch == "}") { d--; if (d == 0) return p+1 }
            p++
        }
        return -1
    }
    while (p <= N && substr(txt,p,1) !~ /[ \t\r\n,}\]]/) p++
    return p
}

function parse(   p,c,q) {
    p = skipws(1)
    if (substr(txt,p,1) != "{") return 0
    p++
    nk = 0
    while (1) {
        p = skipws(p)
        c = substr(txt,p,1)
        if (c == "}") return 1
        if (c != "\"") return 0
        q = scanstr(p); if (q < 0) return 0
        p = skipws(q)
        if (substr(txt,p,1) != ":") return 0
        p = skipws(p+1)
        nk++
        kname[nk] = str
        q = matchval(p); if (q < 0) return 0
        kraw[nk] = substr(txt, p, q-p)
        p = skipws(q)
        c = substr(txt,p,1)
        if (c == ",") { p++; continue }
        if (c == "}") return 1
        return 0
    }
}

function indexof(k,   i) { for (i = 1; i <= nk; i++) if (kname[i] == k) return i; return 0 }

function unq(t,   s,p,ch) {
    s = ""
    for (p = 2; p < length(t); p++) {
        ch = substr(t,p,1)
        if (ch == "\\") { p++; s = s substr(t,p,1); continue }
        s = s ch
    }
    return s
}

function qt(s,   r,p,ch) {
    r = "\""
    for (p = 1; p <= length(s); p++) {
        ch = substr(s,p,1)
        if (ch == "\"" || ch == "\\") r = r "\\"
        r = r ch
    }
    return r "\""
}

function arrload(k,   i,raw,p,c,q,m) {
    m = 0
    i = indexof(k)
    if (i == 0) { nel = 0; return 0 }
    raw = kraw[i]
    if (substr(raw,1,1) != "[") { nel = 0; return 0 }
    p = 2
    while (p <= length(raw)) {
        c = substr(raw,p,1)
        if (c == "," || c ~ /[ \t\r\n]/) { p++; continue }
        if (c == "]") break
        if (c == "\"") {
            q = p+1
            while (q <= length(raw)) {
                c = substr(raw,q,1)
                if (c == "\\") { q += 2; continue }
                if (c == "\"") break
                q++
            }
            m++
            el[m] = substr(raw, p, q-p+1)
            p = q+1
            continue
        }
        p++
    }
    nel = m
    return m
}

function arrbuild(k,   i,s,j) {
    if (nel == 0) s = "[]"
    else {
        s = "[\n"
        for (j = 1; j <= nel; j++) {
            s = s "    " el[j]
            if (j < nel) s = s ","
            s = s "\n"
        }
        s = s "  ]"
    }
    i = indexof(k)
    kraw[i] = s
}

function loadvals(   m,t) {
    m = 0
    while ((getline t < valsfile) > 0) {
        sub(/\r$/, "", t)
        if (t != "") { m++; el[m] = qt(t) }
    }
    close(valsfile)
    nel = m
}

# 包列表复用 loadvals 的读法，只换存放的数组
function loadnew(   j) {
    loadvals()
    nnv = nel
    for (j = 1; j <= nel; j++) nv[j] = el[j]
}

function loadkeys(f,   m,t) {
    m = 0
    while ((getline t < f) > 0) {
        sub(/\r$/, "", t)
        if (t != "") { m++; kl[m] = t }
    }
    close(f)
    nkl = m
}

function alluid(   j,s) {
    if (nel == 0) return 0
    for (j = 1; j <= nel; j++) {
        s = unq(el[j])
        if (s !~ /^[^#]+#[0-9]+$/) return 0
    }
    return 1
}

# 已知的包列表字段 (即使数组为空也认得, 防止空配置死锁)
# 注意: blackApps / whiteApps 故意不在此列 —— 黑白名单是"人工指定"的语义,
# 不应该被 --auto 自动灌入全部已安装应用。它们只有原本就非空时才会被同步。
function knownlist(k) {
    return (k == "backgroundPlayApps" || k == "blockAutostartApps" ||
            k == "frozenProcessExclusions" || k == "killedProcesses" || k == "locationUseApps" ||
            k == "memoryTrimDisabledApps" || k == "memoryTrimGcDisabledApps" ||
            k == "networkMessageApps" || k == "networkSpeedApps")
}

function emit(o,   i,s) {
    print "{" > o
    for (i = 1; i <= nk; i++) {
        s = "  \"" kname[i] "\": " kraw[i]
        if (i < nk) s = s ","
        print s > o
    }
    print "}" > o
    close(o)
}

# 中文字段名 / 宽度对齐
function cn(k) {
    if (k == "backgroundOomAdjApps")     return "后台OOM优先级"
    if (k == "backgroundPlayApps")       return "后台播放应用"
    if (k == "batteryOptimizationApps")  return "电池优化应用"
    if (k == "blackApps")                return "黑名单应用"
    if (k == "blockAutostartApps")       return "禁止自启动"
    if (k == "frozenProcessExclusions")  return "冻结进程排除"
    if (k == "killedProcesses")          return "被杀进程记录"
    if (k == "locationUseApps")          return "定位使用应用"
    if (k == "memoryTrimDisabledApps")   return "禁用内存回收"
    if (k == "memoryTrimGcDisabledApps") return "禁用GC回收"
    if (k == "networkMessageApps")       return "网络消息唤醒"
    if (k == "networkSpeedApps")         return "网速监控应用"
    if (k == "whiteApps")                return "白名单应用"
    if (k == "batteryOptimizationMode")  return "电池优化模式"
    if (k == "bootFreezeAll")            return "开机冻结全部"
    if (k == "compactionDelay")          return "压缩延迟"
    if (k == "compactionEnabled")        return "启用内存压缩"
    if (k == "compactionThrottle")       return "压缩节流"
    if (k == "freezeDelay")              return "冻结延迟"
    if (k == "freezerMode")              return "冻结模式"
    if (k == "hookType")                 return "Hook方式"
    if (k == "logLevel")                 return "日志级别"
    if (k == "memoryTrimDelay")          return "回收延迟"
    if (k == "memoryTrimEnabled")        return "启用内存回收"
    if (k == "memoryTrimGcEnabled")      return "启用GC回收"
    if (k == "memoryTrimLevel")          return "回收阈值"
    if (k == "memoryTrimThrottle")       return "回收节流"
    if (k == "netlinkUnit")              return "Netlink单位"
    if (k == "networkSpeedThreshold")    return "网速阈值"
    if (k == "wakeFreezeDelay")          return "唤醒冻结延迟"
    return k
}

function dw(s,   i,c,n) {
    n = 0
    for (i = 1; i <= length(s); i++) {
        c = ord[substr(s,i,1)]
        if (c < 128) n++
        else if (c >= 192) n += 2
    }
    return n
}

function pad(s, w,   d) {
    d = w - dw(s)
    if (d < 0) d = 0
    return s sprintf("%*s", d, "")
}

# 校验
function vval(p,   c,s,q) {
    p = skipws(p)
    if (p > N) return -p
    c = substr(txt,p,1)
    if (c == "{") return vobj(p)
    if (c == "[") return varr(p)
    if (c == "\"") { q = scanstr(p); return (q < 0 ? -p : q) }
    s = substr(txt, p, 5)
    if (substr(s,1,4) == "true" || substr(s,1,4) == "null") return p+4
    if (s == "false") return p+5
    q = p
    while (q <= N && substr(txt,q,1) ~ /[0-9eE+.\-]/) q++
    if (q == p) return -p
    return q
}

function vobj(p,   c,q) {
    p = skipws(p+1)
    if (substr(txt,p,1) == "}") return p+1
    while (1) {
        p = skipws(p)
        if (substr(txt,p,1) != "\"") return -p
        q = scanstr(p); if (q < 0) return -p
        p = skipws(q)
        if (substr(txt,p,1) != ":") return -p
        p = vval(p+1); if (p < 0) return p
        p = skipws(p)
        c = substr(txt,p,1)
        if (c == ",") { p++; continue }
        if (c == "}") return p+1
        return -p
    }
}

function varr(p,   c,q) {
    p = skipws(p+1)
    if (substr(txt,p,1) == "]") return p+1
    while (1) {
        p = vval(p); if (p < 0) return p
        p = skipws(p)
        c = substr(txt,p,1)
        if (c == ",") { p++; continue }
        if (c == "]") return p+1
        return -p
    }
}

function report(p,   i,m,ln,col) {
    m = 0; ln = 1
    for (i = 1; i < p; i++) if (substr(txt,i,1) == "\n") { m = i; ln++ }
    col = p - m
    printf "ERR:第 %d 行 第 %d 列 结构错误\n", ln, col
}

function do_validate(   r,r2) {
    if (N == 0) { print "OK"; return }
    r = vval(1)
    if (r < 0) { report(-r); return }
    r2 = skipws(r)
    if (r2 <= N) { report(r2); return }
    print "OK"
}

BEGIN {
    for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
    txt = ""
    if (file != "") {
        while ((getline l < file) > 0) txt = txt l "\n"
        close(file)
    }
    N = length(txt)

    if (cmd == "validate") { do_validate(); exit 0 }

    if (N == 0) { nk = 0 }
    else if (!parse()) { print "ERR:JSON 结构损坏"; exit 1 }

    if (cmd == "has")    { print (indexof(key) ? "YES" : "NO"); exit 0 }
    if (cmd == "get")    { i = indexof(key); if (i) print kraw[i]; exit 0 }
    if (cmd == "count")  { i = indexof(key); if (!i) print 0; else { arrload(key); print nel }; exit 0 }

    if (cmd == "type") {
        i = indexof(key)
        if (!i) { print "ABSENT"; exit 0 }
        c = substr(kraw[i],1,1)
        if (c == "[") print "LIST"
        else if (c == "{") print "OBJ"
        else if (c == "\"") print "STR"
        else print "OTHER"
        exit 0
    }

    if (cmd == "keys") {
        for (i = 1; i <= nk; i++) {
            c = substr(kraw[i],1,1)
            t = (c == "[") ? "列表" : (c == "{") ? "对象" : "值"
            printf "%-28s %s\n", kname[i], t
        }
        exit 0
    }

    if (cmd == "list2") {
        for (i = 1; i <= nk; i++) {
            c = substr(kraw[i],1,1)
            if (c == "[") { arrload(kname[i]); v = nel }
            else if (c == "{") v = "对象"
            else v = kraw[i]
            printf "%s  %s  %s\n", pad(cn(kname[i]), 18), pad(kname[i], 26), v
        }
        exit 0
    }

    if (cmd == "cn") { print cn(key); exit 0 }

    if (cmd == "meta") {
        i = indexof(key)
        if (!i) { print "ERR"; exit 1 }
        c = substr(kraw[i],1,1)
        if (c == "[") { arrload(key); printf "列表\t%d\n", nel }
        else if (c == "{") print "对象\t0"
        else printf "值\t%s\n", kraw[i]
        exit 0
    }

    if (cmd == "dump") {
        i = indexof(key)
        if (!i) { print "ERR:没有字段 " key; exit 1 }
        c = substr(kraw[i],1,1)
        if (c == "[") {
            arrload(key)
            print cn(key) " (" key ") — " nel " 项"
            if (nel == 0) print "  (空)"
            else for (j = 1; j <= nel; j++) print "  " j ". " unq(el[j])
        } else if (c == "{") {
            print cn(key) " (" key ") — 对象"
            print kraw[i]
        } else {
            print cn(key) " (" key ")"
            print "  " kraw[i]
        }
        exit 0
    }

    if (cmd == "list") {
        for (i = 1; i <= nk; i++) {
            c = substr(kraw[i],1,1)
            if (c == "[") { arrload(kname[i]); v = nel }
            else if (c == "{") v = "对象"
            else v = kraw[i]
            printf "%-28s %s\n", kname[i], v
        }
        exit 0
    }

    if (cmd == "arr") {
        arrload(key)
        for (i = 1; i <= nel; i++) print unq(el[i])
        exit 0
    }

    if (cmd == "uidkeys") {
        for (i = 1; i <= nk; i++) {
            if (substr(kraw[i],1,1) != "[") continue
            arrload(kname[i])
            # 有元素且全 #uid -> 认; 空数组但字段名已知 -> 也认
            if (alluid() || (nel == 0 && knownlist(kname[i]))) print kname[i]
        }
        exit 0
    }

    if (cmd == "set") {
        i = indexof(key)
        if (!i) { nk++; kname[nk] = key; kraw[nk] = val }
        else kraw[i] = val
        emit(out); print "CHANGED"; exit 0
    }

    if (cmd == "setarr") {
        loadvals()
        i = indexof(key)
        if (!i) { nk++; kname[nk] = key; kraw[nk] = "[]" }
        arrbuild(key)
        emit(out); print "CHANGED"; exit 0
    }

    # 把所有列表字段的值替换为 valsfile 里 [字段名] 分节给出的新列表
    # valsfile 格式:  "[key1]" 后跟若干行值, 然后 "[key2]" ...
    if (cmd == "normalize") {
        loadkeys(keyfile)
        # 解析 valsfile 分节
        cur = ""
        m = 0
        while ((getline t < valsfile) > 0) {
            sub(/\r$/, "", t)
            if (t ~ /^\[.+\]$/) {
                if (cur != "") nsec[cur] = m
                cur = substr(t, 2, length(t)-2)
                m = 0
                continue
            }
            if (t == "" || cur == "") continue
            m++
            sec[cur, m] = t
        }
        if (cur != "") nsec[cur] = m
        close(valsfile)

        ch = 0
        for (x = 1; x <= nkl; x++) {
            k = kl[x]
            i = indexof(k)
            if (!i) continue
            if (substr(kraw[i],1,1) != "[") continue
            cnt = nsec[k] + 0
            if (cnt == 0) { newraw = "[]" }
            else {
                s = "[\n"
                for (j = 1; j <= cnt; j++) {
                    s = s "    " qt(sec[k, j])
                    if (j < cnt) s = s ","
                    s = s "\n"
                }
                s = s "  ]"
                newraw = s
            }
            if (kraw[i] != newraw) { kraw[i] = newraw; ch = 1 }
        }
        if (!ch) { print "SAME"; exit 0 }
        emit(out); print "CHANGED"; exit 0
    }

    # 一次把多个字段清空 (valsfile 里每行一个字段名)
    if (cmd == "clearmulti") {
        loadkeys(valsfile)
        ch = 0
        for (x = 1; x <= nkl; x++) {
            i = indexof(kl[x])
            if (!i) continue
            if (substr(kraw[i],1,1) != "[") continue
            if (kraw[i] == "[]") continue
            kraw[i] = "[]"
            ch = 1
        }
        if (!ch) { print "SAME"; exit 0 }
        emit(out); print "CHANGED"; exit 0
    }

    # 一次把多个字段同步为同一份包列表 (keyfile 每行一个字段, valsfile 包列表)
    # mode=merge 追加去重, 否则覆盖
    if (cmd == "syncmulti") {
        loadkeys(keyfile)
        loadnew()
        ch = 0
        for (x = 1; x <= nkl; x++) {
            i = indexof(kl[x])
            if (!i) continue
            if (substr(kraw[i],1,1) != "[") continue
            if (mode == "merge") {
                arrload(kl[x])
                for (j = 1; j <= nel; j++) keep[j] = el[j]
                nkeep = nel
                for (j = 1; j <= nnv; j++) {
                    f = 0
                    for (m = 1; m <= nkeep; m++) if (keep[m] == nv[j]) { f = 1; break }
                    if (!f) { nkeep++; keep[nkeep] = nv[j] }
                }
                nel = nkeep
                for (j = 1; j <= nel; j++) el[j] = keep[j]
                arrbuild(kl[x])
            } else {
                nel = nnv
                for (j = 1; j <= nnv; j++) el[j] = nv[j]
                arrbuild(kl[x])
            }
            ch = 1
        }
        if (!ch) { print "SAME"; exit 0 }
        emit(out); print "CHANGED"; exit 0
    }

    if (cmd == "unioncount") {
        arrload(key)
        for (j = 1; j <= nel; j++) keep[j] = el[j]
        nkeep = nel
        loadvals()
        for (j = 1; j <= nel; j++) {
            f = 0
            for (m = 1; m <= nkeep; m++) if (keep[m] == el[j]) { f = 1; break }
            if (!f) { nkeep++; keep[nkeep] = el[j] }
        }
        print nkeep; exit 0
    }

    if (cmd == "add") {
        i = indexof(key)
        if (!i) { print "ERR:没有字段 " key; exit 1 }
        if (substr(kraw[i],1,1) != "[") { print "ERR:字段不是列表"; exit 1 }
        arrload(key)
        for (j = 1; j <= nel; j++) keep[j] = el[j]
        nkeep = nel
        loadvals()
        addn = 0
        for (j = 1; j <= nel; j++) {
            f = 0
            for (m = 1; m <= nkeep; m++) if (keep[m] == el[j]) { f = 1; break }
            if (f) print "! 已存在: " unq(el[j])
            else { nkeep++; keep[nkeep] = el[j]; addn++; print "+ " unq(el[j]) }
        }
        if (addn == 0) { print "SAME"; exit 0 }
        nel = nkeep
        for (j = 1; j <= nel; j++) el[j] = keep[j]
        arrbuild(key)
        emit(out); print "CHANGED"; exit 0
    }

    if (cmd == "del") {
        i = indexof(key)
        if (!i) { print "ERR:没有字段 " key; exit 1 }
        if (substr(kraw[i],1,1) != "[") { print "ERR:字段不是列表"; exit 1 }
        arrload(key)
        for (j = 1; j <= nel; j++) keep[j] = el[j]
        nkeep = nel
        loadvals()
        gone = 0; nnew = 0
        for (j = 1; j <= nkeep; j++) {
            d = 0
            for (m = 1; m <= nel; m++) {
                t = unq(el[m])
                if (unq(keep[j]) == t) { d = 1; break }
                if (index(t, "#") == 0 && unq(keep[j]) == t "#0") { d = 1; break }
            }
            if (d) { gone++; print "- " unq(keep[j]) }
            else { nnew++; res[nnew] = keep[j] }
        }
        if (gone == 0) { print "SAME"; exit 0 }
        nel = nnew
        for (j = 1; j <= nnew; j++) el[j] = res[j]
        arrbuild(key)
        emit(out); print "CHANGED"; exit 0
    }

    if (cmd == "unset") {
        i = indexof(key)
        if (!i) { print "SAME"; exit 0 }
        for (j = i; j < nk; j++) { kname[j] = kname[j+1]; kraw[j] = kraw[j+1] }
        nk--
        emit(out); print "CHANGED"; exit 0
    }

    exit 0
}
AWKEOF
    chmod 644 "$JW"
}

write_awk || die "无法写入 awk 引擎 $JW"

# ---------- 公共封装层 ----------
resolve() {
    case "$1" in
        ""|app|ApplicationSettings|ApplicationSettings.json) echo "$APP" ;;
        global|GlobalSettings|GlobalSettings.json)           echo "$GLB" ;;
        *) if [ -f "$1" ]; then echo "$1"; else die "未知配置文件: $1 (可用 app / global)"; fi ;;
    esac
}

# 存在的配置文件列表 (顺序固定 app -> global)
cfgs() {
    [ -f "$APP" ] && echo "$APP"
    [ -f "$GLB" ] && echo "$GLB"
    return 0
}

# awk 引擎只读调用: jwq <cmd> <file> [key] [额外 -v 参数...]
jwq() {
    _a="$1"; _b="$2"; _k="${3:-}"
    if [ $# -ge 3 ]; then shift 3; else shift "$#"; fi
    awk -v cmd="$_a" -v file="$_b" -v key="$_k" "$@" -f "$JW"
}

# awk 引擎写入调用: jwo <cmd> <file> <key> <输出文件> [额外 -v 参数...]
# 结果: _o = awk 完整输出, _st = 最后一行状态 (CHANGED / SAME / ERR...)
jwo() {
    _a="$1"; _b="$2"; _k="$3"; _f="$4"; shift 4
    _o=$(awk -v cmd="$_a" -v file="$_b" -v key="$_k" -v out="$_f" "$@" -f "$JW")
    _st=$(printf '%s\n' "$_o" | tail -n 1)
}

# 打印 awk 写操作的人类可读输出 (去掉状态行)
strip_status() { printf '%s\n' "$_o" | sed '/^CHANGED$/d;/^SAME$/d'; }

# 权限/属主行 (供校验、体检、提交后自检使用)
perm_of() { ls -ln "$1" | awk '{print $3":"$4" "$1}'; }

# 单词去重 (空格分隔)
uniq_words() { tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '; }

# 字段是否存在于指定文件（存在返回 0）
has_field() { [ "$(jwq has "$1" "$2")" = YES ]; }

# 查字段中文名
cnname() { jwq cn "" "$1"; }

# 字段所在文件；$2 = 两个文件都没有该字段时的兜底（默认 app）
file_of() {
    if has_field "$APP" "$1"; then echo "$APP"
    elif has_field "$GLB" "$1"; then echo "$GLB"
    else echo "${2:-$APP}"; fi
}

# 解析 [app|global] <字段> 前缀: 设 p=文件 k=字段 SKIP=需 shift 的个数
target_field() {
    case "$1" in
        app|global|ApplicationSettings|GlobalSettings) p=$(resolve "$1"); k="$2"; SKIP=2 ;;
        *) k="$1"; p=$(file_of "$k"); SKIP=1 ;;
    esac
}

shq() {
    printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

# 有写入才执行后续动作 (并重置 WROTE)
flush_wrote() { [ "$WROTE" = 1 ] || return 0; WROTE=0; "$@"; }

# 单字段写操作统一收尾: apply_edit <file> <why> <warn|die> <same_msg> [err_msg]
apply_edit() {
    case "$_st" in
        CHANGED) commit "$1" "$2"; hotcheck 3; reload_after_write ;;
        SAME)    if [ "$3" = die ]; then die "$4"; else warn "$4"; fi ;;
        *)       if [ -n "$5" ]; then die "$5"; else die "$(printf '%s\n' "$_o" | head -n 1)"; fi ;;
    esac
}

# 多字段写操作统一收尾: 0=已写入(CHANGED) 1=无变化(SAME) 2=失败(输出已打印)
apply_multi() {
    case "$_st" in
        CHANGED) commit "$1" "$2" 1; WROTE=1; return 0 ;;
        SAME)    return 1 ;;
        *)       printf '%s\n' "$_o"; return 2 ;;
    esac
}

# 写盘后统一刷新动作
hot_reload() { hotcheck 4; reload_after_write; }

backup() {
    p="$1"
    [ -f "$p" ] || return 0
    mkdir -p "$BAK"
    stem=$(basename "$p" .json)
    n="$BAK/$stem.$(date '+%Y%m%d-%H%M%S').json"
    cp "$p" "$n"
    i=0
    for f in $(ls -1r "$BAK/$stem".*.json 2>/dev/null); do
        i=$((i+1))
        [ $i -gt 20 ] && rm -f "$f"
    done
    echo "$n"
}

commit() {
    p="$1"; why="$2"; quiet="$3"
    tmp="$p.tmp"
    [ -f "$tmp" ] || die "临时文件缺失，未写入"
    r=$(awk -v cmd=validate -v file="$tmp" -f "$JW")
    [ "$r" = "OK" ] || { rm -f "$tmp"; die "生成内容 JSON 非法，已放弃：$r"; }
    # 热更新 baseline 必须在写入之前取：
    # App 的 debounce 只有 ~2s，等 commit 里的 restorecon/chown 跑完再取，
    # 那条"配置热更新"日志早就进文件了，增量判断会永远为 0。
    logcnt "配置热更新"
    HC_BASE=$_c
    logcnt "Read Config 失败"
    HC_EBASE=$_c
    b=$(backup "$p")
    ino_before=$(ls -i "$p" 2>/dev/null | awk '{print $1}')
    # 原地写入，保留 inode：Cirno 的 ConfigFileObserver 只监听
    # MODIFY(0x2) | DELETE(0x200) | DELETE_SELF(0x400) | MOVE_SELF(0x800)，
    # 不含 MOVED_TO(0x80)。用 mv/rename/os.replace 换掉 inode 只会产生
    # MOVED_TO，App 完全收不到事件，热更新永久失效。
    # 必须用 `cat > ` 原地截断覆盖。
    cat "$tmp" > "$p" || die "写入失败"
    rm -f "$tmp"
    # 顺序很重要：先 restorecon 再 chown/chmod，否则 SELinux 标签可能被重置
    restorecon -F "$p" 2>/dev/null
    chmod 660 "$p"; chown 1000:1000 "$p"
    ino_after=$(ls -i "$p" 2>/dev/null | awk '{print $1}')
    if [ -n "$ino_before" ] && [ "$ino_before" != "$ino_after" ]; then
        warn "inode 变了 ($ino_before -> $ino_after)，App 可能收不到热更新事件"
    fi
    # 写后自检：权限/属主/标签错一项，App 读取就会 AccessDeniedException
    s=$(ls -ln "$p" | awk '{print $3":"$4" "$1}')
    [ "$s" = "1000:1000 -rw-rw----" ] || warn "属主/权限异常: $s (跑 fix-perm)"
    z=$(ls -Z "$p" 2>/dev/null | awk '{print $1}')
    case "$z" in
        *system_data_file*) ;;
        "") ;;
        *) warn "SELinux 标签异常: $z (跑 fix-perm)" ;;
    esac
    if [ "$quiet" != "1" ]; then
        ok "已写入 $(basename "$p") ($why)"
        info "备份: $b"
    fi
}

# 统计日志里某个串出现次数（结果放在 $_c，比 $(...) 少一次子进程）
logcnt() {
    c=$(grep -c "$1" "$LOG" 2>/dev/null)
    case "$c" in ''|*[!0-9]*) c=0 ;; esac
    _c="$c"
}

# 检查热更新是否真的被 App 收到（读日志）
# Cirno 的 FileObserver 在 onEvent 里 postDelayed(2000) 做 debounce，
# 事件落地会晚 1~2 秒，这里轮询等待。
# 用"日志里热更新条数的增量"判断，比记行号稳（日志会被 App 轮转）。
# baseline 由 commit() 在写入前取好，放在 HC_BASE / HC_EBASE。
# 用法: hotcheck [最多等几秒]  返回 0 = 收到事件, 1 = 没收到
hotcheck() {
    w="${1:-6}"
    [ -f "$LOG" ] || return 0

    base="${HC_BASE:-}"
    ebase="${HC_EBASE:-}"
    if [ -z "$base" ]; then
        logcnt "配置热更新"; base=$_c
        logcnt "Read Config 失败"; ebase=$_c
    fi
    [ -n "$ebase" ] || ebase=0

    waited=0
    while [ "$waited" -lt "$w" ]; do
        sleep 1
        waited=$((waited + 1))
        logcnt "配置热更新"
        if [ "$_c" -gt "$base" ]; then
            ok "App 已收到热更新事件 (${waited}s)"
            HC_BASE=""; HC_EBASE=""
            return 0
        fi
        logcnt "Read Config 失败"
        if [ "$_c" -gt "$ebase" ]; then
            warn "App 收到事件但读取失败（权限/属主/SELinux 不对）:"
            grep "Read Config 失败" "$LOG" | tail -n 3
            HC_BASE=""; HC_EBASE=""
            return 1
        fi
    done
    warn "等了 ${w}s 日志里仍没有热更新事件"
    warn "可能原因: inode 被换(mv/rename/os.replace) / App 进程不在 / 日志级别不是 debug"
    HC_BASE=""; HC_EBASE=""
    return 1
}

get_pkgs() {
    tp="$1"; wu="$2"
    if [ "$tp" = 1 ]; then o="-3"; else o=""; fi
    if [ "$wu" = 1 ]; then
        pm list packages $o -U 2>/dev/null | sed -n 's/^package:\([^ ]*\) uid:\([0-9]*\).*/\1#\2/p'
    else
        pm list packages $o 2>/dev/null | sed -n 's/^package:\(.*\)$/\1#0/p'
    fi | sort -u
}

uidkeys_all() {
    for p in $(cfgs); do jwq uidkeys "$p"; done | sort -u
}

# 真正重启 App 的动作 (c_reload / reload_after_write 共用)
restart_app() {
    am force-stop nep.timeline.cirno 2>/dev/null
    sleep 1
    am start -n nep.timeline.cirno/.MainActivity >/dev/null 2>&1 \
        || monkey -p nep.timeline.cirno -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 2
}

# ---------- 命令 ----------
# 把所有列表字段里的 包名#真实UID 统一改写为 包名#0
# Cirno App 的界面判定用 PolicyKey.of(pkg, userId)，主用户就是 #0。
# 写 #10270 这种真实 UID App 认不出来，开关不会变（这是"配置写了但界面没反应"的根因）。
c_normalize() {
    for p in $(cfgs); do
        keys=$(jwq uidkeys "$p")
        [ -n "$keys" ] || continue
        n=0
        for k in $keys; do
            jwq arr "$p" "$k" | sed 's/#[0-9]\+$/#0/' | awk '!seen[$0]++' > "$TMPD/.cirno_norm_$k"
            n=$((n + 1))
        done
        printf '%s\n' $keys > "$TMPD/.cirno_norm_keys"
        : > "$TMPD/.cirno_norm_vals"
        for k in $keys; do
            echo "[$k]" >> "$TMPD/.cirno_norm_vals"
            cat "$TMPD/.cirno_norm_$k" >> "$TMPD/.cirno_norm_vals"
        done
        jwo normalize "$p" "" "$p.tmp" \
            -v valsfile="$TMPD/.cirno_norm_vals" -v keyfile="$TMPD/.cirno_norm_keys"
        apply_multi "$p" "规范化 #uid -> #0 ($n 个字段)"
        case $? in
            0) ;;
            1) info "$(basename "$p") 已是 #0 格式" ;;
            2) warn "$(basename "$p") 规范化失败" ;;
        esac
        rm -f "$TMPD"/.cirno_norm_*
    done
    flush_wrote hot_reload
}

c_validate() {
    p=$(resolve "${1:-app}")
    r=$(jwq validate "$p")
    case "$r" in
        OK) ok "$(basename "$p") JSON 合法" ;;
        *)  echo "$R$r$N"; exit 2 ;;
    esac
    if [ -f "$p" ]; then
        s=$(perm_of "$p")
        info "属主/权限 $s"
        [ "$s" = "1000:1000 -rw-rw----" ] || warn "属主/权限不对，跑 fix-perm"
    fi
}

c_show() {
    p=$(resolve "${1:-app}")
    if [ -n "$2" ]; then
        t=$(jwq type "$p" "$2")
        [ "$t" = ABSENT ] && die "没有字段 $2"
        jwq get "$p" "$2"
    else
        jwq list "$p"
    fi
}

c_keys() { jwq keys "$(resolve "${1:-app}")"; }

# 列出 app/global 所有字段(中文+英文)
c_fields() {
    echo "${B}── ApplicationSettings (应用配置) ──$N"
    jwq list2 "$APP"
    echo ""
    echo "${B}── GlobalSettings (全局配置) ──$N"
    jwq list2 "$GLB"
}

# 交互选择字段, 结果写入 $SEL
# 支持: 序号(3 / 1 3 5 / 1,3,5 / 1-4) 或 字段名(英文/中文/模糊) 或 a(全部) / q(取消)
pick_fields() {
    SEL=""
    echo "请选择要操作的配置字段 (可多选):"
    echo "  ${B}a${N} = 全部   ${B}q${N} = 取消"
    echo "  序号: 单个 ${B}3${N}, 多个 ${B}1 3 5${N} / ${B}1,3,5${N} / ${B}1-4${N}"
    echo "  名字: 英文 ${B}blackApps${N} / 中文 ${B}黑名单${N}, 支持模糊匹配(如 net)"
    echo ""
    c_fields
    echo ""
    printf "选择: "
    read -r choice
    [ -z "$choice" ] && { warn "未选择"; return 1; }
    case "$choice" in
        q|Q|quit|exit|取消) warn "已取消"; return 1 ;;
    esac

    set -A ALLNAMES
    set -A ALLCN
    set -A ALLLC
    n=0
    for f in $(cfgs); do
        for k in $(jwq keys "$f" | awk '{print $1}'); do
            n=$((n+1))
            ALLNAMES[$n]="$k"
            ALLCN[$n]=$(cnname "$k")
            ALLLC[$n]=$(echo "$k" | tr 'A-Z' 'a-z')
        done
    done

    SEL=""
    case "$choice" in
        a|A|all|ALL|全部)
            for i in $(seq 1 $n); do SEL="$SEL ${ALLNAMES[$i]}"; done
            ;;
        *)
            for tok in $(echo "$choice" | sed 's/，/ /g' | tr ',' ' '); do
                case "$tok" in
                    ''|*[!0-9-]*)
                        # 字段名: 先精确匹配(英文键/中文名), 再模糊
                        lc=$(echo "$tok" | tr 'A-Z' 'a-z')
                        hit=""
                        for i in $(seq 1 $n); do
                            if [ "${ALLLC[$i]}" = "$lc" ] || [ "${ALLCN[$i]}" = "$tok" ]; then
                                hit="$hit $i"
                            fi
                        done
                        if [ -z "$hit" ]; then
                            for i in $(seq 1 $n); do
                                case "${ALLLC[$i]}" in *"$lc"*) hit="$hit $i" ;; esac
                            done
                        fi
                        if [ -z "$hit" ]; then
                            for i in $(seq 1 $n); do
                                case "${ALLCN[$i]}" in *"$tok"*) hit="$hit $i" ;; esac
                            done
                        fi
                        if [ -n "$hit" ]; then
                            for i in $hit; do SEL="$SEL ${ALLNAMES[$i]}"; done
                        else
                            warn "找不到字段: $tok"
                        fi
                        ;;
                    *)
                        idx=""
                        case "$tok" in
                            *-*-*|-*|*-) warn "忽略无效项: $tok"; continue ;;
                            *-*)
                                a=${tok%%-*}; b=${tok##*-}
                                bad=0
                                case "$a" in ''|*[!0-9]*) bad=1 ;; esac
                                case "$b" in ''|*[!0-9]*) bad=1 ;; esac
                                if [ "$bad" = 1 ] || [ "$a" -gt "$b" ]; then
                                    warn "忽略无效项: $tok"
                                    continue
                                fi
                                idx=$(seq "$a" "$b")
                                ;;
                            *) idx="$tok" ;;
                        esac
                        for i in $idx; do
                            if [ "$i" -ge 1 ] && [ "$i" -le "$n" ]; then
                                SEL="$SEL ${ALLNAMES[$i]}"
                            else
                                warn "超出范围: $i"
                            fi
                        done
                        ;;
                esac
            done
            ;;
    esac

    SEL=$(echo "$SEL" | uniq_words)
    [ -n "$SEL" ] || { warn "未选中任何字段"; return 1; }
    return 0
}

# 输出所选字段的值
c_get() {
    pick_fields || return 1
    echo ""
    for k in $SEL; do
        p=$(file_of "$k" "$GLB")
        echo "${B}════════════════════════════════$N"
        jwq dump "$p" "$k"
    done
    echo "${B}════════════════════════════════$N"
    info "共 $(echo $SEL | wc -w) 个字段"
}

# 按文件分组生成选中字段清单
sel_for_file() {
    tf="$1"
    for k in $SEL; do
        [ "$(file_of "$k" "$GLB")" = "$tf" ] && echo "$k"
    done
}

# 批量同步所选字段 (按文件分组, 每文件只写一次)
c_bulksync() {
    pick_fields || return 1
    echo ""
    printf "同步模式: ${B}c${N} 覆盖(只留已安装) / ${B}m${N} 追加(保留原+补新) / ${B}d${N} 预览 / ${B}q${N} 取消 [默认 m]: "
    read -r md
    case "$md" in q|Q) warn "已取消"; return 1 ;; esac
    [ -z "$md" ] && md=m

    mmode=""; dflag=""
    case "$md" in
        c|C) mmode="replace" ;;
        m|M) mmode="merge" ;;
        d|D) dflag=1; mmode="merge" ;;
        *) die "无效模式 $md" ;;
    esac

    set -A PKGS $(get_pkgs 1 1)
    cnt=${#PKGS[@]}
    [ "$cnt" -gt 0 ] || die "没抓到任何包"
    info "第三方应用 $cnt 个 (真实UID)"
    [ -n "$dflag" ] && info "预览模式, 不会写入"

    VF="$TMPD/.cirno_bulk"
    printf '%s\n ' "${PKGS[@]}" > "$VF"

    for tf in $(cfgs); do
        sel_for_file "$tf" > "$TMPD/.cirno_sel"
        [ -s "$TMPD/.cirno_sel" ] || continue

        # 过滤出真正的列表字段
        : > "$TMPD/.cirno_ok"
        echo ""
        printf "%s── %s ──%s\n" "$B" "$(basename "$tf")" "$N"
        while read -r k; do
            t=$(jwq type "$tf" "$k")
            if [ "$t" != "LIST" ]; then
                printf "  %s✗ %s (%s) 不是列表, 跳过%s\n" "$R" "$(cnname "$k")" "$k" "$N"
                continue
            fi
            echo "$k" >> "$TMPD/.cirno_ok"
            cur=$(jwq count "$tf" "$k")
            if [ -n "$dflag" ]; then
                if [ "$mmode" = "merge" ]; then
                    nw=$(jwq unioncount "$tf" "$k" -v valsfile="$VF")
                else
                    nw=$cnt
                fi
                printf "  %s[预览]%s %s  %s -> %s\n" "$D" "$N" "$(cnname "$k")" "$cur" "$nw"
            fi
        done < "$TMPD/.cirno_sel"

        [ -n "$dflag" ] && continue
        [ -s "$TMPD/.cirno_ok" ] || continue

        jwo syncmulti "$tf" "" "$tf.tmp" \
            -v keyfile="$TMPD/.cirno_ok" -v valsfile="$VF" -v mode="$mmode"
        apply_multi "$tf" "批量同步 $(wc -l < "$TMPD/.cirno_ok") 个字段"
        case $? in
            0) while read -r k; do
                   now=$(jwq count "$tf" "$k")
                   printf "  %s✓%s %s  -> %s\n" "$G" "$N" "$(cnname "$k")" "$now"
               done < "$TMPD/.cirno_ok" ;;
            1) printf "  %s=%s 无变化%s\n" "$D" "$N" "$N"; continue ;;
            2) printf "  %s✗ %s 失败%s\n" "$R" "$(basename "$tf")" "$N"; continue ;;
        esac
    done
    echo ""
    [ -n "$dflag" ] && echo "${D}(预览结束, 未写入)$N" || ok "批量同步完成"
    flush_wrote reload_after_write
}

# 批量清空所选列表字段
c_bulkclear() {
    pick_fields || return 1
    echo ""
    info "将清空以下字段:"
    for k in $SEL; do
        tf=$(file_of "$k" "$GLB")
        meta=$(jwq meta "$tf" "$k")
        printf "  %s  (%s, %s)\n" "$(cnname "$k")" "$k" "$(echo "$meta" | tr '\t' ' ')"
    done
    echo ""
    printf "确认清空? ${R}y${N}=是 其它=否: "
    read -r ans
    [ "$ans" = y ] || [ "$ans" = Y ] || { warn "已取消"; return 1; }

    for tf in $(cfgs); do
        sel_for_file "$tf" > "$TMPD/.cirno_sel"
        [ -s "$TMPD/.cirno_sel" ] || continue
        jwo clearmulti "$tf" "" "$tf.tmp" -v valsfile="$TMPD/.cirno_sel"
        apply_multi "$tf" "批量清空 $(wc -l < "$TMPD/.cirno_sel") 个字段"
        case $? in
            0) ok "$(basename "$tf") 已清空: $(tr '\n' ' ' < "$TMPD/.cirno_sel")" ;;
            1) info "$(basename "$tf") 无需清空" ;;
            2) warn "$(basename "$tf") 失败" ;;
        esac
    done
    flush_wrote reload_after_write
}

c_add() {
    [ $# -ge 2 ] || die "用法: add <字段> <包名...>"
    k="$1"; shift
    p="$APP"
    for v in "$@"; do
        case "$k" in
            networkMessageApps|networkSpeedApps)
                case "$v" in *"#"*) ;; *) v="$v#0" ;; esac ;;
        esac
        printf '%s\n' "$v"
    done > "$TMPD/.cirno_vals"
    jwo add "$p" "$k" "$p.tmp" -v valsfile="$TMPD/.cirno_vals"
    strip_status
    apply_edit "$p" "向 $k 添加" warn "全部已存在"
}

c_del() {
    [ $# -ge 2 ] || die "用法: del <字段> <包名...>"
    k="$1"; shift
    p="$APP"
    printf '%s\n ' "$@" > "$TMPD/.cirno_vals"
    jwo del "$p" "$k" "$p.tmp" -v valsfile="$TMPD/.cirno_vals"
    strip_status
    apply_edit "$p" "从 $k 删除" warn "没找到"
}

c_set() {
    [ $# -ge 2 ] || die '用法: set [app|global] <字段> <JSON值>'
    target_field "$1" "$2"
    shift "$SKIP"
    raw="$*"
    case "$raw" in
        \[*|\{*|\"*|true|false|null|[0-9]*|-*) v="$raw" ;;
        *) v=$(shq "$raw") ;;
    esac
    old=$(jwq get "$p" "$k")
    jwo set "$p" "$k" "$p.tmp" -v val="$v"
    apply_edit "$p" "$k: ${old:-<无>} -> $v" die "写入失败" "写入失败"
}

c_unset() {
    [ $# -ge 1 ] || die "用法: unset [app|global] <字段>"
    target_field "$1" "$2"
    jwo unset "$p" "$k" "$p.tmp"
    apply_edit "$p" "删除字段 $k" warn "字段 $k 不存在" "失败"
}

c_fixperm() {
    for p in $(cfgs); do
        chmod 660 "$p"; chown 1000:1000 "$p"
        restorecon -F "$p" 2>/dev/null
    done
    restorecon -RF "$DIR" 2>/dev/null
    ok "属主 system:system / 660 / SELinux 已修复"
}

c_backups() {
    fs=$(ls -1 "$BAK"/*.json 2>/dev/null)
    [ -z "$fs" ] && { echo "无备份"; return; }
    echo "$fs" | while read f; do
        printf "%s  %s  %s bytes\n" "$(date -r "$f" '+%m-%d %H:%M:%S' 2>/dev/null || echo '?')" "$(basename "$f")" "$(ls -ln "$f" | awk '{print $5}')"
    done
}

c_rollback() {
    fs=$(ls -1 "$BAK"/*.json 2>/dev/null)
    [ -z "$fs" ] && die "无备份"
    n=${1:-1}
    src=$(echo "$fs" | tail -n "$n" | head -n 1)
    [ -f "$src" ] || die "没有第 $n 个备份"
    case "$src" in *ApplicationSettings*) tgt="$APP" ;; *) tgt="$GLB" ;; esac
    cp "$src" "$tgt.tmp"
    commit "$tgt" "回滚自 $(basename "$src")"
}

c_reload() {
    info "重启 Cirno App"
    restart_app
    ok "已重启 Cirno App"
}

# 写完配置后调用：Cirno App 的界面是内存态，只热更新 hook 进程，
# 不重开 App 的话列表数字不会变（表现为"同步了但软件里没变化"）
reload_after_write() {
    echo ""
    info "配置已写入，正在重启 Cirno App 以刷新界面"
    restart_app
    ok "已重启 Cirno App（界面列表已刷新）"
}

c_log() {
    [ -f "$LOG" ] || die "没有日志 $LOG"
    tail -n "${1:-30}" "$LOG"
    tail -n 200 "$LOG" | grep -q "Read Config 失败" && die "日志里仍有 Read Config 失败"
    return 0
}

c_diff() {
    p="$APP"
    inst="$TMPD/.cirno_inst"
    pm list packages 2>/dev/null | sed -n 's/^package:\(.*\)$/\1/p' | sort -u > "$inst"
    keys="$*"
    [ -z "$keys" ] && keys=$(jwq uidkeys "$p")
    for k in $keys; do
        cnt=$(jwq count "$p" "$k")
        [ "$cnt" = 0 ] && continue
        echo ""
        printf "%s%s%s  (%s 项)\n" "$B" "$k" "$N" "$cnt"
        jwq arr "$p" "$k" | sed 's/#[0-9]*$//' > "$TMPD/.cirno_f"
        gone=$(sort -u "$TMPD/.cirno_f" | while read x; do grep -Fxq "$x" "$inst" || echo "$x"; done)
        if [ -n "$gone" ]; then
            printf "  %s已卸载/不存在:%s %s\n" "$Y" "$N" "$(echo "$gone" | tr '\n' ' ')"
        else
            printf "  %s全部已安装%s\n" "$G" "$N"
        fi
        jwq arr "$p" "$k" | sort | uniq -d > "$TMPD/.cirno_d"
        if [ -s "$TMPD/.cirno_d" ]; then
            printf "  %s重复项:%s %s\n" "$R" "$N" "$(tr '\n' ' ' < "$TMPD/.cirno_d")"
        fi
    done
}

c_doctor() {
    echo "== Cirno 体检 =="
    for p in "$APP" "$GLB"; do
        if [ ! -f "$p" ]; then warn "$p 不存在"; continue; fi
        r=$(jwq validate "$p")
        case "$r" in
            OK) ok "$(basename "$p") JSON 合法" ;;
            *)  echo "$R$r$N" ;;
        esac
        s=$(perm_of "$p")
        if [ "$s" = "1000:1000 -rw-rw----" ]; then ok "$(basename "$p") 属主/权限 $s"
        else warn "$(basename "$p") 属主/权限 $s"; fi
    done
    echo ""
    echo "-- 与已安装应用比对 --"
    c_diff
    echo ""
    echo "-- 最近日志错误 --"
    if [ -f "$LOG" ]; then
        e=$(tail -n 300 "$LOG" | grep "错误")
        [ -n "$e" ] && echo "$e" || echo "  $G无$N"
    else
        echo "  $G无$N"
    fi
}

# 交互选择"可同步的包列表字段"，故意排除 blackApps / whiteApps
# 结果写到 stdout（空格分隔的字段名），供 c_sync 使用
pick_list_fields() {
    set -A FN
    set -A FC
    set -A FL
    n=0
    for p in $(cfgs); do
        loc=$(basename "$p" .json)
        for k in $(jwq uidkeys "$p"); do
            case "$k" in
                blackApps|whiteApps) continue ;;
            esac
            n=$((n + 1))
            FN[$n]="$k"
            FC[$n]=$(cnname "$k")
            FL[$n]="$loc"
        done
    done
    [ "$n" -gt 0 ] || { warn "没有可同步的包列表字段"; return 1; }

    echo ""
    echo "可同步字段 (blackApps / whiteApps 已排除，需单独用 add/del 维护):"
    i=1
    while [ "$i" -le "$n" ]; do
        cnt=$(jwq count "$APP" "${FN[$i]}" 2>/dev/null)
        [ "$cnt" = "0" ] && cnt=$(jwq count "$GLB" "${FN[$i]}" 2>/dev/null)
        printf "  %2d) %-18s %-24s %-18s %s 项\n" "$i" "${FC[$i]}" "${FN[$i]}" "${FL[$i]}" "$cnt"
        i=$((i + 1))
    done
    echo ""
    echo "  输入示例: 1 2 3  /  1,2,3  /  1-3  /  a(全部)  /  q(取消)"
    printf "选择: "
    read -r ch
    case "$ch" in
        ""|q|Q|quit|exit|取消) warn "已取消"; return 1 ;;
    esac

    out=""
    case "$ch" in
        a|A|all|ALL|全部)
            i=1
            while [ "$i" -le "$n" ]; do out="$out ${FN[$i]}"; i=$((i + 1)); done
            ;;
        *)
            for tok in $(echo "$ch" | sed 's/，/ /g' | tr ',' ' '); do
                case "$tok" in
                    ''|*[!0-9-]*)
                        # 允许直接写字段名
                        for i in $(seq 1 "$n"); do
                            [ "${FN[$i]}" = "$tok" ] && out="$out ${FN[$i]}"
                        done
                        ;;
                    *-*)
                        a=${tok%%-*}; b=${tok##*-}
                        case "$a$b" in
                            *[!0-9]*) continue ;;
                        esac
                        [ "$a" -le "$b" ] || continue
                        for i in $(seq "$a" "$b"); do
                            [ "$i" -ge 1 ] && [ "$i" -le "$n" ] && out="$out ${FN[$i]}"
                        done
                        ;;
                    *)
                        [ "$tok" -ge 1 ] && [ "$tok" -le "$n" ] && out="$out ${FN[$tok]}"
                        ;;
                esac
            done
            ;;
    esac
    out=$(echo "$out" | uniq_words)
    [ -n "$out" ] || { warn "未选中任何字段"; return 1; }
    echo "$out"
}

c_sync() {
    case "$1" in
        ""|list|ls) ;;
        net)   shift; set -- blockAutostartApps networkMessageApps networkSpeedApps "$@" ;;
        all)   shift; set -- --auto "$@" ;;
        merge) shift; set -- --auto --merge "$@" ;;
        uid)   shift; set -- --auto --merge "$@" ;;
        dry)   shift; set -- --auto --dry-run "$@" ;;
        pick|choose) shift; set -- --pick "$@" ;;
    esac
    uid=0; all=0; merge=0; dry=0; auto=0; norel=0; pickf=0; bw=0; allf=0; fields=""
    for a in "$@"; do
        case "$a" in
            --uid)        uid=1 ;;
            --all)        all=1 ;;
            --merge)      merge=1 ;;
            --dry-run|-n) dry=1 ;;
            --auto)       auto=1 ;;
            --no-reload)  norel=1 ;;
            --pick)       pickf=1 ;;
            --bw)         bw=1 ;;
            --all-fields) allf=1 ;;
            -*)           die "未知选项 $a" ;;
            *)            fields="$fields $a" ;;
        esac
    done

    if [ -z "$fields" ] && [ $auto = 0 ] && [ $pickf = 0 ]; then
        echo "当前 #uid 格式字段:"
        for p in $(cfgs); do
            loc=$(basename "$p" .json)
            for k in $(jwq uidkeys "$p"); do
                n=$(jwq count "$p" "$k")
                printf "  %-24s %-20s %4s 项\n" "$k" "$loc" "$n"
            done
        done
        echo ""
        echo "用法: sync <字段...> [--all] [--merge] [--dry-run] [--no-reload]"
        echo "      sync pick          交互选择要同步的字段"
        echo "      sync net           三个常用字段: blockAutostartApps networkMessageApps networkSpeedApps"
        echo "      sync all/merge     默认只同步上面这三个常用字段（其余由机主在 App 里手动开）"
        echo "      --all-fields       自动同步时包含全部字段（含后台播放/定位/内存回收等）"
        echo "      --bw               自动同步时也带上 blackApps/whiteApps"
        return
    fi

    # 交互选择字段：只列出真正的包列表字段，排除 blackApps / whiteApps
    if [ $pickf = 1 ]; then
        fields=$(pick_list_fields)
        [ -n "$fields" ] || return 1
        info "已选字段: $fields"
    fi

    if [ "$all" = 1 ]; then tp=0; else tp=1; fi
    if [ "$uid" = 1 ]; then
        wu=1
        warn "--uid 写的是真实UID(包名#10270)，Cirno App 只认 包名#0，界面开关不会变！"
        warn "建议去掉 --uid，改用默认的 #0 格式"
    else wu=0; fi

    set -A PKGS $(get_pkgs $tp $wu)
    cnt=${#PKGS[@]}
    [ "$cnt" -gt 0 ] || die "没抓到任何包 (需要 root / pm 可用)"
    if [ $tp = 1 ]; then s1="第三方"; else s1="全部"; fi
    if [ $wu = 1 ]; then s2="真实UID"; else s2="#0"; fi
    info "抓到 $cnt 个包 ($s1, $s2)"

    if [ "$auto" = 1 ]; then
        # 默认只同步这三个"常用"字段，其余字段（后台播放/定位/内存回收/冻结排除…）
        # 由机主在 App 里手动开，避免脚本一把梭把用户没要的开关全点亮。
        # 要全字段显式加 --all-fields。
        if [ "$allf" = 1 ]; then
            fields=$(uidkeys_all | tr '\n' ' ')
        else
            fields=""
            for f in blockAutostartApps networkMessageApps networkSpeedApps; do
                if has_field "$APP" "$f" || has_field "$GLB" "$f"; then
                    fields="$fields $f"
                fi
            done
        fi
        [ -n "$fields" ] || { warn "没有可同步的字段"; return; }
        # 默认不碰黑白名单：它们是"人工点名"的语义，灌入全部已安装应用毫无意义。
        # 需要一起同步时显式加 --bw。
        if [ "$bw" != 1 ]; then
            skipped=""
            keep=""
            for f in $fields; do
                case "$f" in
                    blackApps|whiteApps) skipped="$skipped $f" ;;
                    *)                   keep="$keep $f" ;;
                esac
            done
            if [ -n "$skipped" ]; then
                info "已跳过黑白名单:$skipped  (要一起同步加 --bw)"
            fi
            fields="$keep"
            [ -n "$fields" ] || { warn "排除黑白名单后没有可同步的字段"; return; }
        fi
        info "自动同步 $(echo $fields | wc -w) 个字段: $fields"
    fi

    VF="$TMPD/.cirno_pkgs"
    printf '%s\n ' "${PKGS[@]}" > "$VF"

    good=0; bad=0; chg=0
    for f in $fields; do
        target=$(file_of "$f")
        case "$target" in *ApplicationSettings*) loc="ApplicationSettings" ;; *) loc="GlobalSettings" ;; esac
        cur=$(jwq count "$target" "$f")
        t=$(jwq type "$target" "$f")
        if [ "$t" != "LIST" ] && [ "$t" != "ABSENT" ]; then
            printf "  %s✗ %-24s 不是数组, 跳过%s\n" "$R" "$f" "$N"
            bad=$((bad+1)); continue
        fi
        if [ "$merge" = 1 ]; then
            new=$(jwq unioncount "$target" "$f" -v valsfile="$VF")
        else
            new=$cnt
        fi
        if [ "$dry" = 1 ]; then
            printf "  %s[dry-run]%s %-24s %s -> %s  (%s)\n" "$D" "$N" "$f" "$cur" "$new" "$loc"
            continue
        fi
        if [ "$merge" = 1 ]; then
            jwo add "$target" "$f" "$target.tmp" -v valsfile="$VF"
        else
            jwo setarr "$target" "$f" "$target.tmp" -v valsfile="$VF"
        fi
        case "$_st" in
            CHANGED) commit "$target" "$f 同步" 1; chg=$((chg+1)) ;;
            SAME)
                printf "  %s=%s %-24s %s 项 (无变化)\n" "$D" "$N" "$f" "$cur"
                good=$((good+1))
                continue ;;
            *)       echo "$_o"; bad=$((bad+1)); continue ;;
        esac
        printf "  %s✓%s %-24s %s -> %s  (%s)\n" "$G" "$N" "$f" "$cur" "$new" "$loc"
    done

    if [ "$dry" = 1 ]; then
        echo ""
        echo "${D}(dry-run, 未写入任何文件)$N"
        return
    fi

    echo ""
    for p in $(cfgs); do
        r=$(jwq validate "$p")
        if [ "$r" = "OK" ]; then printf "%s✓ %s JSON 合法%s\n" "$G" "$(basename "$p")" "$N"
        else printf "%s✗ %s 损坏: %s%s\n" "$R" "$(basename "$p")" "$r" "$N"; bad=$((bad+1)); fi
    done
    if [ "$bad" = 0 ]; then col="$G"; else col="$R"; fi
    printf "\n%s完成: %d 字段已写入, %d 无变化, %d 失败%s\n" "$col" "$chg" "$((good-chg))" "$bad" "$N"
    if [ "$chg" -gt 0 ]; then WROTE=1; fi
    if [ "$WROTE" = 1 ]; then
        WROTE=0
        hotcheck 4
        [ "$norel" = 1 ] || reload_after_write
    fi
}

# ---------- 一键全套 ----------
one_click() {
    echo "======================================"
    echo "  Cirno 一键全套   $(date '+%m-%d %H:%M:%S')"
    echo "======================================"
    echo
    echo ">>> 1/4 修复属主/权限/SELinux"
    c_fixperm
    echo
    echo ">>> 2/4 体检"
    c_doctor
    echo
    echo ">>> 3/4 同步全字段 (真实UID / 只追加)"
    c_sync uid
    echo
    echo ">>> 4/4 重启 Cirno App"
    c_reload
    echo
    echo "全部完成。"
}

# ---------- 菜单 ----------
menu() {
    while :; do
        cat <<'EOF'

──── Cirno 菜单 ────
 1) 一键全套 (修权限+体检+同步+重启)
 2) 体检 doctor
 3) 同步 net  (三常用字段 / 覆盖)
 4) 同步 uid  (全字段 + 真实UID + 追加, 不含黑白名单)
 5) 预览同步 dry
 6) 查看字段 sync
 7) 查看配置 show
 8) 找幽灵包 diff
 9) 备份列表 backups
10) 回滚 rollback
11) 看日志 log
12) 修权限 fix-perm
13) 重启 Cirno App
14) 浏览全部配置 (中文/英文对照)
15) 选择配置并输出 (可多选)
16) 多选字段批量同步
17) 多选字段批量清空
18) 交互选择字段并同步 (sync pick)
19) 检查热更新 hotcheck
 0) 退出
────────────────────
EOF
        printf '选择: '
        read c
        case "$c" in
            1)  one_click ;;
            2)  c_doctor ;;
            3)  c_sync net ;;
            4)  c_sync uid ;;
            5)  c_sync dry ;;
            6)  c_sync ;;
            7)  c_show ;;
            8)  c_diff ;;
            9)  c_backups ;;
            10) c_rollback ;;
            11) c_log ;;
            12) c_fixperm ;;
            13) c_reload ;;
            14) c_fields ;;
            15) c_get ;;
            16) c_bulksync ;;
            17) c_bulkclear ;;
            18) c_sync pick ;;
            19) hotcheck 6 ;;
            0|q|Q) exit 0 ;;
            *)  echo "无效选择" ;;
        esac
    done
}

usage() {
    cat <<'EOF'
Cirno 一键脚本 (单文件 / 零依赖版)
不需要 Termux、不需要 Python，只要有 root

【一键】
  sh Cirno一键脚本.sh              一键全套
  sh Cirno一键脚本.sh menu         交互菜单

【浏览 / 选择配置】★新
  fields                  中英对照列出所有配置字段
  get                     交互多选字段并输出内容
  bulksync                交互多选字段批量同步(按文件只写一次)
  bulkclear               交互多选字段批量清空
                          选择支持 序号 3 / 1 3 5 / 1,3,5 / 1-4
                          或字段名 blackApps / 黑名单 / white,net(模糊) / a(全部) / q(取消)

【同步包列表】
  sync                    列出所有 #uid 格式字段及数量
  sync pick               交互选择字段再同步
  sync net                同步三个常用字段(覆盖)  ← 默认就用这个
  sync all                自动同步(覆盖, 只这三个常用字段)
  sync merge              自动同步(只追加, 只这三个常用字段)
  sync uid                全字段 + 只追加   ← 最全
  sync dry                预览, 不写入
  sync <字段> [选项]       同步指定字段, 可多个

  选项: --all 含系统包 | --merge 只追加 | --dry-run 预览
        --no-reload 写后不重启 App | --bw 也带上 blackApps/whiteApps
        --all-fields 自动同步时包含全部字段

  默认只同步这三个: blockAutostartApps networkMessageApps networkSpeedApps
  其余字段(后台播放/定位/内存回收/冻结排除/后台OOM等)请在 App 里手动开
  注意: 配置里必须写 包名#0, 写真实UID(包名#10270)App 不认, 开关不会变

【热更新自检】
  hotcheck [秒]           看日志确认 App 是否真的收到配置变更

【配置编辑器】
  doctor                  一键体检(JSON/权限/包名比对/日志错误)
  validate [app|global]   只校验 JSON
  show [app|global] [字段] 查看配置
  keys  [app|global]      列出所有字段
  add <字段> <包名...>     安全添加(自动去重、自动 #0)
  del <字段> <包名...>     安全删除
  set <字段> <JSON值>      改单个值
  unset <字段>            删字段
  diff [字段]             找幽灵包/重复项
  fix-perm                修复属主 system:system / 660 / SELinux
  backups                 列出备份
  rollback [n]            回滚到倒数第 n 个备份
  reload                  重启 Cirno App
  log [行数]              看日志

原则：写入前必校验、必备份、保留 inode 原地写入（App 热更新才生效），绝不产生半个 JSON。
EOF
}

# ---------- 入口 ----------
case "$1" in
    ""|one|all|--one)     one_click ;;
    menu|-m)              menu ;;
    fields|ls)            c_fields ;;
    get|pick|select)      c_get ;;
    bulksync|bs)          c_bulksync ;;
    bulkclear|bc)         c_bulkclear ;;
    help|-h|--help|usage) usage ;;
    doctor)               c_doctor ;;
    validate|check)       shift; c_validate "$@" ;;
    show)                 shift; c_show "$@" ;;
    keys)                 shift; c_keys "$@" ;;
    add)                  shift; c_add "$@" ;;
    del|rm)               shift; c_del "$@" ;;
    set)                  shift; c_set "$@" ;;
    unset)                shift; c_unset "$@" ;;
    diff)                 shift; c_diff "$@" ;;
    fix-perm)             c_fixperm ;;
    normalize|norm|fix-uid) c_normalize ;;
    backups)              c_backups ;;
    rollback)             shift; c_rollback "$@" ;;
    reload)               c_reload ;;
    hotcheck|hot)         shift; hotcheck "${1:-6}" ;;
    log)                  shift; c_log "$@" ;;
    sync)                 shift; c_sync "$@" ;;
    *)                    c_sync "$@" ;;
esac
