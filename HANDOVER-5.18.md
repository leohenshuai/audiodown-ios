# 阅听 iOS 客户端 · 项目交接报告（v5.18）

> 更新：2026-10-26 ｜ 仓库 `github.com/leohenshuai/audiodown-ios`（private）｜ 工作目录 `/var/minis/workspace/audiodown`
> 最新产物 `阅听-5.18-unsigned.ipa`（466,920 字节，未签名，版本 5.18 / 编译号 108）｜ 取代 5.4 版交接报告
> **注意：5.5–5.18 全部改动均未经真机功能验证，只在 CI 上确认能编译通过。** 见 §9。

---

## 0. 先看这四件事

1. **用哪个分支**：`main` 停在 2.6，**已彻底过时**。当前主线是 **`feature/5.5`**，5.18 在这里。
2. **App 名字已改**：显示名 `阅听`，Bundle ID 仍是 `com.leo.audiodown`（覆盖安装保留数据）。旧文档里的"听书"指的就是它。
3. **CI 现在会自动发 Release**：每次编译成功都会在 GitHub 发布 `v<版本号>`，App 内的"检查更新"读它。见 §10。
4. **未真机验证**：5.5 到 5.18 这 14 个版本的功能全部没有经过真机确认，装机后请按 §9 逐项验。

---

## 1. 这是什么

第三方 iOS 客户端，对接自建的 **AudioDown 服务端 v0.3.13**，提供发现、搜索、专辑、播放、离线缓存、书架管理。界面思路参考「听见有声 1.4.5」，**不含其任何代码**。

| 项 | 值 |
|---|---|
| 显示名 | 阅听 |
| Bundle ID | `com.leo.audiodown` |
| 最低系统 | iOS 14.0 |
| 语言 | Objective-C + UIKit，纯代码布局（无 Storyboard / 无 Swift） |
| 代码量 | 约 9,650 行，15 个 .m |
| 目标设备 | iPhone 13 Pro，iOS 16.3，Dopamine 越狱 + TrollStore |
| 仓库 | `leohenshuai/audiodown-ios`（**私有**） |

---

## 2. 分支与版本地图

| 分支 | 版本 | 是什么 | 状态 |
|---|---|---|---|
| `main` | 2.6 | 早期稳定点 | **过时**，不要用 |
| `rollback-3.11` | 3.11 | 功能完整、无 iOS26 风格的基线 | 稳定参照点 |
| `fix/catalog` | 4.2 | 3.x + 早期 iOS26 尝试 | 历史 |
| `ios26-style` / `ios26-polished` | 4.2 / 4.3 | 旧 iOS26 尝试 | 废弃 |
| `ios26-redesign` | 5.4 | 5.x 设计系统起点 | 已被 5.18 超越 |
| **`feature/5.5`** | **5.18** | **当前主线** | **用这个** |

### 5.4 → 5.18 都做了什么

| 版本 | 内容 |
|---|---|
| 5.5 | 书签、离线存储管理、备份与恢复、播完本集停、播放模式（单集/整本循环）、启动恢复上次位置 |
| 5.6 | 专辑详情页重做：封面糊化背景、居中大封面、续播主按钮、标签、可展开简介、目录行重绘 |
| 5.7 | 快速选集改骨架占位 + 并行拉页，点击立即滚动到位 |
| 5.8 | 设置并入底栏（第 4 项）、首页去掉下载钮、收听历史重做、继续收听菜单合并 |
| 5.9 | 迷你条左右滑切集 + 圆球旋转、播放页控件缩小、搜索与书架重做 |
| 5.10 | **修复书架/收藏/历史/下载任务重启后丢失**（见 §4.1，最严重的一个） |
| 5.11 | 改名「阅听」，新图标（黑胶底 + 金色"听"字） |
| 5.12 | 分段式下载面板、圆球封面不再超出圆圈 |
| 5.13 | 修快速选集后目录停在 1450 |
| 5.14 | 设置页分组重做、版本号、检查更新、快速选集改分段显示、CI 自动发布 Release |
| 5.15 | 本机下载页重做、单集页编辑、单集下载进度 |
| 5.16 | **修复已下载集无法播放**（MP3 存成 .m4a，见 §4.2）、服务地址显示、三个数据页 UI 重做 |
| 5.17 | 锁屏封面（第一版，有 bug） |
| 5.18 | 修锁屏封面时序，补时长刷新 |

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
| GET | `/albums/{id}/tracks?page=&pageSize=&targetChapterIndex=` | 目录，**必须带 `targetChapterIndex`**（§4.3） |
| POST | `/cdn/play` | 取音频地址与请求头；番茄源返回 `downloadPending` 需轮询 |
| GET | `/downloads` | 服务端任务，**只读** |

