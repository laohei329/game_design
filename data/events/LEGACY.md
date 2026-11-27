# 事件卡库（Legacy）

> **状态**：默认 **自发 incident**；`useLegacyEventCards=true` 时段叙事走 `EventDraw` + 本目录 JSON。  
> **自发路径**：设为 `false` 后段/日后果读 [`../incidents.json`](../incidents.json) · [`../stress.json`](../stress.json)。

- 勿再增写选项型事件卡（红线 #14 · `architecture.md`）。  
- `events_index` 在 `manifest.legacyFiles`（Godot 默认不载；Python/对照可载）。  
- `loadLegacyEventCatalog=false` 时客户端 **不读** 单卡 JSON（省 IO）；`CHOOSE_EVENT_OPTION` 仅服务于旧存档含 `eventId` 时须暂留 `true`。

阶段 5 未物理搬迁本目录；完整下线见 [`modules/06-incident-migration.md`](../../modules/06-incident-migration.md) 阶段 6–7。