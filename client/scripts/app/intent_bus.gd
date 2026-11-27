extends Node
## 玩家操作 → 玩法意图（Autoload IntentBus）。
##
## 表现层（按钮、面板）只调用 emit_intent，禁止直接改 RunState 或库存。
## 命名与处理方对照：开发计划 §12.9 · modules/GODOT_ARCH Intent 目录。

signal intent_emitted(intent_name: String, payload: Dictionary)

## 派发玩法意图；唯一 UI→逻辑入口（§12.9）。
##
## Autoload IntentBus；presentation → gameplay 唯一信号入口。
## @param intent_name IntentBus 意图名
## @param payload Intent 附带的 Dictionary
func emit_intent(intent_name: String, payload: Dictionary = {}) -> void:
	intent_emitted.emit(intent_name, payload)