**不要再碰的**
- `POST /downloads`：会在服务端真的开下载任务，**无法停止**。早期误开过一个 469 集的任务，吃掉约 1.6 GB。
- `/api/*`：需网页会话 cookie，token 不认。
- 分类检索：`categoryId` 被忽略，分类专辑接口 404。App 里的分类只是**标题关键词猜测**。

**音频格式**：`cdn/play` 返回的多是 **MP3**（文件头 `ID3`），不是 M4A。见 §4.2。

---

## 4. 关键问题与根因（踩过的坑，最有价值的部分）

### 4.1 书架/收藏/历史/下载任务重启后全部丢失 ⭐⭐
- **现象**：用一会儿再重开 App，收藏、历史、想听、下载任务列表全空。进度和听完标记还在。
- **根因**：`ADAlbum` / `ADTask` 只声明了 `NSCoding`，没实现 `NSSecureCoding`；而读取用的是 `unarchivedObjectOfClasses:`（强制安全编码）。解码失败返回 nil，被当成"本来就是空的"，下次一保存就把原文件覆盖成空。另外 `ADTrack` 连 `encodeWithCoder` 都没有，下载任务里的集数列表根本存不住。
- **修法**（5.10）：三个类补 `+supportsSecureCoding` 与按类型解码；新增 `ADUnarchive()`（先安全解码，失败退回非安全解码，兼容旧数据）；`ADStore.load` 读不出的 `fav/hist/want` 先备份成 `.bad`，防止被覆盖。
- **代价**：已经丢的数据恢复不了。

### 4.2 已下载的集无法播放 ⭐⭐
- **现象**：下载显示完成，点播放没反应（在线播放正常）。
- **根因**：`ADDownloader.fileFor:` 一律拼 `<trackId>.m4a`，但服务端给的是 **MP3**（文件头 `ID3`）。AVPlayer 打开本地文件时按扩展名当 MP4 解析 → 直接失败。在线播放不看扩展名，所以只有离线坏。
- **修法**（5.16）：`+extForData:` 按文件头识别 mp3/aac/m4a/flac/ogg/wav；下载完成按真实格式存扩展名；`fileFor`/`hasLocal` 兼容所有扩展名；启动时后台 `fixExtensions` 把旧 `.m4a` 改名（**旧文件不用重下**）；预缓存 `prefetchPath` 同样处理。
- **实测样本**：《深度睡眠轻音乐》竹溪，trackId `290594789`，albumId `XMID29983424`。

### 4.3 VIP/音乐合集专辑目录为空
- **根因**：服务端有两条取目录路径——**带 `targetChapterIndex` 走"按目标章节定位抓取"（能抓全），不带走"整页批量抓取"（对这类专辑必失败）**。
- **做法**：`ADApi tracksViaToken:` 一律拼 `targetChapterIndex=(page-1)*pageSize+1`。
- **排错工具**：专辑页 ⋯ → **目录诊断**，把 9 种参数变体的原始返回写进 `Documents/probe_<专辑>.txt`。遇到"服务端返回怪"先跑这个。

### 4.4 快速选集后目录停在 1450
- **根因**：两个叠加。①区间按 60 集分、目录按 50 集一页，不对齐，旧 `jumpTo` 只按区间**起点**算目标页（1441→第 29 页 = 1401–1450），没拉第 30 页。②缓存回调先把前面页填满、骨架模式立即结束；随后同页网络结果覆盖缓存时"新增 0 条"，被 `loadPage` 误判为"整页重复 = 到底了"，之后再也不翻页。
- **修法**（5.13）：目标页按区间末尾算；覆写已存在页时不判到底（`hadPage`/`nextOfPrefix`）。
- **最终方案**（5.14）：快速选集改**分段显示**——列表只显示当前 60 集，点分段切整段，不再依赖长列表连续加载。这个类问题不会再出现。

