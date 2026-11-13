# 坐标与动画探针

本项目原创开发测试资产，来源脚本为`tools/export_animation_probe.py`，不作为玩家角色，也不进入发行包。

- 制作工具：Blender4.5.15LTS，build `5afeabba6097`。
- 源文件`animation_probe.blend`，导出`animation_probe.glb`。
- 米制；Blender Z向上/+Y前向，GLB Y向上/−Z前向。
- 两个蒙皮网格、Root/Upper两骨骼，ProbeWave动画2秒。
- 红标记为+X、绿标记为−Z、蓝标记高度2.5m。

旧P2在Bevy中验证过坐标与骨骼运动，Godot需要独立验证导入、骨骼和实际播放。历史结果见[实施与验证记录](../../../docs/09-实施与验证记录.md)，正式资源标准见[资源与交互](../../../docs/04-资源与交互.md)。

重新导出前结束读取该探针的本次测试程序，核对源文件/GLB差异；不生成`.blend1`备份，不修改其他正式模型。
