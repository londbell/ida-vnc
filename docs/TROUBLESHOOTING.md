# Troubleshooting / 踩坑记录

构建与运行本镜像过程中踩过的坑，按时间顺序记录。新问题请继续追加。

---

## 构建（docker build）

### 1. `--mount=type=bind` 挂载目录是只读的

**现象**：`chmod +x /mnt/downloads/xxx.run` 报 `Read-only file system`。

**原因**：`RUN --mount=type=bind` 默认只读，不能对挂载内容原地改权限。

**解法**：先把文件 `cp` 到 `/tmp` 再 `chmod` 执行。拷贝和删除在同一条 RUN 内完成，不会进入镜像层（600MB 安装包不膨胀镜像的关键）。

### 2. deadsnakes 的 `python3.11` 不含共享库

**现象**：`idapyswitch` 报 `Couldn't parse file name .../libpython3.11.so.1.0`，exit 110。

**原因**：`libpython3.11.so.1.0` 在独立的 `libpython3.11` 包里。原 Dockerfile 靠 `python3.11-dev` 间接带入；瘦身删掉 dev 包后库就没了。

**解法**：显式安装 `libpython3.11`（运行时 idalib 也依赖它）。

### 3. 国内 VM 访问不了 GitHub

**现象**：`uv pip install git+https://github.com/...` 报 `GnuTLS recv error (-110)`。

**解法**：在能上网的机器上克隆仓库放进 `downloads/ida-pro-mcp/`（gitignored），构建时从本地路径安装。同时 pip/uv 走清华 PyPI 镜像（`ARG PYPI_MIRROR` 可覆盖）。

### 4. uv 从本地只读目录安装失败

**现象**：`error: could not create 'src/ida_pro_mcp.egg-info': Read-only file system`。

**原因**：uv 对本地路径包会在**源码目录原地构建**，而源码在只读 bind mount 里。

**解法**：`cp -a` 到 `/tmp` 再安装，装完 `rm -rf`。

### 5. 基础镜像拉取极慢

**解法**：从国内加速源拉取后 tag 回原名，BuildKit 会复用本地镜像：

```bash
docker pull hub.rat.dev/kasmweb/core-ubuntu-jammy:1.14.0
docker tag hub.rat.dev/kasmweb/core-ubuntu-jammy:1.14.0 kasmweb/core-ubuntu-jammy:1.14.0
```

（`mirrors.tencent.com` 对 docker.io 按仓库白名单放行，kasmweb 不在内，会 403。）

### 6. apt 走海外源很慢

**解法**：Dockerfile 里 `sed` 把 `archive/security.ubuntu.com` 换成 `mirrors.tencent.com`。deadsnakes PPA 无国内镜像，只能忍受（包很小）。

---

## 运行（docker run / compose）

### 7. 持久化挂载遮蔽镜像内配置 → IDAPython 未配置

**现象**：IDA 报 `Couldn't initialize IDAPython: Python 3 is not configured`。

**原因**：`idapyswitch` 构建时写的是镜像内 `~/.idapro/ida.reg`；把宿主机空目录挂到 `~/.idapro`（bind mount 不像 named volume 会拷贝镜像内容）后，该文件被遮蔽。

**解法**：root entrypoint 启动时检测 `ida.reg` 缺 `Python3TargetDLL` 就重跑 `idapyswitch`。

### 8. license 文件名不匹配

**现象**：明明放了授权文件，日志却说 `license file not found`。

**原因**：文件名叫 `idapro.hexlic`，脚本只找 `ida.hexlic`。

**解法**：entrypoint 通配 `*.hexlic`，并软链成 IDA 认的 `ida.hexlic`。

### 9. Kasm 的 `custom_startup.sh` 以 uid 1000 运行（不是 root）

**现象**：startup 脚本里 `chown` / `ln` / `idapyswitch` 全部静默失败。

**解法**：加 root entrypoint 包装（`/dockerstartup/ida-entrypoint.sh`）做所有特权操作，完成后 `setpriv --reuid=1000` 降权，再转交 Kasm 原启动链。

### 10. 入口脚本 ≠ 猜的那个

**现象**：`/dockerstartup/kasm-default.sh: No such file or directory`，容器反复重启。

**原因**：凭记忆猜了不存在的脚本名。

**解法**：先查基础镜像真实入口再包装：

```bash
docker inspect kasmweb/core-ubuntu-jammy:1.14.0 \
  --format 'ENTRYPOINT={{json .Config.Entrypoint}} CMD={{json .Config.Cmd}}'
# → 三个脚本串联，后面的作为参数传给第一个
```

### 11. Dockerfile 末尾 `USER 1000` 导致 entrypoint 不是 root

**现象**：entrypoint 里 root 专属操作报 `Operation not permitted`；但 `docker exec -u 0` 手动执行同样的命令却成功。

**原因**：容器启动用户继承 Dockerfile 的 `USER 1000`，而 `docker exec -u 0` 显式覆盖成了 root。`docker exec` 能成功不能证明 entrypoint 是 root。

**解法**：`USER root` + entrypoint 内部降权（见第 9 条）。诊断时先看 `docker inspect <c> --format '{{json .Config.Entrypoint}}'` 确认跑的是不是新镜像。

### 12. `idalib` Python 绑定缺失 → MCP 握手能过但调用会炸

**现象**：`python3.11 -c "import idalib"` 报 ModuleNotFoundError；MCP 握手正常但工具不可用。

**原因**：`idapro`/`idalib` 绑定不在 PyPI 上，是 IDA 安装目录 `/opt/ida-pro/idalib/python/idapro-*.whl` 里自带的 wheel，需要 pip 安装到 Python 环境。`idalib-mcp` 懒加载它，所以握手阶段不报错。

**解法**：Dockerfile 构建时执行
`RUN IDADIR=/opt/ida-pro python3.11 -m pip install /opt/ida-pro/idalib/python/idapro-*.whl`

### 13. `IDADIR` 未设置 → idapro 导入失败

**现象**：`ImportError: Cannot load IDA library file libidalib.so ... IDADIR environment variable is not set`。

**解法**：镜像 ENV 里加 `ENV IDADIR=/opt/ida-pro`。

---

## 教训（vibe coding 复盘）

1. **别静默吞错误**：`2>/dev/null || true` 会把关键报错藏掉，连锁失败时无从定位。WARN 必须打日志。
2. **`docker exec -u 0` 成功 ≠ entrypoint 是 root**：验证运行身份要用 `docker top` / `docker inspect`。
3. **改启动链前先 `docker inspect` 基础镜像的真实 ENTRYPOINT**，不要猜。
4. **bind mount 与 named volume 语义差异**：前者遮蔽镜像内容，后者首次挂载拷贝。持久化配置目录时必须考虑被遮蔽的文件（本例：`ida.reg`）。
5. **瘦身删包要查依赖链**：`libpython3.11` 藏在 `python3.11-dev` 的依赖里，删 dev 前应确认运行时需要什么。
6. **国内构建环境把 GitHub/PyPI 当外部依赖处理**：全部本地化（downloads/ + 镜像源），构建才可复现。