### 4.5 锁屏封面一直是灰块
- **第一版死因**（5.17）：`nowPlaying` 里先调 `loadArtwork:` 再写 `nowPlayingInfo`。封面在缓存里时 `coverImage` **同步回调**，把封面写进去后，紧接着又被那份不带封面的 info 覆盖。
- **修法**（5.18）：**先写 info 再取封面**。回调里取当前 info 合并封面。另加 `coverURL` 兜底（`album.cover` 为空时从历史/收藏/想听/下载任务找同书封面）。
- **教训**：可能同步回调的异步接口，调用要放在会覆盖其结果的写操作**之后**。

### 4.6 锁屏进度显示 `--:--`
- **根因**：`nowPlayingInfo` 只在开播时写一次，那时音频时长还没拿到。
- **修法**（5.18）：定时器里 `refreshNowPlayingIfNeeded`——缺时长或缺封面就补写，平时每 10 秒校准一次；`seekTo` 完成后也刷新。

### 4.7 目录分页"时好时坏"
- `cachedGET` 是"先回调缓存、再回调网络"，旧代码在回调里直接 `addObjectsFromArray + page++` → 同一页加两次、页码跳号，**有缓存时必现**。
- 修法：`pageMap[页码]` 按页存，网络覆盖缓存，重建时按页号排序并按 `trackId` 去重。
- **"到底了"不能依赖服务端 `total`**（会缺失/给错）。只认事实：某页返回 0 条（先补拉一次）或整页全是重复 → `endReached`。

### 4.8 播放取地址被抢占
- 旧版用 `_resolving` 布尔互斥，连点两集时后一次被丢弃，界面永远停在"正在获取音频…"。
- 改用自增 `resolveSeq`，新请求接管，旧回调按序号作废。

### 4.9 其它已修的小坑

| 症状 | 原因 | 处理 |
|---|---|---|
| 中文搜不到 | URL 二次转义，`%`→`%25` | `request:` 先 `NSURL URLWithString:` 解析，失败才转义 |
| 点 ⋯ 没反应 | 自绘菜单初始 y 在屏幕外 | y = 屏高 − 高度，靠 transform 滑入 |
| 按钮没图标 | 模糊视图塞进 UIButton | 用 `glassButton:`，不加子视图 |
| 首页封面点不开 | 0 秒按压手势吞点击 | 小卡片不加按压；全局按压改 0.12 秒 |
| 底栏重影 | 系统 tabBar 被重新显示 | 自建 `ADDockController`，不用 `UITabBarController` |
| 书架滚动卡 | 每行一个实时模糊 | 行用 `glassLite:`（零实时模糊） |
| 迷你条圆球海报露出圆外 | 对封面本身同时做圆角 + 旋转，圆角跟着转 | 封面放进圆形裁剪容器 `_disc`，封面放大 1.42 倍只转内层 |
| 暂停/删除被算成下载失败 | 主动 cancel 的 `NSURLErrorCancelled` 被当失败 | 该错误码直接忽略；加 `gen` 序号作废在途请求 |
| 暂停后仍在后台下载 | 在途的取地址请求回来后继续下载 | 回调里校验 `gen` 与任务状态 |

---

## 5. 代码结构

```
src/
├── main.m              入口；ADDockController 承载 4 个 UINavigationController；启动恢复上次位置；每日静默检查更新
├── AD.h                全部对外声明（约 263 行）
├── ADCore.m            配置、ADAlbum/ADTrack 模型、ADStore（收藏/历史/想听/置顶/进度/听完/书签）、封面缓存、ADUnarchive
├── ADApi.m             网络层；cachedGET；tracksViaToken（带 targetChapterIndex）；rawGET（诊断）
├── ADPlayer.m          AVPlayer 封装；resolveSeq；预加载；ensureFullQueue；openAlbum/restoreLast；锁屏信息与封面
├── ADDownloader.m      本机下载；真实格式识别；单集进度；失败集记录；删除/重下/重试
├── ADHaptic.m          触感 + 系统提示音
├── ADLiquid.m          iOS26 设计系统 + 悬浮底栏 ADNavDock + 自建容器 ADDockController
├── ADViews.m           发现 / 搜索 / 书架 / 迷你播放条 / 卡片
├── ADDetail.m          专辑页 / 播放页 / 设置页（最大文件，2786 行）
├── ADLibrary.m         收听历史
├── ADSheet.m           自绘底部菜单 ADOptionSheet
├── ADExtras.m          书签 / 离线存储 / 备份恢复（基于 ADGlassPage + ADGlassRow）
├── ADDownloadSheet.m   分段式下载面板 ADDLSheet（20 集一段）
├── ADDownloadsUI.m     本机下载页 + 单集页（ADDownloadsController / ADDownloadDetailController）
├── ADUpdater.m         GitHub Release 检查更新 + 下载安装包
└── Assets/             AppIcon 全尺寸（workflow 平铺到包根，放子目录无效）
```

