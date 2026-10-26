# 听书 iOS 客户端 · 项目交接报告（v5.4）

> 更新：2026-10-26 ｜ 仓库 `github.com/leohenshuai/audiodown-ios`（private）｜ 工作目录 `/var/minis/workspace/audiodown`
> 最新产物 `听书-5.4-unsigned.ipa`（306,757 字节，未签名，Info.plist 5.4）｜ 取代 2.6 版交接报告

---

## 0. 先看这三件事

1. **现在应该用哪个分支。** `main` 停在 2.6，**已过时**；功能和界面的最新状态在 `ios26-redesign`（5.4）。一切后续工作从它出发。
2. **iOS 26 风格是“材质近似”，不是真 Liquid Glass。** 目标设备是 iOS 16.3，编译环境是 macos-14 + 旧 SDK，调不到 iOS 26 的真 API。详见 §6。
3. **5.4 刚做了两项结构性改动，尚未经你真机确认**：自建容器取代 `UITabBarController`、首页点击手势修复。装机后先验这两项（§9）。

---

## 1. 这是什么

第三方 iOS 客户端，对接自建的 **AudioDown 服务端 v0.3.13**，提供发现、搜索、专辑、播放、离线缓存、书架管理。界面思路参考「听见有声 1.4.5」，**不含其任何代码**。

| 项 | 值 |
|---|---|
| Bundle ID | `com.leo.audiodown` |
| 显示名 | 听书 |
| 最低系统 | iOS 14.0 |
| 语言 | Objective-C + UIKit，纯代码布局（无 Storyboard / 无 Swift） |
| 代码量 | 约 6300 行（`ADDetail.m` 1887、`ADViews.m` 1766 最大） |
| 目标设备 | iPhone 13 Pro，iOS 16.3，Dopamine 越狱 + TrollStore |

---

## 2. 分支与版本地图

| 分支 | 版本 | 是什么 | 状态 |
|---|---|---|---|
| `main` | 2.6 | 早期稳定点 | **过时**，不含 2.7 以后所有修复 |
| `fix/catalog` | 4.2 | 3.x 功能线 + 早期 iOS26 尝试 | 历史，勿再用 |
| `rollback-3.11` | 3.11 | **功能完整、无 iOS26 风格** 的基线 | 稳定参照点；要“退回朴素界面”就从这出包 |
| `ios26-style` / `ios26-polished` | 4.2 / 4.3 | 旧 iOS26 尝试（`ADGlass` 体系） | 废弃，仅存档 |
| **`ios26-redesign`** | **5.4** | **当前主线**：3.11 功能 + 全新 `ADLiquid` 设计系统 | **使用这个** |

**版本阶段**
- 1.x：首发、下载、离线、搜索分类、预加载
- 2.x：目录与倒序/快速选集修复、听完标记、队列工具条
- 3.0–3.4：**VIP 专辑目录问题定位并解决**（`targetChapterIndex`，见 §4.1）
- 3.5–3.11：书架三视图+长按、搜索空状态（历史/热词/推荐）、触控反馈与提示音、迷你条全局常驻与自动收缩
- 4.x：第一次 iOS26 风格尝试（被推翻重做）
- **5.0–5.4：重做的 iOS26 设计系统**

**建议**：确认 5.4 真机无误后，把 `ios26-redesign` 合进 `main`，并删掉 4.x 的废弃分支，避免下个人迷路。

---

## 3. 服务端接口（实测）

```
Base：https://audio.959935291.xyz:899
鉴权：Authorization: Bearer <token>        前缀：/open-api/v1
```

