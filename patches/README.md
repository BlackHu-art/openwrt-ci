# 固件构建兼容补丁

`packages/miniupnpd-2.3.11.patch` 原样保留自 ImmortalWrt packages 的
[PR #2001](https://github.com/immortalwrt/packages/pull/2001)，提交
[`11ebc02d3914b5b3e05c964ac1d21f7e5b8cd6be`](https://github.com/immortalwrt/packages/commit/11ebc02d3914b5b3e05c964ac1d21f7e5b8cd6be)。
2026-10-17 检查时，该 PR 尚未合并。

miniupnpd 2.3.11 已包含权限解析与私网地址判断修复，原 feed 的 `020`、`030`
补丁不能重复应用；`040` 日志补丁则需要适配移动后的源码位置。此补丁删除前两者并刷新后者，
保留 UPnP 功能和其余补丁，不降级软件包。

`scripts/Roc-script.sh` 拉取 miniupnpd 后调用 `scripts/fix-miniupnpd-patches.sh`。
辅助脚本只处理 2.3.11，先检查整份补丁可应用再修改文件；同一修复已存在时跳过，
未知补丁冲突会中止构建。升级其他版本后不再应用此兼容补丁；上游正式修复后可复查并移除此处移植。

运行真实源码回归：

```bash
bash tests/miniupnpd-patches.test.sh
```

默认下载固定的故障 feed 提交和官方 2.3.11 源码包，并校验源码包 SHA-256。
也可传入本地原始 `net/miniupnpd` 目录和源码压缩包路径进行离线验证：

```bash
bash tests/miniupnpd-patches.test.sh /path/to/net/miniupnpd /path/to/miniupnpd-2.3.11.tar.gz
```

测试覆盖旧补丁失败复现、完整补丁序列应用、重复调用、其他版本不修改、冲突不部分写入，
以及固件自定义脚本的实际调用路径。此测试不代替完整固件编译或设备上的 UPnP 运行验证。
