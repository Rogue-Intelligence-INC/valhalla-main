# 瓦序 VAL-DAL 主程序

Windows 桌面主程序（`qt/`，`Valhalla.exe`），从 `valhalla-windows` 拆出。`native/` 是共用的本地引擎，`brand/` 是标志，`installer/` 是安装包程序源码，`tools/cdk_gen.py` 生成在线版 CDK。

目录保持原样：CMake 以本目录为根去找 `native/` 和 `brand/`。构建：`qt/build.bat`。`build/`、`dist/` 不入库。
