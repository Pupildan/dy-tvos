# tvOS App 图标编译完全指南（brandassets 正确姿势）

> 来源：DYTV tvOS 项目 v195-v203 九轮攻坚实录（2026-11-17/18，v203 真机验证通过）。
> 适用：Xcode 26 / tvOS 26（actool），纯 CI 构建（无 Mac 依赖）。
> **一句话结论**：tvOS 图标必须用 brandassets 格式 + imagestack 分层结构 + 全不透明 PNG，格式错 actool 会"静默不编译"且 **CI 依然绿灯**——诊断必须三查（见 §6）。

---

## 一、最终可用目录结构（v203 实测编译通过 + 真机出图标）

```
Assets.xcassets/
└── App Icon & Top Shelf Image.brandassets/          ← 文件夹名 = tvOS 默认查找名，勿改
    ├── Contents.json                                ← 数组格式（§2.1），指向下面 4 个子资产
    ├── App Icon - App Store.imagestack/             ← App Store 图标 1280×768
    │   ├── Contents.json                            ← layers 数组（§2.2）
    │   ├── Front.imagestacklayer/
    │   │   ├── Contents.json
    │   │   └── Content.imageset/
    │   │       ├── Contents.json
    │   │       └── icon-large.png                   ← 1280×768 不透明 RGB
    │   └── Back.imagestacklayer/
    │       ├── Contents.json
    │       └── Content.imageset/
    │           ├── Contents.json
    │           └── black.png                        ← 1280×768 纯黑不透明（凑 2 层+兜底不透明）
    ├── App Icon.imagestack/                         ← 主屏图标 400×240（同上双层结构）
    │   ├── Contents.json
    │   ├── Front.imagestacklayer/
    │   │   ├── Contents.json
    │   │   └── Content.imageset/
    │   │       ├── Contents.json
    │   │       └── icon-small.png                   ← 400×240 不透明 RGB
    │   └── Back.imagestacklayer/
    │       ├── Contents.json
    │       └── Content.imageset/
    │           ├── Contents.json
    │           └── black.png                        ← 400×240 纯黑不透明
    ├── Top Shelf Image.imageset/                    ← 顶架图 1920×720
    │   ├── Contents.json
    │   └── topshelf.png
    └── Top Shelf Image Wide.imageset/               ← 顶架宽图 2320×720
        ├── Contents.json
        └── topshelf-wide.png
```

---

## 二、每个文件的逐字节模板（照抄即可）

### 2.1 brandassets 顶层 `Contents.json`（⚠️ assets 是**数组**不是对象！）

```json
{
  "assets" : [
    {
      "size" : "1280x768",
      "idiom" : "tv",
      "filename" : "App Icon - App Store.imagestack",
      "role" : "primary-app-icon"
    },
    {
      "size" : "400x240",
      "idiom" : "tv",
      "filename" : "App Icon.imagestack",
      "role" : "primary-app-icon"
    },
    {
      "size" : "2320x720",
      "idiom" : "tv",
      "filename" : "Top Shelf Image Wide.imageset",
      "role" : "top-shelf-image-wide"
    },
    {
      "size" : "1920x720",
      "idiom" : "tv",
      "filename" : "Top Shelf Image.imageset",
      "role" : "top-shelf-image"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
```

**三个 role 值**：`primary-app-icon`（可出现两次：large+small）/ `top-shelf-image`（1920×720）/ `top-shelf-image-wide`（2320×720）。

### 2.2 imagestack 的 `Contents.json`（⚠️ **至少 2 层**，单层会报错）

```json
{
  "layers" : [
    {
      "filename" : "Front.imagestacklayer"
    },
    {
      "filename" : "Back.imagestacklayer"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
```

### 2.3 层级（`.imagestacklayer`）的 `Contents.json`

```json
{
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
```

### 2.4 层内 `Content.imageset/Contents.json`

```json
{
  "images" : [
    {
      "filename" : "icon-large.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
```

### 2.5 顶架 `.imageset/Contents.json`（同 2.4 结构，换 filename）

---

## 三、图片硬性要求

| 资产 | 尺寸 | 格式要求 |
|---|---|---|
| App Store 图标 | **1280×768** | **完全不透明 RGB**（imagestack Front） |
| 主屏图标 | **400×240** | **完全不透明 RGB**（imagestack Front） |
| 顶架图 | **1920×720** | 完全不透明（有 alpha 只 warning 但建议压平） |
| 顶架宽图 | **2320×720** | 完全不透明 |
| Back 层黑底 | 与 Front 同尺寸 | 纯色不透明 |

**⚠️ 透明度是隐形杀手**：RGBA PNG 背景/边角哪怕半透明（实测 alpha=84/139 都被拒）都会报
`The last image stack layer with content, "Front", must be a fully opaque bitmap`。

