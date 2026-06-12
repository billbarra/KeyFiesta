# 键盘庆典 KeyFiesta — 设计文档

日期：2026-06-12
状态：已定稿（用户授权自主决策）

## 背景与目标

用户想要一个 macOS 打字特效小工具：打字时播放随机搞笑音效，并在文字光标处喷出 emoji 粒子（烟花、彩带为主）。要求在苹果输入法和微信输入法下都生效，并能分享给朋友使用。

macOS 没有第三方输入法插件机制，因此产品形态为**独立菜单栏 app**：在系统层监听键盘事件，与输入法无关，天然兼容所有输入法。

### 成功标准

- 在备忘录、Safari、微信等常用 app 中，无论用苹果拼音还是微信输入法，每次按键都有 emoji 粒子从光标处喷出，并伴随随机搞笑音效。
- 密码框中打字无任何特效（安全输入自动静默）。
- 菜单栏可一键关闭特效/音效、调音量、退出。
- 编译产物为单个 .app（zip 打包），朋友右键打开 + 授权辅助功能即可使用。
- 连续快速打字、长按连发不卡顿，空闲时零 CPU 占用。

### 非目标

- 不做公证/上架（无开发者账号签名；macOS 15+ 已移除"右键→打开"豁免通道，分发依靠 系统设置 →「仍要打开」流程，README 给出分步指引）。
- 不做按键内容相关的特效（不读取、不存储任何按键字符——隐私底线，也写进 README）。
- 不做偏好设置窗口；所有控制都在菜单栏菜单里。
- 不支持 Intel Mac（按 arm64 编译；如朋友需要可后续加 universal binary）。

## 技术决策记录

| 决策点 | 结论 | 理由 |
|---|---|---|
| 技术栈 | 原生 Swift + AppKit，swiftc 直接编译 | 本机只有 Command Line Tools（Swift 6.3，无 Xcode），swiftc 可直接产出 .app；轻量无依赖 |
| 触发粒度 | 每键触发音效 + emoji（用户选定） | 音效做短（0.2–0.8s），8 路并发池防炸耳 |
| 控制界面 | 仅菜单栏图标（用户选定） | 无快捷键、无设置窗口 |
| 分发方式 | ad-hoc 签名 .app + zip + README（用户选定：分享朋友） | 免开发者账号；README 写明右键打开步骤 |
| 音效来源 | 脚本程序合成 12 条卡通音效（主路线，100% 自有版权、构建可复现）；Pixabay/Kenney 替换增强留作后续可选 | Pixabay 批量下载需绕 Cloudflare、Freesound 需账号，自动化不可靠；合成路线零授权风险。调研结论见下节 |
| 最低系统 | macOS 13.0 | SMAppService（开机自启）需要 13+；覆盖绝大多数在用设备 |

## 音效授权调研结论（2026-06-12，官方授权页一手来源）

- **Kenney.nl**：全部素材 CC0 公有领域，明确可商用、免署名，打包分发零风险。音频包偏游戏 UI 风格，作点缀。
- **Pixabay Content License**：允许免费使用、修改改编、嵌入作品（含商用），免署名；禁止"原样单独分发"（standalone，即未施加创作性修改、以原始形态分发）。本项目对音效做裁剪、响度归一化、格式转换后嵌入 app 资源，属改编+嵌入用途，符合条款。
- **兜底**：若批量下载受阻，用脚本（正弦扫频、噪声包络等）直接合成卡通音效（弹簧 boing、pop、滑哨、喇叭、放屁声等），100% 自有版权。
- Mixkit 未完成核实（页面被 cookie 横幅遮挡），不采用。

## 架构

```
┌─────────────────────────────────────────────────┐
│                  KeyFiesta.app                   │
│                                                  │
│  KeyMonitor ──按键事件──► Coordinator             │
│   (全局事件监听)              │                    │
│                    ┌────────┴─────────┐          │
│                    ▼                  ▼          │
│             CaretLocator        SoundEngine      │
│             (AX API 定位光标)    (8路播放池)        │
│                    │                             │
│                    ▼                             │
│              FXOverlay                           │
│        (每屏一个透明窗 + CAEmitterLayer)            │
│                                                  │
│  StatusBarMenu (菜单栏 UI) ──读写──► Settings      │
│                                  (UserDefaults)  │
└─────────────────────────────────────────────────┘
```

