# 🎉 KeyFiesta 键盘庆典

[English](README.md) | **简体中文**

打字时在文字光标处喷出 emoji 烟花/彩带，并播放随机搞笑音效的 macOS 菜单栏小工具。

对所有输入法生效（苹果拼音、五笔、各种第三方输入法都行——它监听的是按键，与输入法无关）。
原生 Swift 编写，安装后 **0.7 MB**、内存约 **20 MB**、空闲时几乎 **0% CPU**。

## ✨ 特性

- 每次按键在**文字光标处**喷 emoji 粒子（彩带 🎉🎊🎀✨🎈 / 烟花 🎆🎇💥⭐🌟）
- 12 条程序合成的卡通搞笑音效（弹簧、鸭叫、喇叭、滑哨……），8 路并发不炸耳
- 菜单栏一键开关特效 / 音效 / 音量三档 / 开机自启
- 密码框自动静默；⌘C 等快捷键不触发
- 空闲零开销：不打字时音频引擎自动暂停，不阻止系统休眠

## 📦 安装

> 这是自签名 app（没买苹果 99 美元/年的开发者签名），所以首次打开要手动放行一次。

1. 从 [Releases](../../releases) 下载 `KeyFiesta.dmg`，双击挂载，把 **KeyFiesta** 拖到 **Applications**。
2. 在「应用程序」里双击 KeyFiesta —— 会被系统拦下（"无法验证"），点「完成」。
3. 打开 **系统设置 → 隐私与安全性**，往下滚到安全提示，点 **「仍要打开」**，认证后再点「打开」。
   - macOS 13/14 可走捷径：右键 app →「打开」→「打开」。
   - 会用终端的话一行解决：`xattr -dr com.apple.quarantine /Applications/KeyFiesta.app`
4. 首次启动会弹「辅助功能」授权：**系统设置 → 隐私与安全性 → 辅助功能 → 打开 KeyFiesta**。
5. 授权后 app 会**自动重启一次**（macOS 要求进程重启才启用辅助功能查询），属正常现象。菜单栏出现 🎉 即就绪。

需要辅助功能权限的原因：感知"有键按下"和定位文字光标。**不读取任何按键内容**（见下）。

## 🔒 隐私

- **不读取、不记录、不传输任何按键内容**。代码只把"有键按下"当作放烟花的信号。
- 无网络访问，无磁盘写入（除菜单设置存进 UserDefaults）。
- 全部源码在 `Sources/KeyFiesta/`，几百行，可自行审计。

## 🎯 各 app 的光标精度

| 类别 | 精度 |
|---|---|
| 备忘录 / Safari / 邮件 / Chrome / VS Code / Claude 桌面版 / Obsidian 等绝大多数 app | **字符级精确** |
| 中文拼音组合期（借输入法候选窗定位） | 基本贴合 |
| **微信** | **不喷特效** |

微信是自绘界面，对系统**完全不暴露**光标位置（业界所有划词/翻译工具在微信里都只能退回鼠标位置）。
与其喷错地方，KeyFiesta 检测到微信就不喷。技术细节见 [设计文档](docs/superpowers/specs/2026-06-12-keyfiesta-design.md)。

## 🛠 从源码构建

需要 macOS 13+ 和 Xcode Command Line Tools（`xcode-select --install`），无需 Xcode：

```bash
python3 scripts/make_sounds.py   # 生成音效（已入库，可跳过）
./scripts/build.sh               # 产出 dist/KeyFiesta.app 和 .zip
./scripts/make_dmg.sh            # 产出 dist/KeyFiesta.dmg
```

构建脚本默认 ad-hoc 签名（每次重编译后需在系统设置里重新授权辅助功能）。
若钥匙串里有名为 `KeyFiesta Local Signer` 的自签名证书，会自动改用它——
签名身份稳定，授权一次后重编译不再掉权限（开发时强烈推荐，建证书方法见 `scripts/build.sh` 注释）。

## ⚙️ 工作原理（简述）

全局监听 keyDown（辅助功能权限，被动不拦截）→ 后台串行队列做光标定位 → 透明置顶点穿窗里用
`CAEmitterLayer`（GPU）喷粒子 + `AVAudioEngine` 8 路池播音效。光标定位多通道降级：

1. 经典 AX（`kAXBoundsForRange`）—— 原生 app
2. **TextMarker 通道**（`AXSelectedTextMarkerRange` → 洗锚点 → `AXBoundsForTextMarkerRange`）——
   Chromium/Electron（Claude/Obsidian/浏览器）字符级精确，VoiceOver 同款
3. 输入法候选窗 + 按键计数 —— 中文组合期
4. 鼠标兜底

## 🎵 音效版权

全部 12 条音效由 `scripts/make_sounds.py` 程序合成，自有版权，随意分发。

## 📄 License

[MIT](LICENSE)