---

## 6. iOS 26 设计系统 `ADLiquid`

**定位**：材质近似，iOS 14+ 可用。真 Liquid Glass 需要 iOS 26 SDK，当前 runner 是 `macos-14`。

| 能力 | 方法 | 说明 |
|---|---|---|
| 背景 | `canvas:` | 深蓝黑渐变 + 暖橙光斑 + 冷蓝光斑，暖光 9 秒漂移 |
| 玻璃面 | `glass:radius:alpha:` | 超薄材质模糊 + 高光 + 描边；**只用于容器和面板** |
| 轻量玻璃 | `glassLite:radius:` | 零实时模糊；**列表行/重复卡片必须用它** |
| 按钮玻璃 | `glassButton:radius:` | 不加子视图，不遮图标；**所有 UIButton 用它** |
| 按压 | `press:` | 0.962 缩放弹簧（0.12s 触发，不吞点击） |
| 取色 | `tintFromImage:` / `recolor:with:` | 封面主色换光斑 |
| 呼吸 | `breathe:on:` | 播放中封面 1.0↔1.018 |
| 滚动联动 | `followScroll:lastY:` | 向下滚底栏缩小变淡 |

**悬浮底栏 `ADNavDock`**：4 项（发现/搜索/书架/设置），左右各留 14pt，圆角 30，磨砂玻璃 + 光圈（lens）跟手滑动，按弹簧过冲。再点当前项 = 回该页根；进入二级页自动收起。

**自建容器 `ADDockController`**：继承 `UIViewController`，`pages` 数组，切换淡入。**不要再写 `UITabBarController` 相关代码。**

### 设计规则（新增界面必须遵守）
1. 背景用 `canvas:`，不要写死 `backgroundColor`。
2. 容器/面板用 `glass:`；**重复行用 `glassLite:`**；按钮用 `glassButton:`。
3. 可点的小卡片**不要**加按压手势（会抢点击）。
4. 迷你条 Y 位置依赖 `ADNavDock.topY` 与 `dockVisible`，改底栏高度要同步看 `ADViews.m` 的 `applyFrame:`。
5. 统一页面骨架参考 `ADGlassPage`（渐变背景 / 玻璃返回钮 / 大标题 / 副标题 / 空状态 / 右上按钮）与 `ADGlassRow`（玻璃卡片行）。

---

## 7. 功能清单（5.18 现状）

**发现**：搜索胶囊、继续收听卡片（长按与 ⋯ 同一菜单：继续播放/从头播放/收藏/打开专辑/重新获取封面/从继续收听移除）、推荐内容

**搜索**：大标题 + 玻璃搜索框 + 在线/本地分段；分类胶囊；结果为玻璃卡片行（关键词橙色高亮、已听完/VIP/已收藏/已缓存标签）；空状态 = 搜索历史 + 热词 + 推荐收听

**书架**：分类胶囊条（全部/收藏/想听/置顶/已下载/最近播放）+ 显示方式循环按钮（详细列表/紧凑列表/封面墙）；长按菜单（收藏、想听、删除下载、置顶、从书架移除）

**专辑**：目录分页（§4.3）；**分段显示**（每 60 集一段，点胶囊切整段，默认停在上次听到的段）；正序/倒序；多选；单集/分段下载；⋯ → 分段下载 / 目录诊断；主按钮（继续播放 N 集·听到时间 / 开始收听 / 正在播放）

**播放**：队列工具条（正序/倒序、选集、多选、缓存）；定时关闭（含"播完本集后停止"）；倍速；AirPlay；播放模式（顺序/单集循环/整本循环）；书签；封面呼吸 + 取色；锁屏封面与进度

**迷你条**：全局常驻；左右滑切集；闲置 8 秒收成圆球（唱片造型 + 中心孔 + 播放时旋转）；下滑收起、上滑展开

**下载**：分段式下载面板（20 集一段，可选单集/整段）；本机下载页（专辑卡片、当前集百分比、单集环形进度）；单集页（多选删除/重新下载、左滑删除/重试、点已下载直接播放）；失败集单独记录可重试