### 组件职责

**1. KeyMonitor（按键监听）**
- `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`，被动监听，不拦截、不读取字符内容，回调里只取事件的"发生"信号和 `isARepeat` 标记。
- 需要辅助功能权限（`AXIsProcessTrustedWithOptions` 引导授权）。
- 触发范围：排除式过滤——含 ⌘/⌃ 修饰键的组合键（如 ⌘C）与非打字键（Esc、方向键、F1-F12、Home/End/PgUp/PgDn、Help）**不触发**；其余按键（可见字符、空格、回车、删除、Tab 等）触发。⇧/⌥ 组合正常触发（输打字符常用）。
- macOS 安全输入（密码框）下系统不向全局监听器派发事件 → 密码场景自动静默，无需额外处理（验收时验证）。

**2. CaretLocator（光标定位）**
- 三级 fallback，每级失败立即降级：
  1. AX API 精确插入点：焦点元素 `AXSelectedTextRange` → `AXBoundsForRange` 取屏幕坐标；
  2. 焦点文本元素的 frame 中心偏上；
  3. 鼠标当前位置。
- 微信、Chrome/Electron 类 app 对 AX 支持不全，靠 fallback 保证"总有位置可用"。
- AX 查询在后台串行队列执行（IPC 可能慢，不卡主线程）；system-wide AXUIElement 复用单例并设 0.5s 消息超时；查询在途时新按键直接复用上次成功点/鼠标位置，不排队堆积。音效不依赖位置、在按键瞬间先响。
- Chromium/Electron 系 app 默认不渲染辅助功能树（查不到光标）：首次查询失败时对该 app 注入 `AXManualAccessibility` + `AXEnhancedUserInterface` 标志后重试，按 pid 记忆只注入一次。已知权衡：`AXEnhancedUserInterface` 可能轻微影响个别窗口管理工具对该 app 的动画行为。
- Electron 系还会以 err=0 返回**零尺寸垃圾矩形**（实测 Claude/Obsidian 返回 `(0, 屏高, 0, 0)`）：用"像光标"的尺寸约束过滤（高 4–300px、宽 ≤300px），不合格则依次降级：① 空选区时查"前一字符"的 bounds 取右缘（Electron 有文字时常可行）→ ② 焦点元素 frame 中心 → ③ 焦点窗口底部中央（上方 70px、水平居中；针对微信这类自绘 UI 完全不暴露焦点元素的聊天 app，实测其窗口树仅 6 个元素、零文本框）→ ④ 鼠标位置。
- AX 返回的是左上原点屏幕坐标，需转换为 AppKit 左下原点坐标系。

**2b. 光标定位多通道（实测演进，2026-06-12）**
按优先级逐级降级，每次按键在后台串行队列解析：
1. **经典 AX range**（`kAXBoundsForRange`）——苹果原生 app 精确。
2. **TextMarker 通道**（`AXSelectedTextMarkerRange` → 洗锚点 → `AXBoundsForTextMarkerRange`）——
   Chromium/Electron/WebKit（Claude 桌面版、Obsidian、浏览器）字符级精确，VoiceOver 同款私有通道，
   macOS 12 起转正为公开 API。直接用选区 marker 会拿到容器巨矩形或被丢弃的零宽矩形，必须用
   Previous/Next 把锚点下沉到叶子节点并扩成 1 字符 range。Electron 注入辅助功能开关后有 **2 秒防抖**
   才提供字符级几何，故在 app 激活时预注入。
3. **输入法候选窗**（CGWindowList 取候选条位置 + 组合内按键计数估算偏移）——中文组合输入期，
   候选条 x 锚定拼音段起点（系统行为，Squirrel 源码实证），按 ~9pt/键估算当前位置。
4. **降级鼠标位置**。
偶发竞态 miss 复用最近有效点；焦点元素设 0.4s 超时防止卡死主线程；axInFlight 超 1s 自愈。

