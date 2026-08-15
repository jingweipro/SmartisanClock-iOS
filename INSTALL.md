# 安装与自签说明

## 先说明：IPA 不能直接安装

GitHub Release 提供的是未签名 IPA。iOS 要求 App 具有与你的设备和 Apple Account 匹配的有效签名与描述文件，因此下载后直接点击 IPA 不会完成安装。

本项目不提供企业证书、共享证书、付费签名或远程代签服务。推荐使用自己的 Apple Account，并只从工具的官方网站下载软件。

## 方法一：使用 Xcode（最透明）

1. 从 GitHub 下载源码或执行：

   ```bash
   git clone https://github.com/jingweipro/SmartisanClock-iOS.git
   ```

2. 使用 Xcode 26.2 或更高版本打开 `SmartisanClockiOS.xcodeproj`。
3. 在 Xcode > Settings > Accounts 登录自己的 Apple Account。
4. 在 Target > Signing & Capabilities 中选择自己的 Team，并设置一个唯一的 Bundle Identifier。
5. 用数据线连接并信任 iPhone，在手机中开启开发者模式。
6. 选择手机为运行设备并点击 Run。

Apple 官方步骤见：[Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)。

## 方法二：使用 AltStore Classic 导入 IPA

1. 按 [AltStore 官方文档](https://faq.altstore.io/) 安装 AltStore Classic 和 AltServer。
2. 下载本项目 Release 中名称含 `unsigned.ipa` 的文件。
3. 在 AltStore 的 **My Apps** 页面使用左上角 `+` 选择 IPA。
4. 等待 AltStore 使用你的 Apple Account 完成签名和安装。
5. iOS 16 及以上需要开启开发者模式。

AltStore 与本项目互不隶属。其安装、账号处理和刷新机制以 AltStore 官方说明为准。

## Personal Team 的限制

Apple 官方说明：未加入付费开发者计划的 Personal Team 可以在个人设备上测试 App，但描述文件通常自签发起 7 天后过期；每台设备最多同时安装 3 个此类 App，并存在 App ID 和设备数量限制。过期后需要重新构建或重新签名安装。

参考：[Apple Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)。

## 安装后检查

- 确认系统版本为 iOS 26.0 或更高。
- 首次创建闹钟时允许 AlarmKit 权限。
- 先创建一个几分钟后的测试闹钟，验证锁屏、音量和系统权限。
- 不要把本项目作为唯一的关键提醒工具。

## 常见问题

### “无法验证 App”或 App 一打开就退出

通常表示签名、描述文件或开发者模式有问题，也可能是免费签名已过期。重新签名安装，并确认手机能连接 Apple 的验证服务。

### 安装时提示 Bundle Identifier 冲突

在 Xcode 中把 `PRODUCT_BUNDLE_IDENTIFIER` 改成自己的唯一值，或让签名工具自动生成新的标识符。

### 更新会不会丢数据

使用相同 Bundle Identifier 和兼容签名覆盖安装时通常会保留数据；删除 App、改变 Bundle Identifier 或某些第三方工具的重签策略可能导致数据无法继承。更新前请自行评估。