**设置**（6 组）：服务（地址/Token/网页账号/保存并测试）、播放（预缓存 4 项）、下载与存储（本机下载/离线存储/全部暂停继续）、体验（触感/提示音）、数据（书签/备份恢复）、关于（版本/检查更新/GitHub 令牌/项目主页）

**其它**：收听历史（大标题 + 玻璃卡片 + 左滑移除/收藏 + 清空）；离线存储管理（占用堆叠条 + 清理 + 按专辑）；备份与恢复（立即备份/分享/从文件导入，含 summary）；预加载（默认关，仅 Wi-Fi，1–5 集，自动清理）

---

## 8. 已知限制

1. **没有分类浏览**：服务端不支持，只能标题关键词猜。
2. **服务端下载任务不可控**：只读。
3. **番茄源首次播放慢**：服务端转码，可能几十秒。
4. **搜索结果未去重**：同一本书在多源各一条。
5. **"大家都在搜"是本地词表**，不是真热搜。
6. **"已听 N/M 章"按最后收听位置算**，不是逐集统计。
7. **检查更新需要令牌**：仓库私有，必须在 设置 → 关于 → GitHub 令牌 填只读令牌（Fine-grained，Contents: Read-only）。令牌存 Keychain（`service=com.leo.audiodown.github`），不进备份。
8. **真 Liquid Glass 无法实现**（折射、可折叠标签栏），见 §6。
9. **备份不含 Token 和已下载音频**：换机后需重填 Token、重下音频。
10. **旧备份没有 summary**：5.16 之前生成的 `.adbak` 只显示时间，不显示收藏/历史/书签数量。

---

## 9. 装机后请先验证（5.5–5.18 全部未真机确认）

按风险从高到低：

| # | 检查项 | 预期 | 对应版本 |
|---|---|---|---|
| 1 | 收藏/历史/想听/下载任务，重启 App 后是否还在 | 全部保留 | 5.10 |
| 2 | 已下载的集能否播放（尤其是 MP3 源的） | 能播，进度正常 | 5.16 |
| 3 | 锁屏 / 控制中心 | 显示书籍封面，进度和时长正确 | 5.17/5.18 |
| 4 | 快速选集点 1441–1500 | 列表切到该段，能继续往后 | 5.13/5.14 |
| 5 | 分段下载面板 | 展开分段、整段/单集勾选、开始下载 | 5.12 |
| 6 | 本机下载页 | 卡片、当前集百分比、点进单集页、多选删除 | 5.15 |
| 7 | 设置 → 关于 → 检查更新 | 填令牌后能读到 v5.18 并下载 | 5.14 |
| 8 | 书签 / 离线存储 / 备份恢复 三个页面 | 玻璃卡片界面正常，功能可用 | 5.16 |
| 9 | 迷你条圆球 | 旋转时四角不露出圆外 | 5.12 |
| 10 | 专辑详情页 | 布局、主按钮文案、目录行、吸顶分段条位置 | 5.6 |
| 11 | 底栏 | 只有一条，四项，光圈跟手 | 5.8/5.14 |

**风险点（我无法在 CI 上发现的）**
- 各页面 scrollView 的底部 inset 是否够（悬浮底栏 + 迷你条会盖住最后一行）。
- 手势冲突：迷你条的左右滑 vs 上下滑、专辑页横滑、`ADLiquid` 全局按压。
- `canvas:` 光斑漂移、迷你条圆球旋转的耗电。
- 自定义导航栏隐藏/显示的切换（`ADGlassPage` 返回设置页时要恢复系统导航栏）。

---

## 10. 编译与发布

- 流水线：`.github/workflows/build.yml`，`macos-14` + `xcrun clang`，**不依赖 Xcode 工程**。
- 触发：push `main` 自动；**其它分支用 `workflow_dispatch` 指定 `ref`**。
- 链接框架：`UIKit Foundation AVFoundation MediaPlayer CoreMedia CoreGraphics QuartzCore AVKit Security AudioToolbox CoreImage`。**新增系统框架必须在这里加**（5.6 漏了 CoreImage 导致链接失败）。
- 必须 `mkdir -p build/Payload/ADBook.app`，图标 `cp src/Assets/*` **平铺到包根**。
- `CFBundleVersion` 用 `GITHUB_RUN_NUMBER` 写入（设置页显示为 `5.18 (108)`）。
- **每次编译成功自动发 Release**：`gh release create v<版本号> YueTing-<版本>-unsigned.ipa`，同版本号重复编译会先删旧 Release 再发。需要 `permissions: contents: write`。
- 产物是**未签名** IPA，需自备工具（TrollStore / 自签）安装；覆盖安装保留数据（Bundle ID 未变）。