**关键运维坑（实测）**：
- 给**正在运行**的进程授权辅助功能后，全局按键监听立即生效，但 AX 客户端 API 仍返回 `-25211 APIDisabled`，
  **必须重启进程**才真正启用。故 app 在检测到首次授权后**自动重启自己**（固定签名下授权保留，用户无感）。
- 采用**固定自签名证书**（`KeyFiesta Local Signer`）而非 ad-hoc 签名：designated requirement 基于证书哈希、
  跨重建稳定，辅助功能授权**一次后永久保留**，重编译不再掉权限。

**微信（自绘 UI）—— 技术死角，已排除**：
微信 4.x 对系统辅助功能**完全零暴露**（全树 9 元素、0 文本框，注入开关无效；本机实测 + 多智能体调研双重确认）。
中文社区共识（Easydict 5万★、Bob 等划词工具源码）：拿不到微信光标，只能回退鼠标位置。精确光标唯二出路是
**自建 IMK 输入法**（仅中文有效、极高工程量）或 **dylib 注入微信进程**（有封号风险）——均不适合一个玩具。
故 KeyFiesta 把 `com.tencent.xinWeChat` 放入排除名单，前台是微信时完全不喷，避免错位特效。

**3. FXOverlay（特效层）**
- 每个 NSScreen 一个 borderless NSWindow：`backgroundColor = .clear`、`ignoresMouseEvents = true`、`level = .screenSaver`、`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`，不抢焦点、可点穿、盖在全屏 app 之上。
- 屏幕配置变化（插拔显示器）时监听 `NSApplication.didChangeScreenParametersNotification` 重建窗口。
- 粒子用 `CAEmitterLayer`（GPU 渲染）。emoji 字符先用 NSAttributedString 渲染成 CGImage 并缓存（每个 emoji 渲染一次）。
- 每次按键在光标坐标处随机二选一发射：
  - **彩带喷射**：🎉🎊🎀✨🎈 向上锥形喷出，受重力下落、随机旋转、渐隐；
  - **烟花炸开**：🎆🎇💥⭐🌟 全向放射爆开、速度衰减、渐隐。
  - 另混入低权重 🥳😂。
- 粒子寿命约 1.2–1.5s；burst 节流（80ms 内多次按键合并为一次加强 burst，强度封顶 4）；同屏存活 emitter 上限 12 个，超出直接跳过新 burst，长按连发不失控。

**4. SoundEngine（音效引擎）**
- `AVAudioEngine` + 8 个 `AVAudioPlayerNode` 轮询池；启动时把全部音效解码为 `AVAudioPCMBuffer` 常驻内存（每条 ≤1s，总量很小）。引擎**懒启动**：首次 play() 才启动，停止打字 3s 后自动 pause、关闭音效开关立即 pause——常驻运转的音频 I/O 会持有阻止系统休眠的电源断言并空转 CPU。
- 每键随机挑一条（避免与上一条相同）；8 路全忙时抢占最早开播的一路。
- 音量三档（小 0.3 / 中 0.6 / 大 1.0），作用于 engine mainMixerNode。
- 音效素材：10–14 条短卡通音效（boing 弹簧、pop、鸭叫、喇叭、滑哨上/下、放屁声、squeak、rimshot、卡祖笛、气泡、叮等），统一转为 caf/44.1kHz/mono，响度归一化，首尾静音裁掉。

**5. StatusBarMenu（菜单栏 UI）**
- `NSStatusItem`，标题用 🎉（授权未完成时显示 ⚠️ 并置灰功能项）。
- 菜单项：特效开/关 ✓ ｜ 音效开/关 ✓ ｜ 音量（小/中/大 单选）｜ 开机自启 ✓（SMAppService）｜ 关于（版本+隐私说明）｜ 退出。
- 状态持久化到 UserDefaults。
- `LSUIElement = true`：无 Dock 图标、无主窗口。

### 数据流

