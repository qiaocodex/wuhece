# 物盒册 · 个人物品资产与收纳空间管理

> 原项目名「归物」，因重名已于 2026-11 更名为「物盒册」；
> 包名（`guiwu`）、存储键（`guiwu.data.v2`）与备份标识为兼容性内部标识，保持不变。

由 Web 单页版（`D:\traeproject\zichanguanli`）重构而来的 **Flutter 四端应用**：

- 📱 Android / iOS（`flutter run` / Android Studio）
- 🌐 Web（`flutter run -d chrome`）
- 🖥️ Windows / macOS（VS 2022 / Xcode 工具链）

数据完全离线保存在本机，不上传服务器。现有功能详见 [docs/FEATURES.md](docs/FEATURES.md)。

## 运行

```bash
flutter pub get
flutter run -d windows        # Windows 桌面
flutter run -d chrome         # Web
flutter run                   # Android（设备/模拟器）
flutter test                  # 单元测试
flutter build web             # Web 发布包 → build/web
flutter build apk             # Android APK
flutter build windows         # Windows 可执行程序 → build/windows/x64/runner/Release
```

> 国内环境已配置镜像：`PUB_HOSTED_URL=pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=storage.flutter-io.cn`；
> Android gradle wrapper 已指向华为云镜像（`android/gradle/wrapper/gradle-wrapper.properties`）。

## 架构

```
lib/
├── main.dart                  # 入口：持久化初始化、发布包异常可视化
├── app.dart                   # MaterialApp、中文本地化、主题
├── models/models.dart         # Item / Space / Category / AppSettings
│                              #   字段与 Web 版 guiwu.data.v2 JSON Schema 一致
├── store/
│   ├── app_store.dart         # ChangeNotifier：增删改查 + 统计 + 整理建议引擎
│   └── seed_data.dart         # 示例数据（与 Web 版一致）
├── services/
│   ├── image_service.dart     # 选图 + 统一压缩管线（≤900px JPEG72 → dataURL）
│   ├── file_io.dart           # 导入导出平台适配（条件导出：native / web）
│   ├── csv.dart               # CSV 解析 / 生成 / 导入映射（列别名兼容 Web 版）
│   ├── dates.dart / format.dart / id.dart
└── ui/
    ├── theme.dart             # 暖纸色设计系统（#F5F2ED / #2E6B5E）
    ├── widgets.dart           # 卡片 / 环形图 / 进度条 / 徽章 / 响应式弹层
    ├── shell.dart             # 自适应外壳：宽屏侧栏 ↔ 窄屏底部导航
    └── pages/                 # 总览 / 物品库 / 空间 / 整理建议 / 数据分析 / 设置
```

**状态管理**：零第三方依赖，`AppStore extends ChangeNotifier` + `ListenableBuilder`。

**持久化**：`shared_preferences`（键 `guiwu.data.v2`），JSON 结构与 Web 版完全一致 ——
**Web 版导出的 JSON 备份可直接导入本应用，反之亦然。**

## 版本迭代与发布流程

1. **改代码** → 跑 `flutter analyze && flutter test`（推送后 CI 也会自动跑）
2. **升版本**：`pubspec.yaml` 的 `version: 1.1.0+2`（+号后是构建号，每次发布 +1）
3. **写说明**：在 `CHANGELOG.md` 顶部按格式加一节 `## [1.1.0] - 2026-XX-XX`
4. **提交并打标签**：
   ```bash
   git add -A && git commit -m "feat: xxx"
   git tag v1.1.0
   git push origin main v1.1.0
   ```
5. **自动发布**：GitHub Actions 会校验标签与 pubspec 版本一致，三平台并行构建
   （Android APK / Web zip / Windows zip），并从 `CHANGELOG.md` 提取对应段落
   自动创建 GitHub Release 并附加构建产物（版本说明与下载包全自动，无需手动填）。

CI（`ci.yml`）在每次推送 main / PR 时自动运行 analyze + test；
Release（`release.yml`）在推送 `v*` 标签时自动三平台构建并发布。
macOS 产物因需签名公证暂不在流水线内，可本地 `flutter build macos`。

## 平台能力矩阵

| 能力 | Android | iOS | Web | Windows | macOS |
|---|---|---|---|---|---|
| 本地存储 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 拍照 / 相册选图 | ✅ | ✅ | ✅（相册） | 文件选择 | 文件选择 |
| 图片压缩 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 导出 JSON / CSV | 系统分享 | 系统分享 | 另存为下载 | 另存为对话框 | 另存为对话框 |
| 导入 JSON / CSV | ❌* | ✅ | ✅ | ✅ | ✅ |
| WebDAV 云同步（坚果云/NAS） | ✅ | ✅ | ✅ | ✅ | ✅ |
| 深色模式 / 标签管理 / 图片墙 | ✅ | ✅ | ✅ | ✅ | ✅ |

\* `file_selector` 尚不支持 Android，手机端导入请在 Web / 桌面端完成（界面有提示）。

## 待办（后续版本）

- [x] Android 设置页空白问题（已解决，2026-11-21 验收）
- [ ] Android / iOS 真机全面回归
- [ ] Web 版 localStorage 数据一键迁移引导（粘贴 JSON 即导入）
- [ ] 多设备同步（WebDAV / 云盘）
- [ ] iOS / macOS 真机与签名配置、macOS Release 产物
- [ ] 深色模式、国际化
