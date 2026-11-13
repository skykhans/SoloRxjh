# 资源来源索引

更新日期：2026-11-13。现有资源来自旧Rust版本，作为Godot迁移基础保留；新引擎导入与最终美术尚未验收。资源与现代界面规范统一见[资源与交互](../docs/04-资源与交互.md)。

| 目录 | 来源 | 维护方式 |
| --- | --- | --- |
| `models/characters/*.glb`、`characters.blend` | 本项目原创角色、野兽、竹、骨架与动画 | `tools/export_game_models.py`，Blender4.5.15LTS |
| `audio/*.wav` | 本项目原创标准库波形合成，无第三方录音/采样 | `tools/generate_audio.py` |
| `fonts/NotoSansCJKsc-Regular.otf` | Adobe/Google Noto CJK | [字体来源与哈希](fonts/README.md)、[SIL OFL1.1](fonts/OFL.txt) |
| `models/probes/` | 本项目原创坐标/骨骼测试资产 | [探针说明](models/probes/README.md)，不进入发行包 |
| `config/*.ron` | 现有实现的游戏设计数据 | 后续一次性迁移JSON；目前未改动 |

旧场景建筑、围栏、工具架、桥和岩石由`src/world.rs`生成；Godot场景实现待迁移。已有6正式GLB、方尘14动画与11WAV不等于目标版八职业、武器系列或披风已完成。

小说来源和改编边界见[项目与故事](../docs/01-项目与故事.md)；玩法参考见[官网资料](../docs/11-官网参考资料.md)。原创资源不包含从《热血江湖》或其他商业游戏提取的模型、贴图、图标或音频。新增资源继续记录来源、许可、制作脚本和实际验证。
