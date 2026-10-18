# 上游与依赖

pipecap：https://github.com/a1678991/pipecap
固定源码版本：d045192de888188783b4da74b10ab05f4229c868
本地：pipecap-review，选择性下载源码/锁文件/夹具，保留原LICENSE（MIT，Copyright2026 a1678991）；不是完整历史clone，不设置为自己的上游开发主线。复用或分发保留原声明。

Rust依赖按Cargo.lock固定。上次构建为现有Cargo工具链，补取clap4.6.6、clap_builder4.6.6、clap_derive4.6.4、thiserror2.0.20、thiserror-impl2.0.20、syn3.0.5，其余复用缓存；完整依赖以锁文件为准。无全局安装。

公开无许可证gist仅参考接口声明事实，未复制进本项目。独立DisplayProbe.swift、EDIDProbe.m不依赖BetterDisplay。

重要一手上下文：https://developer.apple.com/forums/thread/814201 。原M5案例不直接证明M2Pro阈值。

作者临时EDID说明：https://github.com/waydabber/BetterDisplay/discussions/1491 ，https://github.com/waydabber/BetterDisplay/discussions/2265 。
