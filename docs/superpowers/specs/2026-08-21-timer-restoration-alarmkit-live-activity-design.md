# 倒计时恢复与 AlarmKit 灵动岛设计

日期：2026-08-21

## 背景

当前计时器把运行状态保存在 `TimerView` 的瞬时 SwiftUI 状态中，同时把提醒交给 AlarmKit。用户从多任务界面结束 App 后，页面状态随进程消失，但系统调度的 AlarmKit 闹钟仍然存在。再次打开 App 时，界面因此回到未计时状态，而系统仍会在原定时间响铃。

项目当前使用固定日期的普通 AlarmKit 闹钟模拟计时器，也没有包含 Widget Extension。因此无法恢复完整的计时器生命周期，也没有承载 AlarmKit 倒计时 Live Activity 的自定义界面。

## 目标

- App 被系统终止、用户划掉或重新启动后，仍能恢复正在运行或暂停的倒计时。
- App 内状态、AlarmKit 系统状态和灵动岛展示使用同一个计时器身份与生命周期。
- 取消或重置倒计时后，系统不再出现延迟响铃。
- 为计时器以及闹钟的临近、贪睡和响铃阶段提供锤子时钟风格的锁屏与灵动岛界面。
- 普通的未来闹钟不长期占用灵动岛。
- 常规验证由自动化测试和模拟器完成，最后再安装到已连接的 iPhone。

## 非目标

- 不让所有已设置的普通闹钟持续显示在灵动岛。
- 不建立服务器推送或远程 Live Activity 更新服务。
- 不重做计时器主页面现有的尺子交互与钟面动画。
- 不把 ActivityKit 建成与 AlarmKit 并行运行的第二套倒计时系统。

## 方案选择

采用 AlarmKit 作为系统侧唯一计时源，本地持久化只保存恢复界面所需的会话信息，并使用 AlarmKit 的 `AlarmAttributes` 在 Widget Extension 中绘制 Live Activity。

未采用的方案：

- 只保存本地状态：可以恢复 App 页面，但不能完成自定义灵动岛，也难以核对系统闹钟是否仍然存在。
- 自建 ActivityKit 加本地通知：视觉自由度高，但强制退出后的提醒可靠性与系统闹钟能力不如 AlarmKit，并会产生两套生命周期。

## 状态模型

新增可编码的 `TimerSession`，至少包含：

- `alarmID: UUID`
- `originalDuration: TimeInterval`
- `startedAt: Date`
- `fireDate: Date`
- `status: running | paused`
- `pausedRemaining: TimeInterval?`
- `updatedAt: Date`
- `schemaVersion: Int`

新增 `TimerSessionStore`，负责原子地读取、写入和删除单一活动计时器会话。第一版使用应用自己的 `UserDefaults` 即可；Widget Extension 的展示数据由 AlarmKit 的 Activity 上下文提供，不依赖共享容器。

新增主线程隔离的 `TimerCoordinator`，作为 `TimerView` 的状态来源。页面不再直接持有 AlarmKit ID、结束时间和运行状态等核心生命周期数据。

## AlarmKit 生命周期

### 开始

1. 生成新的 `alarmID` 和会话数据，并以 `pending` 的内部事务状态暂存。
2. 使用 `AlarmManager.AlarmConfiguration.timer(duration:attributes:...)` 调度真正的 AlarmKit 计时器。
3. 调度成功后，将会话提交为 `running`；失败则回滚本地记录并向页面报告错误。

### 暂停与继续

- 暂停调用 AlarmKit `pause(id:)`，记录当时剩余时间并把会话改为 `paused`。
- 继续调用 `resume(id:)`，依据当前时间重建 `fireDate` 并提交 `running` 状态。
- 任一步骤失败时，重新读取 `AlarmManager.alarms`，以系统实际状态修正本地会话。

### 停止、重置与完成

- 停止或重置先请求 AlarmKit 取消对应 ID，确认系统不再包含它后清理会话。
- 倒计时结束或 AlarmKit 不再返回对应 ID 时，清理本地活动会话并恢复初始页面。
- 所有路径复用同一套协调器操作，避免某个按钮只清理页面、不清理系统闹钟。

## 启动恢复与状态核对

App 启动以及 `scenePhase` 回到 active 时执行核对：

