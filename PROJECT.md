# 听书 iOS 客户端(音频来自 AudioDown 服务)

## 形态
- 原生 Objective-C + UIKit,字体系统,纯代码布局,无 Swift / 无 Storyboard
- 仓库:https://github.com/leohenshuai/audiodown-ios(私有)
- 编译:GitHub Actions `Build AudioDown`(macos-14,xcrun clang 直接编,不走 Xcode 工程)
- 产物:未签名 IPA(`Audiodown-unsigned.ipa`),bundle id `com.leo.audiodown`
- 源码:`src/AD.h`(接口声明)、`ADCore.m`(配置/模型/存储/工具)、`ADApi.m`(网络)、`ADPlayer.m`(播放器)、`ADViews.m`(发现/搜索/书架/迷你条)、`ADDetail.m`(专辑/播放器页/设置)、`main.m`

## 服务端接口(已实测)
Base:`https://audio.959935291.xyz:899`
认证:`Authorization: Bearer <token>`(token 形如 `xmd_29f7…`)

| 用途 | 方法 路径 | 说明 |
|---|---|---|
| 发现页 | GET `/open-api/v1/discover` | `sections[].{title,items[]}`,item 含 albumId/cover/title/anchorName/trackCount |
| 分类 | GET `/open-api/v1/categories` | 只有分类树,**没有**按分类取专辑的开放接口 |
| 搜索 | GET `/open-api/v1/search?q=&page=&pageSize=` | `data.items[]` |
| 专辑详情 | GET `/open-api/v1/albums/{albumId}` | `data` |
| 章节列表 | GET `/open-api/v1/albums/{albumId}/tracks?page=&pageSize=` | `items[]` + `total`,分页 |
| **取播放地址** | POST `/open-api/v1/cdn/play` | body `{trackId,provider,albumId}`;返回 `url` + `headers`(Cookie/Referer/UA);番茄源返回本地代理流,`downloadPending=true` 需轮询直到就绪 |
| 下载任务 | GET `/open-api/v1/downloads`、`/downloads/{id}` | 服务端下载队列,只读(无停止接口) |

albumId 前缀:`XMID…`(喜马拉雅)、`FQID…`(番茄)。

## 已知坑
- `/api/*` 全部要网页会话 cookie,token 无效;只有 `/open-api/v1/*` 认 token。
- 环境变量里存 token 时**下划线容易丢**:正确是 `xmd_29f7…`,存成 `xmd29f7…` 会报 `OPEN_API_TOKEN_INVALID`。
- 开放 API 没有进度同步接口,进度只存本地(UserDefaults 归档到 Documents)。
- 没有停止下载任务的接口,别在调试时随手 POST `/open-api/v1/downloads`(会真的开始下载)。
- 播放必须带上 `/cdn/play` 返回的 `headers`,否则部分源 403(xm 的直接 CDN 偶尔不校验,别赌)。

## 待办
- 分类浏览(需服务端开放 `/open-api/v1/categories/{id}/albums`)
- 离线下载(可基于 `/cdn/play` 的直链做本地缓存)
- 跨设备进度同步(需服务端接口)
- 图标/启动图还是空白