Token 形如 `xmd_29f7…`，**下划线不能丢**，丢了报 `OPEN_API_TOKEN_INVALID`。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/discover` | 首页板块 |
| GET | `/categories` | 分类树（仅展示，**不能按分类检索**） |
| GET | `/search?q=&page=&pageSize=` | 搜索，混有多个源 |
| GET | `/albums/{id}` | 专辑详情 |
| GET | `/albums/{id}/tracks?page=&pageSize=&targetChapterIndex=` | 目录，**必须带 `targetChapterIndex`**（§4.1） |
| POST | `/cdn/play` | 取音频地址与请求头；番茄源会返回 `downloadPending`，需轮询 |
| GET | `/downloads` | 服务端任务，**只读** |

**不要再碰的**
- `POST /downloads`：会在服务端真的开下载任务，**无法停止**。早期调试时误开过一个 469 集的任务，吃掉约 1.6 GB。
- `/api/*`：需要网页会话 cookie，token 不认。
- 分类检索：`categoryId` 等参数被服务端忽略，分类专辑接口 404。App 里的分类只是**标题关键词猜测**。

---

## 4. 关键问题与根因（踩过的坑）

### 4.1 VIP/音乐合集专辑目录为空 ⭐
- **现象**：《深度睡眠轻音乐》（xm 源，260 集，`accessKind:"vip"`）目录永远空，服务端回 `200 + ok:true + items:[]`，`lastError:"paged 目录未取全: 1-50"`。
- **根因**：服务端有两条取目录路径——**带 `targetChapterIndex` 走“按目标章节定位抓取”（能抓全），不带走“整页批量抓取”（对这类专辑必失败）**。
- **证据**：用“目录诊断”打 9 种参数变体，只有带 `targetChapterIndex=1` 的返回 `loadedCount:50 / partial:false`。听见有声二进制里同样有此字段，所以它能显示。
- **做法**：`ADApi tracksViaToken:` 一律拼 `targetChapterIndex=(page-1)*pageSize+1`。
- **排错工具**：专辑页 ⋯ → **目录诊断**，把 9 种请求的原始返回写进 `Documents/probe_<专辑>.txt`，文件 App 里可取。**以后遇到任何“服务端返回怪”，先跑这个。**

### 4.2 目录分页“时好时坏”
- `cachedGET` 是“先回调缓存、再回调网络”，页面回调里直接 `addObjectsFromArray + page++` → 同一页加两次、页码跳号，**有缓存时必现**重复与缺段。
- 修法：`ADAlbumController` 用 `pageMap[页码]` 按页存，网络覆盖缓存，重建时按页号排序并按 `trackId` 去重。
- **“到底了”不能依赖服务端 `total`**（会缺失/给错）。只认事实：某页返回 0 条（先补拉一次）或整页全是重复 → `endReached`。
- 每页重试 2 次（1.2s/2.4s 退避），并发最多 2 页；目录请求单独 30 秒超时（其它 12 秒）。

### 4.3 播放取地址被抢占
旧版用 `_resolving` 布尔互斥，连点两集时后一次被丢弃，界面永远停在“正在获取音频…”。改成自增 `resolveSeq`，新请求接管，旧回调按序号作废；取地址失败自动重试一次，item 失效（403）再取一次。

### 4.4 搜索中文查不到
`search:` 先转义一次、`request:` 又对整条 URL 转义一次，`%` 变 `%25`，服务端按字面量匹配。修法：`request:` 先用 `NSURL URLWithString:` 解析，失败才转义；关键词用严格字符集 `A-Za-z0-9-._~`。

### 4.5 5.x 阶段的两个 UI 坑
| 坑 | 根因 | 处理 |
|---|---|---|
| 按钮图标消失 | 把 `UIVisualEffectView` 塞进 `UIButton` 内部，盖住了按钮自带的图标/文字 | **按钮不要用 `glass:`**，用 `glassButton:`（半透明填充+描边，不加子视图） |
| 首页封面点不开 | 小卡片上加了 0 秒触发的按压手势，按下即进入识别，吞掉点击 | 去掉小卡片上的按压；全局按压改 0.12 秒触发并与点击/滚动并存 |
| 底栏重影 | `tabBar.hidden=YES` 在页面切换时会被系统重新显示，和自绘条叠加 | **不再使用 `UITabBarController`**，改自建 `ADDockController`（二进制校验引用为 0） |

---

## 5. 代码结构

```
src/
├── main.m            入口；用 ADDockController 承载 3 个 UINavigationController
├── AD.h              全部对外声明（模型/API/播放器/下载/设计系统/控制器）
├── ADCore.m          配置、模型、ADStore（收藏/历史/进度/听完/想听/置顶）、封面缓存
├── ADApi.m           网络层；cachedGET；tracksViaToken；panelLogin(可选账号)；rawGET(诊断)
├── ADPlayer.m        AVPlayer 封装；resolveSeq；预加载；ensureFullQueue(队列补全)
├── ADDownloader.m    本机下载；单集重试 2 次；落盘 <8KB 视为失败
├── ADHaptic.m        触感(轻/选择/重/软/成功/警告/错误) + 系统提示音
├── ADLiquid.m        ★ iOS26 设计系统 + 悬浮底栏 + 自建容器（632 行）
├── ADViews.m         发现 / 搜索 / 书架 / 迷你播放条 / 卡片
├── ADDetail.m        专辑页 / 播放页 / 设置页（最大文件）
├── ADLibrary.m       收听历史 / 本机下载
├── ADSheet.m         自绘底部菜单 ADOptionSheet
└── Assets/           AppIcon 全尺寸（workflow 平铺到包根，放子目录无效）
```

---

## 6. iOS 26 设计系统 `ADLiquid`（5.x 核心）

**定位**：材质近似，iOS 14+ 可用。真 Liquid Glass 需要 iOS 26 SDK，当前 runner 是 `macos-14`，调不到。

| 能力 | 方法 | 说明 |
|---|---|---|
| 背景 | `canvas:` | 深蓝黑渐变 + 左上暖橙光斑 + 右侧冷蓝光斑；暖光 9 秒缓慢漂移 |
| 玻璃面 | `glass:radius:alpha:` | 超薄材质模糊 + 白色色层 + 斜向高光渐变 + 0.65pt 描边 + 连续圆角 |
| **轻量玻璃** | `glassLite:radius:` | 渐变+描边，**零实时模糊**；**列表行/重复卡片必须用它**（书架每行一个模糊层会掉帧） |
| **按钮玻璃** | `glassButton:radius:` | 不加子视图，不遮挡图标；**所有 UIButton 用它** |
| 悬浮投影 | `float:` | 统一阴影 |
| 按压 | `press:` | 0.962 缩放弹簧回弹（0.12s 触发，不吞点击） |
| 入场 | `rise:delay:` | 上浮淡入 |
| 封面取色 | `tintFromImage:` + `recolor:with:` | 缩到 1×1 取平均色并提饱和，页面光斑换成封面色（0.8s 渐变） |
| 封面呼吸 | `breathe:on:` | 播放中 1.0↔1.018 + 投影起伏，3.2 秒周期 |
| 滚动联动 | `followScroll:lastY:` | 向下滚底栏缩小变淡，向上/停止恢复 |

**悬浮底栏 `ADNavDock`（5.4 参照订货单 App 的 `.foot` / `.lens` 重做）**
- 左右各留 14pt、圆角 30、磨砂玻璃 + 投影
- **光圈（lens）**：径向高光渐变 + 描边；**手指按下就滑到所按按钮并放大 1.06**，松手落定；弹簧过冲对应订货单的 `cubic-bezier(.3,1.5,.5,1)`
- 再点当前项 = 回到该页根；进入二级页自动收起
- 参考源：`leohenshuai/pedidos-ios` → `Pedidos/Web/pedidos.html` 第 233、259–268 行

**自建容器 `ADDockController`**：继承 `UIViewController`，持有 `pages`，切换时淡入新页；取当前页用 `selectedViewController`，**不要再写 `UITabBarController` 相关代码**。

**设计规则（新增界面必须遵守）**
1. 背景用 `canvas:`，不要写死 `backgroundColor`。
2. 容器/面板用 `glass:`；**重复出现的行用 `glassLite:`**；按钮用 `glassButton:`。
3. 可点的小卡片**不要**加按压手势（会抢点击）。
4. 迷你播放条的 Y 位置依赖 `ADNavDock.topY` 与 `dockVisible`，改底栏高度要同步看 `ADViews.m` 里 `applyFrame:`。

---

## 7. 功能清单（5.4 现状）

**发现**：搜索胶囊（点了跳搜索 tab）、继续收听大卡（长按菜单：播放/加入书架/收藏/重新获取封面/删除记录）、推荐内容、各板块横滑
**搜索**：在线/本地分段；分类胶囊（本地关键词过滤）；**空状态**=搜索历史（12 条，可清空）+ 大家都在搜（本地词表）+ 推荐收听；清空搜索词立即清结果
**书架**：☰ 菜单（分类：全部/收藏/想听/置顶/已下载/最近播放；显示：详细列表/紧凑列表/封面墙）；**长按菜单**（收藏、想听、删除下载、置顶、从书架移除）；每行含进度条与“已听 N/M 章”
**专辑**：目录分页（见 §4.2）；正序/倒序（倒序先拉全）；每 60 集快速选集；单集/多选下载；缓存整本（先拉全目录）；⋯ → 目录诊断
**播放**：队列工具条（正序/倒序、选集、多选、缓存）；定时关闭（开启后按钮变剩余时间）；倍速；AirPlay；封面呼吸+取色
**迷你条**：全局常驻；**闲置 8 秒（播放/暂停都算）收成右边缘 50×50 小球**；右侧 › 或下滑立即收起；点球/上滑展开
**其它**：触控反馈+提示音（设置里各一个开关）；预加载（默认关，仅 Wi-Fi，1–5 集，自动清理 3/7/30 天）；可选“网页账号”（`panelLogin`，对这台服务端**无实际收益**，见 §8）

---

## 8. 已知限制

1. **没有分类浏览**：服务端不支持，只能标题关键词猜。
2. **服务端下载任务不可控**：只读。
3. **番茄源首次播放慢**：服务端转码，可能几十秒。
4. **搜索结果重复**：同一本书在多源各一条，客户端未去重。
5. **“大家都在搜”是本地词表**，不是真热搜。
6. **“已听 N/M 章”按最后收听位置算**，不是逐集统计（本地只存进度与听完标记）。
7. **网页账号功能基本用不上**：听见有声的 `server_profiles` 里账号密码为空，说明同一台服务端只用 token；`/api/v1/*` 需登录，但目录靠 `targetChapterIndex` 已解决。该设置项可保留，也可删除。
8. 真 Liquid Glass（折射、可折叠标签栏）无法实现，见 §6。

---

## 9. 5.4 装机后请先验证（尚未真机确认）

| # | 检查项 | 预期 |
|---|---|---|
| 1 | 首页任意封面点击 | 能进专辑（之前被手势吞了） |
| 2 | 底栏 | **只有一条**悬浮玻璃条，无重影 |
| 3 | 按住某个标签 | 光圈跟手滑过去，松手落定 |
| 4 | 进专辑再返回 | 底栏收起/复现正常，迷你条位置跟着变 |
| 5 | 发现页右上两个圆钮 | 图标可见 |
| 6 | 书架滚动 | 比 5.2 顺（行已改轻量玻璃） |
| 7 | 播放页 | 封面呼吸；换一本书背景色随封面变化 |
| 8 | 《深度睡眠轻音乐》 | 目录能出 260 集 |

**风险点（我没法在真机验证的）**
- 自建 `ADDockController` 没有 `UITabBarController` 的安全区自动适配；各页面如果底部内容被悬浮条盖住，需要给 scrollView 加底部 inset。
- 手势修改后，卡片“按压回弹”动效可能变得不明显（刻意让点击优先）。
- `canvas:` 的光斑漂移是常驻动画，需观察耗电。

---

## 10. 编译与发布

- 流水线：`.github/workflows/build.yml`，`macos-14` + `xcrun clang`，**不依赖 Xcode 工程**。push `main` 自动触发；**其它分支用 `workflow_dispatch` 指定 `ref`**。
- 链接框架：`UIKit Foundation AVFoundation MediaPlayer CoreMedia CoreGraphics QuartzCore AVKit Security AudioToolbox`（新增系统框架要在这里加）。
- 必须 `mkdir -p build/Payload/ADBook.app`，图标 `cp src/Assets/*` **平铺到包根**。
- 产物是**未签名** IPA，需自备工具（TrollStore / 自签）安装；覆盖安装保留收藏、历史、进度、下载。
- 触发与取包（`GITHUB_TOKEN` 在环境变量里）：

```bash
curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/leohenshuai/audiodown-ios/actions/workflows/build.yml/dispatches \
  -d '{"ref":"ios26-redesign"}'
# 然后轮询 /actions/runs?per_page=1，取 artifacts[0] 的 zip，解出 Audiodown-unsigned.ipa
```

**校验技巧**：ObjC 里的中文串在二进制中是 **UTF-16LE**，用 `rg/strings` 按 UTF-8 搜不到，要用 `python data.count(s.encode('utf-16-le'))`。

**建议**：`GITHUB_TOKEN` 用完后到 GitHub 里撤销/轮换。

---

## 11. 速查：症状 → 原因 → 处理

| 症状 | 原因 | 处理 |
|---|---|---|
| 目录为空，`partial:true` | 缺 `targetChapterIndex` | 3.4 起已带；仍空→⋯→目录诊断 |
| 目录重复/缺一段 | 缓存+网络双回调 | 按页存、去重（2.7） |
| 倒序首行不是最后一集 | 只反转了已加载部分 | 先拉全再反转（2.8） |
| 中文搜不到 | URL 二次转义 | `request:` 先解析（1.9） |
| 点 ⋯ 没反应 | 自绘菜单初始 y 在屏幕外 | y = 屏高 − 高度（2.1） |
| 按钮没图标 | 模糊视图塞进了 UIButton | 用 `glassButton:`（5.2） |
| 首页封面点不开 | 0 秒按压手势吞点击 | 删小卡片手势，全局 0.12s（5.4） |
| 底栏重影 | 系统 tabBar 被重新显示 | 自建容器（5.4） |
| 图标不生效 | 图标放在子目录 | workflow 平铺到包根 |
| 书架滚动卡 | 每行一个实时模糊 | 行用 `glassLite:`（5.3） |
| 编译 `no visible @interface… selector` | 新方法没在 `AD.h` 声明 | 补声明 |
| 编译 `duplicate interface definition` | 内部又写了一遍 `@interface` | 内部用 `@interface X ()` 类扩展 |

---

## 12. 下一步建议（按价值排序）

1. 真机验证 §9，修掉底栏/手势相关回归，然后**合并到 `main`** 并清理旧分支。
2. 给各页面的 scrollView 补**底部 inset**（悬浮底栏高度 + 迷你条），防止最后一行被遮。
3. 搜索结果按标题去重（保留播放量最高的一条）。
4. 逐集听完统计，让“已听 N/M”精确。
5. 热词接口化（需服务端配合）；分类词表可配置。
6. iPad 适配（当前仅 iPhone 竖屏）。
7. 如果升级到能用 iOS 26 SDK 的构建环境，再考虑换成真 `UIGlassEffect`，`ADLiquid` 的封装边界已经留好，替换成本集中在 `glass:` 一处。

---

## 13. 相关文件

- 接口笔记与迭代记录：`PROJECT.md`
- 旧版交接（2.6，已过时）：`HANDOVER.md`
- 5.x 预览：`preview/ios26-redesign.png`（PIL 绘制，**不是真机截图**；生成脚本 `preview/render_ios26.py`）
- 订货单参考底栏：仓库 `leohenshuai/pedidos-ios` → `Pedidos/Web/pedidos.html`
- 听见有声（竞品，仅作参考）：`com.tafe.audiebooksreader`；其 `audiebooks.sqlite3` 的 `server_profiles` 表可用 Filza 的 SQL 框查询
- 浏览器加载多层 `backdrop-filter` 的页面会卡死（已踩过两次），**预览一律用 PIL 直绘**