1. 读取本地 `TimerSession`。
2. 读取 `AlarmManager.alarms`。
3. 本地 ID 在系统中存在：根据 AlarmKit 的 `scheduled/countdown/paused/alerting` 状态和本地时间数据恢复页面。
4. 本地 ID 不在系统中：删除过期会话并显示未计时状态。
5. 系统存在固定时间或倒计时类型的历史条目，但本地没有记录：将它与普通周期闹钟 ID 集合区分；只恢复一个仍有效的计时器，其余重复条目安全取消。
6. `fireDate` 已过但 AlarmKit 仍在 alerting：页面显示已完成状态，不创建新的倒计时。

剩余时间始终由绝对 `fireDate - now` 推导，不通过每次渲染递减一个本地整数，避免进后台后的时间漂移。

## AlarmKit 元数据

扩展 `ClockAlarmMetadata`，加入可编码的类型标识：

- `kind: timer | alarm`
- `label`
- 可选的原始时长或视觉样式版本

App 与 Widget Extension 共享该模型。普通闹钟继续使用相对时间计划；计时器改为 AlarmKit timer 配置。

## Widget Extension 与灵动岛

新增仅承载 Live Activity 的 Widget Extension，并在主应用启用 `NSSupportsLiveActivities`。配置类型使用：

`ActivityConfiguration(for: AlarmAttributes<ClockAlarmMetadata>.self)`

界面依据 `AlarmPresentationState.Mode` 渲染 countdown、paused 与 alert 等状态。

### 紧凑形态

- 左侧：小型白色机械钟面、深灰指针、红色轴心。
- 右侧：使用系统计时文本显示剩余时间，锤子红作为强调色。
- 在系统黑色岛体上保持高对比，不使用大面积白色底板。

### 最小形态

- 白色圆环、红色中心点和短灰色指针，确保多个 Live Activity 并存时仍可识别。

### 展开形态

- 左侧或中心显示简化机械钟面。
- 显示“计时器”或闹钟标签及较大的剩余时间。
- countdown 状态提供暂停与停止；paused 状态提供继续与停止。
- 视觉延续白、灰、红配色，阴影与高光保持克制，以适应灵动岛小尺寸。

### 锁屏与 StandBy

- 使用横向白色机械表盘卡片。
- 中部显示锤子红倒计时，辅助文字使用中性灰。
- 普通未来闹钟不启用持续 pre-alert，因此不会长期占用灵动岛；贪睡倒计时和正在响铃阶段由 AlarmKit 系统生命周期驱动。

## 错误处理

- AlarmKit 未授权：保留用户选定时长，明确提示授权失败，不伪装成正在计时。
- Live Activity 被用户禁用：AlarmKit 提醒仍可工作，App 页面继续恢复，灵动岛作为可选展示降级。
- 持久化数据损坏或版本不兼容：删除无效记录，并核对系统 AlarmKit 条目后安全恢复或清理。
- Widget Extension 加载失败：不得影响系统提醒和 App 内计时器。
- 取消失败：页面不得立即假装完全重置；先核对系统状态，再给出可重试的错误反馈。

## 测试策略

### 单元测试

- running 会话在结束时间之前正确恢复。
- paused 会话恢复固定剩余时间。
- 过期、缺失或损坏会话被清理。
- AlarmKit ID 不存在时不显示幽灵倒计时。
- 开始失败会回滚，取消成功会清理，取消失败会保留可核对状态。
- 普通闹钟 ID 不会被历史计时器迁移逻辑误删。

### 集成与界面测试

- 设置倒计时，终止 App 进程，重新启动后显示同一倒计时及正确剩余时间。
- App 在后台经过一段时间后，钟面和文本依据绝对时间同步恢复。
- 重置后终止并重启，不再恢复且不会响铃。
- 检查灵动岛 compact、minimal、expanded 以及锁屏视图的 countdown、paused、alert 状态。
- 在不支持灵动岛或关闭 Live Activities 的场景下验证降级行为。

### 交付验证

- 运行已有计时器尺子测试及新增状态测试。
- 使用 iOS 26 模拟器完成进程终止和重启恢复测试。
- 构建主应用与 Widget Extension，检查签名、嵌入和 Info.plist 配置。
- 模拟器验证通过后，再安装到已连接的 iPhone 并检查 AlarmKit 授权及灵动岛实际展示。

## 迁移与兼容

- 第一次启动新版本时执行一次历史 AlarmKit 条目核对。
- 现有普通闹钟的数据模型和 ID 保持不变。
- 新的 `TimerSession` 带版本号，后续字段变化可以迁移而不是直接丢弃。
- 保留当前计时器 UI 和尺子交互，只替换其状态来源与系统调度方式。
