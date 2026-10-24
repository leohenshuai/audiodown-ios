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

## 待办
- 分类浏览(需服务端支持)
- 离线下载
- App 图标/启动图
- 与「听见有声」逐屏对齐(截图还不够,需要其余页面截图)
