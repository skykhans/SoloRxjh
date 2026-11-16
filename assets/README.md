# 资源来源索引

更新日期：2026-11-16。资产以Godot项目导入和运行时目录为准；现有资源已从旧版RON配置迁移为正式JSON清单，模型、动画与最终美术仍待独立验收。资源与现代界面规范统一见[资源与交互](../docs/04-资源与交互.md)。

| 目录 | 来源 | 维护方式 |
| --- | --- | --- |
| `models/characters/*.glb` | 本项目原创角色、野兽、竹、骨架与动画 | `tools/export_game_models.py`，Blender4.5.15LTS |
| `models/sources/characters.blend` | 可编辑的角色与生物源工程，不导入游戏 | `tools/export_game_models.py`，Godot通过同目录`.gdignore`跳过源文件 |
| `audio/*.wav` | 本项目原创标准库波形合成，无第三方录音/采样 | `tools/generate_audio.py` |
| `fonts/NotoSansCJKsc-Regular.otf` | Adobe/Google Noto CJK | [字体来源与哈希](fonts/README.md)、[SIL OFL1.1](fonts/OFL.txt) |
| `models/probes/` | 本项目原创坐标/骨骼测试资产 | [探针说明](models/probes/README.md)，Godot导入和发行均排除 |
| `config/resources.json` | 正式运行时资源清单 | Godot启动严格校验路径、唯一ID与导入类型 |

原`.ron`运行配置已清除；场景、玩法和任务数据以Godot配置及采用合同迁移，旧场景几何基线保存在文档参考JSON。已有6个GLB、方尘14动画与11个WAV不等于目标版八职业、武器系列或披风已完成。

小说来源和改编边界见[项目与故事](../docs/01-项目与故事.md)；玩法参考见[官网资料](../docs/11-官网参考资料.md)。原创资源不包含从《热血江湖》或其他商业游戏提取的模型、贴图、图标或音频。新增资源继续记录来源、许可、制作脚本和实际验证。
