# 听书 iOS 客户端 · 项目交接报告

> 最后更新：2026-10-25 ｜ 当前版本 **2.7** ｜ 产物 `听书-2.7-unsigned.ipa`（261,177 字节，未签名）

---

## 1. 这是什么

一个第三方 iOS 客户端，对接自建/购买的 **AudioDown** 有声书服务（服务端版本 v0.3.13），提供发现、搜索、专辑、播放、离线缓存、下载管理等功能。UI 参考第三方 App「听见有声 1.4.5」重做，但不含其任何代码。

- Bundle ID：`com.leo.audiodown`
- 显示名：听书
- 最低系统：iOS 14.0
- 语言：Objective-C + UIKit，纯代码布局（无 Storyboard、无 Swift）
- 体积：二进制约 476 KB，IPA 约 257 KB

---

## 2. 服务端接口

### 2.1 基本

```
Base URL：https://audio.959935291.xyz:899
鉴权：Authorization: Bearer <token>
开放 API 前缀：/open-api/v1
```

Token 形如 `xmd_29f78...8e93`（51 字符）。**注意下划线**：`xmd29f7...` 这种缺下划线的写法会被拒（`OPEN_API_TOKEN_INVALID`）。

### 2.2 可用端点

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/discover` | 首页板块：`sections[]`（每个含 title / categoryId / hotWords / items）+ `items[]` |
| GET | `/categories` | 分类树：有声书、儿童、相声评书、音乐、历史、娱乐、外语、个人成长… |
| GET | `/search?q=&page=&pageSize=` | 搜索。返回 `total / totalPages / items[]`，items 里混有 xm/fq/kuwo/qtfm/qidian/netease 多源 |
| GET | `/albums/{albumId}` | 专辑详情 |
| GET | `/albums/{albumId}/tracks?page=&pageSize=` | 曲目分页（每页最多 50，App 固定用 50） |
| POST | `/cdn/play` | body `{trackId, provider, albumId, quality, mode}`，返回 `url` + `headers` |
| GET | `/downloads`、`/downloads/{id}` | 服务端下载任务，**只读** |

### 2.3 已知不可用（别再踩）

- **分类检索**：`/search` 加 `categoryId` / `category` / `type` 等参数，`total` 完全不变（被忽略）；`/categories/{id}/albums`、`/albums?categoryId=` 全部 404；专辑详情里也没有分类字段。→ App 里的分类只能靠标题关键词判断（见 §5）。
- **cdn/stream**：需要服务端签发的临时 stream token，开放 API 无接口换取，直接 401/`OPEN_API_STREAM_TOKEN_EXPIRED`。
- **服务端下载控制**：`POST/DELETE/PATCH` 全部 404 或 405，任务一旦创建无法停止。
- **番茄（fq）源**：`/cdn/play` 经常返回 `WAIT`，需要轮询直到转码完成；专辑详情返回的 `title` 是 `album_74624...` 这种占位串，`cover` 为空 —— 客户端必须忽略这类占位值。
- `/api/*` 一整套需要网页会话，开放 API token 用不了。

### 2.4 一次事故记录

早期为探测下载接口，用 `POST /downloads` 真的在服务端建了一个任务（《鬼吹灯外传》，469 集），跑掉约 1.6 GB 才自己结束，且无法取消。**后续不要再向 `/downloads` 发写请求。**

---

## 3. 代码结构

```
src/
├── main.m            入口，UIWindow + UITabBarController(发现/搜索/书架)，NSUserDefaults 注册默认值
├── AD.h              全部对外声明：模型、API、播放器、下载器、配置、工具、各控制器
├── ADCore.m          ADConfig(读设置) / ADAlbum ADTrack 模型 / ADStore(收藏、历史、进度、听完标记) / ADUtil(封面、时间、颜色、parseDuration)
├── ADApi.m           网络层：request / JSON / cachedGET(先缓存后网络) / 各业务接口
├── ADPlayer.m        AVPlayer 封装：播放、下一集、倍速、定时、锁屏信息、预加载、听完打点
├── ADDownloader.m    本机下载：任务队列、逐集 cdn/play + NSURLSessionDownload、断点、暂停/继续/删除
├── ADViews.m         发现页、搜索页、书架页、卡片组件、迷你播放条
├── ADDetail.m        专辑页、播放页、设置页（最大文件，约 1485 行）
├── ADLibrary.m       收听历史页、本机下载页
├── ADSheet.m         自绘底部菜单 ADOptionSheet（深色、圆角、滑入、点外面关闭）
└── Assets/           AppIcon 全套尺寸（20~1024），workflow 会平铺到包根
```

## 4. 关键实现

### 4.1 播放

- `AVPlayer` + `AVURLAsset`，`AVURLAssetHTTPHeaderFieldsKey`（用字符串字面量，别用常量名，头文件里没有）。
- 播放优先级：本机下载文件 → 预缓存文件 → 请求 `cdn/play` 拿实时地址（带 headers）。
- 番茄源 `WAIT` 状态 → 每 2 秒重试，最多 40 次，UI 显示「音频准备中…」。
- 锁屏：`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`。
- 倍速、定时关闭（15/30/45/60/90 分钟 + 自定义 `20`、`1h30m`、`90s`）、±15 秒、章节列表。

### 4.2 播放页布局（反复调过的公式）

```objc
top = safeTop + 16;  bottomPad = safeBottom + 16;
blockH = 70+28+30+80+40;   lastGap = 18;          // 控制行与底部工具行固定贴近
coverMax = MIN(W - 24, H * 0.52);
leftover = H - top - bottomPad - blockH - coverMax - lastGap;
gap = MIN(22, MAX(6, leftover / 4));
extra: top += extra*0.55, bottomPad += extra*0.45;
```

390×844 下：封面 top 69 / 高 366、标题 457、进度 553、时间 599、控制行 651、底部工具行 749。

### 4.3 缓存

| 内容 | 位置 |
|---|---|
| 接口 JSON | `Documents/cache/*.json`（`ADCacheGet/Set`，超时兜底显示旧数据） |
| 封面 | `Documents/cache/covers/<url hash>.jpg`（落盘，重启后仍可用） |
| 本机下载音频 | `Documents/audio/<trackId>.m4a` |
| 预缓存音频 | `Documents/cache/prefetch/<trackId>.m4a`，按设置自动清理 |
| 收藏/历史/进度/听完 | `fav.dat` `hist.dat` `pos.dat` `last.dat` `info.dat` `done.dat` `donealbums.dat`（NSKeyedArchiver） |

### 4.4 预加载

播放时后台抓后续 N 集（默认 2，可调 1–5）的真实音频地址并落盘；设置里有「仅 Wi-Fi」开关（默认开，检测 `en0` 是否有 IPv4 地址）。关掉后用蜂窝也会预取。

### 4.5 搜索

- 关键词用严格字符集（`A-Za-z0-9-._~`）百分号转义；**请求层不允许再转义整条 URL**，否则 `%` 变 `%25`，服务端按字面量匹配 → 永远搜不到中文。
- 结果排序在客户端二次处理：去空格标点归一化后比较，标题完整含关键词 → 置顶；否则按命中词数。
- 分类胶囊：服务端不支持，只能本地按关键词判断；「有声书」是兜底类（不属于其他细分类的都算）。

---

## 5. 错误处理约定

- 搜索无结果但服务端有错 → 显示错误文本；有缓存 → 静默使用缓存（不弹「当前离线」提示）。
- 目录：按页加载，每页独立重试 2 次（1.2s / 2.4s），并发最多 2 页；某页最终失败只影响该页，底部显示「第 N 段目录没取到 · 已加载 M 集 · 点这里重试」。
- 番茄专辑详情返回 `album_xxx` 占位标题或空封面时，**不覆盖**列表页带过来的正确标题/封面。
- 下载/播放失败都是逐项标记，不影响其他集。

---

## 6. 版本历史

| 版本 | 内容 |
|---|---|
| 1.0 | 首发：发现/搜索/书架/专辑/播放/设置、下载、离线、锁屏 |
| 1.1 | 控件缩小、底部四键菜单化、历史与本机下载页 |
| 1.2 | 设置改 sheet、封面落盘、去掉离线提示、定时自定义、封面首字占位 |
| 1.3 | 章节面板点空白收起 |
| 1.4 | 倍速/定时改自绘面板、定时加取消、目录重试、App 图标 |
| 1.5–1.6 | 搜索分类胶囊、在线/本地搜索 |
| 1.7–1.8 | 单集/多选下载、目录正倒序、每 60 集快速选集、智能预加载 + 仅 Wi-Fi |
| 1.9 | 修中文搜索二次编码 |
| 2.0 | 搜索相关度排序、番茄占位标题不覆盖、补回 Wi-Fi 行 |
| 2.1 | 修底部菜单整体画在屏幕外（点 ⋯ 没反应） |
| 2.2 | 分段条吸顶、详情页隐藏底栏、倒序先全量拉取 |
| 2.3 | 播放页队列工具条（排序/选集/多选/下载）、听完标记 |
| 2.4 | 分段条不再压简介、队列收起无残留、播放页 ⋯ 改深色面板 |
| 2.5 | 分类筛选保留精确命中 |
| 2.6 | 「有声书」改兜底分类 |
| 2.7 | 目录改分页模型（去重/补缺页/逐页重试）、缓存整本先拉全目录、播放取地址抢占修复、下载失败重试 |

---

## 7. 编译与发布

### 7.1 仓库与流水线

- 仓库：`github.com/leohenshuai/audiodown-ios`（private）
- 分支 `main`，push 自动触发 `.github/workflows/build.yml`
- 流程：macOS runner + `xcrun clang` 编成 arm64 二进制 → 组装 `Payload/ADBook.app` → `zip` 出未签名 IPA → 上传 artifact `Audiodown-IPA`

关键点：
- 必须 `mkdir -p build/Payload/ADBook.app`，否则链接器报 `ld: open() failed`
- 链接框架：`UIKit Foundation AVFoundation MediaPlayer CoreMedia CoreGraphics QuartzCore AVKit Security`
- `cp src/Assets/* build/Payload/ADBook.app/` —— **平铺到包根**，放子目录里 iOS 不认图标

### 7.2 取包

```bash
# 取最新 run → 取 artifact → 解压
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/leohenshuai/audiodown-ios/actions/runs?per_page=1"
```

Artifact 下载下来是 `Audiodown-unsigned.ipa`，重命名成 `听书-X.Y-unsigned.ipa` 放回项目目录。

### 7.3 安装

未签名包，需要用自备签名工具（TrollStore / 自签证书）重签后安装。覆盖安装保留收藏、历史、进度、下载。

---

## 8. 已知限制（都是服务端限制，不是 bug）

1. **没有分类浏览**：只有标题关键词近似分类，做不到喜马拉雅那种官方分类。
2. **服务端下载任务不可控**：只能看，不能暂停/取消/删除。
3. **番茄源首次播放慢**：要等服务端转码，可能几十秒。
4. **搜索结果重复**：同一本书在多源各返回一条（App 暂未去重）。
5. **预缓存走流量**：开了「仅 Wi-Fi」就只在 Wi-Fi 下预取。
6. **听完标记不追溯**：只从装了 2.3+ 之后、自然播完的集开始记。

---

## 9. 下一步可以做的

- 搜索结果按标题去重（保留播放量最高的那条）
- 分类词表可配置（当前写死在 `ADViews.m` 的 `catWords:`
- 播放页封面长按保存 / 分享
- 集列表显示剩余时长、批量标记已听
- 睡眠定时「播完本集后停止」
- iPad 适配（当前按 iPhone 竖屏设计）

---

## 10. 关键坑位速查

| 症状 | 原因 | 处理 |
|---|---|---|
| 中文搜不到 | URL 被二次编码 | `request:` 先 `[NSURL URLWithString:]`，失败才转义 |
| 点 ⋯ 没反应 | 自绘面板初始 y 放在屏幕外 | box 的 y 用 `屏高 - height`，靠 transform 滑入 |
| 书名变成 `album_xxx` | 番茄详情接口占位数据 | 检测前缀，不覆盖已有标题 |
| 图标不生效 | 图标被放进 `Assets/` 子目录 | workflow 里平铺到包根 |
| 倒序后首行不是最后一集 | 只反转了已加载的 50 集 | 切倒序先全量拉完再反转 |
| 目录重复 / 缺一大段 / 只出 50 集 | `cachedGET` 回调两次，页回调里直接 append+page++ | 2.7 起按页存 pageMap，网络覆盖缓存，重建去重 |
| 分段条盖住简介 | 页头高度没算分段条 | `h = 170 + introH + 12 + 48` |
| 链接报 `OBJC_CLASS_$_AVRoutePickerView` 未定义 | 没链 AVKit | 构建加 `-framework AVKit` |
| `AVURLAssetHTTPHeaderFieldsKey` 未声明 | SDK 没导出该常量 | 用字符串字面量 `@"AVURLAssetHTTPHeaderFieldsKey"` |

---

## 11. 相关文件

- 详细接口笔记与迭代记录：[PROJECT.md](PROJECT.md)
- 预览图（PIL 直绘，不是真机截图）：`preview/*.png`
- 图标源图：`icon-preview.png`，各尺寸在 `src/Assets/`