**压平脚本**（PIL，合成到黑底转 RGB）：

```python
from PIL import Image
im = Image.open('icon.png').convert('RGBA')
bg = Image.new('RGBA', im.size, (0, 0, 0, 255))
flat = Image.alpha_composite(bg, im).convert('RGB')   # RGB 无 alpha
flat.save('icon.png')
```

---

## 四、构建设置

**不需要**设置 `ASSETCATALOG_COMPILER_APPICON_NAME`：
- tvOS 构建系统默认查找名就是 **"App Icon & Top Shelf Image"**（CI 日志 actool 参数 `--app-icon App\ Icon\ \&\ Top\ Shelf\ Image` 实锤）
- 文件夹名 `App Icon & Top Shelf Image.brandassets` 的集合名正好匹配 → 自动识别

如果非要自定义文件夹名（如 `AppIcon.brandassets`），则必须设：
```yaml
ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon   # 值 = 文件夹名去掉 .brandassets
```
且名字必须逐字符匹配，否则 `None of the input catalogs contained a matching...` → 整个 catalog 静默不编译。

⚠️ **标准 iOS appiconset（1024×1024 单尺寸）在 tvOS 不被认**——报 `The app icon set "AppIcon" has an unassigned child`。tvOS 必须走 brandassets。

---

## 五、九轮弯路实录（别再踩）

| 轮次 | 尝试 | 结果 |
|---|---|---|
| v195 | 删 top-shelf 槽位只留图标 | ❌ 集合不完整（四槽位要齐全），静默不产出 |
| v196 | — | （CI 其他错） |
| v197 | 同 v195 配置，首次出完整 ipa | ❌ 拆包无 Assets.car（格式根本不对） |
| v198 | 换标准 iOS appiconset | ❌ tvOS 不认 `unassigned child` |
| v199 | brandassets + 删 ASSETCATALOG 设置 | ❌ 格式仍错 + 名字回退默认对不上 |
| v200 | 修 top-shelf-square 尺寸 1280×1280 | ❌ 格式仍是手写对象式 |
| v201 | 恢复 ASSETCATALOG=AppIcon | ❌ 格式仍错 |
| v202 | **官方模板格式重建** | ⚠️ Assets.car 出现但图标被丢弃——**actool document errors 不 fail CI**！ |
| **v203** | **+ 不透明压平 + imagestack 双层** | ✅ **CI 零错误 + Assets.car + 真机出图标** |

**v202 的教训最值钱**：`Assets.car 存在` + `Info.plist 有 CFBundleIcons` ≠ 图标可用。actool 的 document error（alpha 不透明、层数不足）只把图标内容丢弃，构建照样绿。

---

## 六、诊断三查（CI 绿 ≠ 图标好）

1. **查 CI 日志 actool 段**（`_tools/dy_fetch_errors.ps1 -RunId <id>` 后 grep）：
   - `com.apple.actool.document.errors` → 内容级错误（alpha/层数/尺寸），**构建不失败但图标被丢**
   - `None of the input catalogs contained a matching ... named "XXX"` → 格式/名字不匹配（XXX 就是它要找的集合名）
   - `has an unassigned child` → 用了 iOS appiconset 格式，tvOS 不认
2. **拆 ipa**（python zipfile）：
   - `Payload/*.app/Assets.car` 在不在
   - `Info.plist` 二进制里搜 `CFBundleIcons` / `CFBundlePrimaryIcon`（plistlib 解析看值）
   - 反例特征：13 条目无 Assets.car + 无图标键 = catalog 压根没编译
3. **PIL 验所有 PNG 不透明**：`Image.open(p).mode == 'RGB'`（RGBA 一律压平）

---

## 七、一行速查

> tvOS 图标 = `App Icon & Top Shelf Image.brandassets`（模板名）+ 数格式 Contents.json（role/size）+ 图标 `.imagestack`（≥2 层，Front 图标 + Back 纯黑）+ 顶架 `.imageset`（1920×720 / 2320×720）+ **全 PNG 不透明 RGB** + 不设 ASSETCATALOG（用默认名）+ 诊断三查（CI actool errors / 拆 ipa / PIL 验 alpha）。

完整可抄目录：本仓库 `App/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets/`（v203 已真机验证）。

参考：
- [Apple Asset Catalog Format Reference — Brand Assets Type](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/BrandAssetsType.html)
- [react-native-vanilla tvOS 模板（已上架应用）](https://github.com/invertase/react-native-vanilla/tree/master/platforms/tvos/ReactNativeVanillaTVOS/Assets.xcassets/App%20Icon%20%26%20Top%20Shelf%20Image.brandassets)
- [Stack Overflow: tvOS app icon not displaying](https://stackoverflow.com/questions/79288669/)
- [Apple HIG: tvOS icons](https://developer.apple.com/design/human-interface-guidelines/tvos)
