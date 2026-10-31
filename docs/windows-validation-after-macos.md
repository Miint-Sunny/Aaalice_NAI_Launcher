# Mac 适配与后续 PR 的 Windows 验证

这些工作需要 Windows 真机 / runner；本轮没有在 Mac 生成或覆盖 Windows PNG。

## 省电与统计 PR

`stats_anlasNote` 由余额差记账说明改为按请求报价，实际由 `statistics_cards.dart` 的 Anlas 卡绘制。`statistics_golden_test.dart` 的以下 9 张场景使用完整数据：main、main-dark、r30、narrow、narrow-dark、narrow-en、narrow-ja、narrow-ko、min-window。loading、empty-dark、error 不作为确定受影响的完整统计卡场景。

空闲微动从开关变为三档，并改了 `set_cvMotionSub`、`channel_motionSub` 与三个选项标签。还需核对：

- 设置画布页 `test/presentation/ui/settings/goldens/settings-canvas.png`，尤其滚动后微动行及窄窗长文案；默认截图是否包含该行以实际绘制结果为准。
- 显示弹层 `test/presentation/ui/channel/goldens/v2/popover.png`、`popover-dark.png`、`popover-fixed.png`。
- 旧 `channel/goldens/*.png` 对整个显示弹层已有排除区域，不能为此改写被锁定的旧基准；v2 是新弹层的完整基准。

先运行相关 golden 测试查看差异，再由维护者确认更新。统计页可用普通 `--update-goldens`；channel 只针对允许重录的 v2 弹层场景，不扩大旧图排除区域。

## 生成错误 PR

新增文案的调用链是 `generation_error_view.dart` → 画布接线 / 探索映射 / Agent 提示词组卡。现有生成页 failed golden 使用 `GenFixture.failed()` 的固定标题和说明，探索 failed golden 使用 `ExploreFixture` 的固定错误文本，未走新错误映射；它们不能证明新的服务端详情与处理指引已被截图覆盖，也没有据此判定需要自动重录的额外旧 PNG。

请人工检查：429 停止卡、400 参数错误、随机/顺序块跳过次数且无重试、窄窗长英文、深浅色、探索的“重试失败的候选”、组卡提示通过 Agent 修改词。组件回归和本地假接口验证不等于运行中用户窗口截图。

## 原生行为

验证托盘右键、退出开始后的再次显示、最小化、从任务栏还原、隐藏时暂停绘制和回到前台恢复。Windows 没有完全遮挡检测，这不是预期支持的场景。

## 既有问题

上游已有未引用的 updateCapsuleLabel 文案、写死 E:/node/node.exe 的测试入口、online_backend 缓存数据库工厂未设置等问题需要独立处理；本 PR 不通过跳过失败或改写旧 golden 来掩盖它们。
