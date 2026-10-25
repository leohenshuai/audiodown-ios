# 听书 iOS 客户端(音频来自 AudioDown 服务)

## 形态
- 原生 Objective-C + UIKit(界面风格复刻「听见有声」),纯代码布局,无 Swift / 无 Storyboard
- 仓库:https://github.com/leohenshuai/audiodown-ios(私有),推 main 自动编译
- 编译:GitHub Actions `Build AudioDown`(macos-14,xcrun clang)
- 产物:未签名 IPA,bundle id `com.leo.audiodown`
- 源码:`src/AD.h`(声明)、`ADCore.m`(配置/模型/存储/工具)、`ADApi.m`(网络)、`ADPlayer.m`(播放器)、`ADViews.m`(首页/搜索/书架/卡片/迷你条)、`ADDetail.m`(专辑页/播放器页/设置)、`main.m`

## 界面(按「听见有声 1.4.5」截图复刻)
- 首页:大标题「听见 AudioDown」+ 右上两个圆形按钮;继续收听横向大卡(封面/第N集/书名/章节/主播·剩余集数/播放胶囊+进度+时长+···);推荐内容浅色面板(两列横滑);其后是各接口板块横滑
- 搜索 / 书架:深色底 + 三列封面
- 标签栏:iOS 26 原生悬浮玻璃;迷你播放条按 `safeAreaInsets.bottom` 定位,不会压住标签栏
- 专辑页、播放器页:封面 + 章节列表 + 倍速/定时/章节切换

## 服务端接口(已实测)
Base:`https://audio.959935291.xyz:899`,认证 `Authorization: Bearer <token>`(`xmd_29f7…` 带下划线)

| 用途 | 方法 路径 |
|---|---|
| 发现页 | GET `/open-api/v1/discover`(`sections[].items[]`) |
| 分类 | GET `/open-api/v1/categories`(无按分类取专辑的接口) |
| 搜索 | GET `/open-api/v1/search?q=&page=&pageSize=` |
| 专辑详情 | GET `/open-api/v1/albums/{albumId}` |
| 章节列表 | GET `/open-api/v1/albums/{albumId}/tracks?page=&pageSize=` |
| 播放地址 | POST `/open-api/v1/cdn/play` body `{trackId,provider,albumId}` → `url` + `headers`;番茄源 `downloadPending` 需轮询 |
| 下载任务 | GET `/open-api/v1/downloads`(只读,没有停止接口) |

## 已知坑
- `/api/*` 只认网页会话 cookie,不认 token
- token 下划线丢了会报 `OPEN_API_TOKEN_INVALID`
- 播放必须带 `/cdn/play` 返回的 headers(AVURLAsset 用 `AVURLAssetHTTPHeaderFieldsKey`)
- 开放 API 没有进度同步接口,进度只存本地(Documents 下归档)
- `POST /open-api/v1/downloads` 会真的在服务端排队下载,调试时别碰

## 下载
- **本机下载**(自己实现,`ADDownloader.m`):专辑页「缓存到本机」→ 逐集调 cdn/play 取地址→带 headers 下载到 `Documents/audio/<trackId>.m4a`;设置页可查看进度、点击暂停/继续、左滑删除、全部暂停/继续;已缓存的集直接本地播放
- **服务端下载任务**:开放 API 只有 `GET /open-api/v1/downloads` 与 `/downloads/{id}`,实测 POST/DELETE/PATCH `/downloads/{id}/stop|cancel|pause|resume` 全部 404,无法从客户端控制,只能去网页后台操作

## 版本记录
- v1.0(2026-10-24):首页/搜索/书架/专辑/播放器/设置全部完成;本机下载;本地 JSON 缓存;下拉刷新;token 遮罩;播放页按「听见有声」1:1 重排(封面 min(宽-24,高52%),间隙 ≤22,控制行与底部工具行固定 18)
- v1.1(2026-10-24):播放控件缩小,底部四键对齐(倍速菜单/定时菜单/AirPlay 路由/章节),首页右上两键接上历史与本机下载,继续收听卡片与播放页「···」菜单化
- v1.2(2026-10-24):设置改模态弹出(书架的设置不再赖在 tab 栈里)、封面落盘缓存 Documents/cache/covers、删除"当前离线"提示、定时支持自定义(20 / 1h30m / 90s)、无封面时显示书名首字占位
- v1.3(2026-10-24):章节面板加遮罩,点面板外任意位置收起(不只是再点 ☰)
- v1.4(2026-10-24):倍速/定时改成自绘底部面板(不再用系统 UIAlertController,避免浮在中间偏上);定时菜单加「取消定时关闭」;专辑目录失败自动重试 2 次 + 底部「点这里重试」;新增 App 图标(src/Assets,workflow 平铺到包根)
- v1.5(2026-10-25):搜索页加分类胶囊(本地关键词过滤,服务端不支持分类过滤)
- v1.6(2026-10-25):搜索页加在线/本地分段,本地搜下载/收藏/历史(包含匹配)
- v1.7(2026-10-25):专辑页支持单集下载(左滑)、多选下载(⋯→选择剧集)、目录正序倒序、每 60 集快速选集;智能预加载(预取后续 N 集到 Documents/cache/prefetch)
- v1.8(2026-10-25):预加载加「仅 Wi-Fi」开关(默认开,检测 en0),清理策略 不清理/3/7/30 天
- v1.9(2026-10-25):修搜索中文二次编码(关键词先在 search() 严格转义、request() 不再整条 URL 再转义);结果按"标题含关键词"优先排序。踩坑:同一 URL 既在 search() 里转义又在 request() 里转义,`%` 变 `%25`,服务器按字面量匹配→永远搜不到
- v2.0(2026-10-25):搜索排序改"去空格标点归一化"后比较(完整命中优先,其次按命中词数);番茄源详情接口返回 album_xxx 占位标题/空封面时不覆盖搜索结果;设置补回「仅 Wi-Fi 预加载」行(上一版行号错位出现空行)
- v2.1(2026-10-25):修自绘底部菜单面板初始 y=屏高导致整体在屏幕外(点⋯/倍速/定时都没反应);快速选集在倒序下跳转位置修正
- v2.2(2026-10-25):分段条吸顶(浮动副本+滚动切换)、专辑页 hidesBottomBarWhenPushed、倒序先全量拉取再反转、播放页 ⋯ 可跳专辑
- v2.3(2026-10-25):播放页队列加工具条(正序/倒序、选集、多选、缓存整本/缓存所选);听完标记(ADStore done.dat/donealbums.dat,自然播完才记),专辑列表/队列显示 ✓,书架显示「已听完」角标
- 产物:`听书-2.3-unsigned.ipa`(bundle com.leo.audiodown,最新)

## 待办
- 分类浏览(需服务端支持)
- 离线下载
- App 图标/启动图
- 与「听见有声」逐屏对齐(截图还不够,需要其余页面截图)