```
keyDown 事件（全局监听）
  └─ 过滤（修饰键组合剔除）
      └─ Coordinator.burst()        ← 80ms 节流合并
           ├─ CaretLocator.locate() → (screen, point)
           ├─ FXOverlay.emit(at: point, on: screen, style: 随机)
           └─ SoundEngine.playRandom()      ← 受"音效开关"控制
```

特效开关关闭时 KeyMonitor 直接移除监听器（零开销）；音效单独开关只静音不影响粒子。

## 错误处理与边界情况

| 情况 | 处理 |
|---|---|
| 未授权辅助功能 | 启动时 `AXIsProcessTrustedWithOptions(prompt:true)` 弹系统引导；菜单显示 ⚠️ 与"打开系统设置"项；2s 轮询检测，授权后自动激活 |
| 密码框/安全输入 | 系统不派发事件，自动静默（验收项） |
| AX 定位全部失败 | fallback 到鼠标位置，特效永不缺席 |
| 多显示器/插拔 | 按光标所在屏选窗口；监听屏幕变化通知重建特效窗 |
| 全屏 app / 多 Space | `canJoinAllSpaces` + `fullScreenAuxiliary`，特效跟随 |
| 长按连发 / 高速打字 | 80ms 节流合并 burst；粒子上限；音效 8 路抢占 |
| 音频设备切换/采样率不符 | 配置变化时引擎自动停止，下次 play() 懒启动恢复；播放失败静默忽略（特效不中断） |
| 朋友机器上 Gatekeeper 拦截 | README 写明：拖入 /Applications → 双击让其被拦 → 系统设置「仍要打开」（macOS 13/14 仍可右键打开；或 xattr 去隔离）；ad-hoc 签名保证 arm64 可执行 |

## 隐私

- 不读取、不记录、不传输任何按键内容；事件回调只消费"按键发生"信号。
- 无网络访问、无文件写入（除 UserDefaults 设置项）。
- README 中向用户明示以上两点及辅助功能权限用途。

## 项目结构与构建

```
键盘/
├── Sources/KeyFiesta/        # Swift 源码（main, KeyMonitor, CaretLocator,
│                             #   FXOverlay, SoundEngine, StatusBarMenu, Settings）
├── Resources/
│   ├── Sounds/*.caf          # 处理后的音效
│   └── Info.plist
├── scripts/
│   ├── build.sh              # swiftc 编译 → 组装 .app → ad-hoc codesign → zip
│   ├── fetch_sounds.sh       # （可选）从素材源下载原始音效
│   └── make_sounds.py        # 合成兜底音效 + 裁剪/归一化处理
├── dist/KeyFiesta.app + KeyFiesta.zip
├── README.md                 # 安装步骤（右键打开、授权辅助功能）、隐私说明、致谢
└── docs/superpowers/...      # 设计文档与实现计划
```

- 构建：`swiftc -O -target arm64-apple-macos13.0` 编译全部源文件 → 手工组装 bundle（Contents/MacOS、Resources、Info.plist）→ `codesign --force -s -` → zip。
- 无 SPM 外部依赖，全系统框架（AppKit、AVFoundation、ApplicationServices、ServiceManagement）。

## 测试与验收

逻辑可单测部分（用 swift test 风格的轻量断言脚本验证）：音效随机选择不重复上一条、节流合并逻辑、坐标系转换、设置持久化。

系统集成靠手动验收清单（本机执行）：

1. 备忘录 + 苹果拼音：光标处喷粒子 + 音效 ✅/❌
2. Safari 网页文本框 + 地址栏 ✅/❌
3. 微信聊天框 + 微信输入法 ✅/❌
4. 终端打字 ✅/❌
5. Safari 登录页密码框：完全静默 ✅/❌
6. ⌘C/⌘V 等快捷键：不触发 ✅/❌
7. 长按字母连发 10s：流畅、CPU 占用合理（< ~20%）✅/❌
8. 菜单全部项生效；退出后无残留进程 ✅/❌
9. 全屏 app（如全屏备忘录）中特效可见 ✅/❌
10. zip 解压后的 .app 按 README 的「仍要打开」流程可运行 ✅/❌

微信输入法若本机未安装，安装后验证；无法安装则注明（原理上与输入法无关，风险低）。