触发与取包：

```bash
curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/leohenshuai/audiodown-ios/actions/workflows/build.yml/dispatches \
  -d '{"ref":"feature/5.5"}'
# 轮询 /actions/runs?per_page=1，取 artifacts[0] 的 zip，解出 Audiodown-unsigned.ipa
```

**校验技巧**：ObjC 里的中文串在二进制中是 **UTF-16LE**，`rg/strings` 按 UTF-8 搜不到，要 `python data.count(s.encode('utf-16-le'))`。
**注意**：`GITHUB_TOKEN` 用完建议轮换。

---

## 11. 速查：症状 → 原因 → 处理

| 症状 | 原因 | 处理 |
|---|---|---|
| 收藏/历史重启后消失 | 模型没实现 NSSecureCoding | 5.10 已修；旧数据救不回 |
| 下载好的集放不了 | MP3 存成 .m4a | 5.16 已修，旧文件自动改名 |
| 目录为空，`partial:true` | 缺 `targetChapterIndex` | ⋯→目录诊断 |
| 目录重复/缺一段 | 缓存+网络双回调 | 按页存、去重 |
| 快速选集后目录停住 | 区间与页不对齐 + 误判到底 | 5.13/5.14 |
| 锁屏灰块 | 封面写入被覆盖 | 5.18 已修 |
| 锁屏进度 `--:--` | 只在开播时写过一次 | 5.18 已修 |
| 中文搜不到 | URL 二次转义 | `request:` 先解析 |
| 点 ⋯ 没反应 | 自绘菜单初始 y 在屏幕外 | y = 屏高 − 高度 |
| 按钮没图标 | 模糊视图塞进 UIButton | 用 `glassButton:` |
| 底栏重影 | 系统 tabBar 被重新显示 | 自建容器 |
| 书架滚动卡 | 每行实时模糊 | 行用 `glassLite:` |
| 图标不生效 | 图标放在子目录 | workflow 平铺到包根 |
| 编译 `Undefined symbols` | 新框架没加进 build.yml | 按 §10 的框架列表补 |
| 编译 `no visible @interface … selector` | 新方法没在 `AD.h` 声明 | 补声明 |
| 编译 `use of undeclared identifier` | 宏/常量定义在使用之后 | 移到文件顶部 |
| 编译报 `NSKeyValueObservation` | 那是 Swift 类型 | ObjC 用 `NSKeyValueObservation` 不可用，改轮询或 `observeValueForKeyPath:` |

---

## 12. 下一步建议（按价值排序）

1. **真机验 §9 的 11 项**，把回归修掉，然后 `feature/5.5` 合进 `main`，清理旧分支（`ios26-style`/`ios26-polished`/`fix/catalog`）。
2. 给各页面 scrollView 补**底部 inset**（悬浮底栏 + 迷你条高度），防止最后一行被遮。
3. 搜索结果按标题去重（保留播放量最高的一条）。
4. 逐集听完统计，让"已听 N/M"精确。
5. 备份增加"只恢复某几类"（比如只恢复书签）。
6. iPad 适配（当前仅 iPhone 竖屏）。
7. 升级到能用 iOS 26 SDK 的构建环境后，换真 `UIGlassEffect`——封装边界已留好，替换成本集中在 `glass:` 一处。

---

## 13. 相关文件

- 接口笔记与迭代记录：`PROJECT.md`
- 旧版交接（5.4）：`HANDOVER-5.4.md`（本文件取代它）
- 更旧的交接（2.6，已过时）：`HANDOVER.md`
- 图标生成脚本：`/var/minis/workspace/icons/combo.py`（底色 × 主图形两层可交叉，144 种矩阵 `combo/grid.png`）+ `/tmp/mkicon.py`（BG[7] + FG[1]，即黑胶底 + 金色"听"字）
- 订货单参考底栏：仓库 `leohenshuai/pedidos-ios` → `Pedidos/Web/pedidos.html`
- 听见有声（竞品，仅作参考）：`com.tafe.audiebooksreader`
- **浏览器加载多层 `backdrop-filter` 的页面会卡死**（已踩过两次），预览一律用 PIL 直绘
