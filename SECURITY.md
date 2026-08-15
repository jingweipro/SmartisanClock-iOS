# 安全说明

## 获取可信构建

- 优先从本仓库的 GitHub Releases 下载 IPA。
- 下载后核对 Release 页面提供的 SHA-256。
- 未签名 IPA 必须重新签名；最终安装包的签名者对该构建负责。
- 不要向来历不明的网站提交 Apple Account 密码、双重验证码、开发证书或私钥。
- 所谓“永久签名”“共享企业证书”可能被撤销，也可能在安装包中注入额外代码。

## 报告安全问题

请优先使用仓库的 [GitHub Security Advisories](https://github.com/jingweipro/SmartisanClock-iOS/security/advisories/new) 私下报告可被利用的安全问题。普通功能问题可以使用 GitHub Issues。

报告中请包含受影响版本、iOS 版本、复现步骤和可能影响。不要在公开 Issue 中发布 Apple Account、设备 UDID、证书、描述文件或其他敏感信息。

## 闹钟可靠性边界

本项目不是安全关键系统。签名过期、权限被撤销、系统测试版缺陷、设备关机、音量设置或系统行为变化都可能影响提醒。请勿将其作为医疗、消防、出行、考试或生产值守的唯一提醒方式。
