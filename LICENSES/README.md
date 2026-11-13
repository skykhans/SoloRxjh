# 引擎、依赖与资源许可

更新日期：2026-11-13。Godot目标版与现有Rust版的依赖清单分开核对，不能把旧crate数量当作新游戏的运行依赖。

## Godot目标版

Godot4.7.2引擎使用MIT许可，正式发行时携带引擎许可和对应版本第三方声明；新增插件逐项记录版本、来源和许可。当前尚未导出Godot包，不提前宣称新依赖清单检查通过。

原创模型/音频及其他资产见[资源来源](../assets/README.md)；Noto字体随包携带[OFL](../assets/fonts/OFL.txt)。官网机制参考和小说事实摘要不等于取得其商业素材或改编授权；项目使用自行制作资源。

## 现有Rust历史材料

当前supplemental目录仍服务于未替换的Rust构建。旧工具通过Cargo的Windows依赖图收集LICENSE/COPYING/NOTICE，补充文件按准确包名/版本、URL、上游提交及SHA256核对，不能自动改选未知许可。

AccessKit等依赖的工作区许可、Chromium通知、encase工作区MIT-0、constgebra0.1.4的Apache-2.0选用、hexf-parse0.2.1的CC0正文继续按已有source.json维护；法律正文和来源记录不因本次文档整理删除。Godot迁移验证后，发行工具按实际引擎和运行资源重新生成清单。
