extends Node

var voice_id = ""
var next_allowed_ms = 0
var warned_unavailable = false
var adjutant_next_allowed_ms = 0

const PHRASES = {
    "rifle": {
        "select": ["步枪班待命", "长官，请下令"],
        "move": ["正在前进", "收到"],
        "attack": ["锁定目标", "开始交火"],
        "ready": ["步枪班报道"]
    },
    "rocket": {
        "select": ["火箭小组待命", "反装甲小组就绪"],
        "move": ["正在转移", "明白"],
        "attack": ["火箭准备", "目标已确认"],
        "ready": ["火箭兵就绪"]
    },
    "tank": {
        "select": ["装甲部队待命", "主炮已就绪"],
        "move": ["装甲部队前进", "履带启动"],
        "attack": ["主炮瞄准", "摧毁目标"],
        "ready": ["主战坦克出厂"],
        "crush": ["清除步兵"]
    },
    "scout": {
        "select": ["侦察车在线", "等待坐标"],
        "move": ["高速前往", "正在侦察"],
        "attack": ["武器开火", "目标接触"],
        "ready": ["侦察车就绪"]
    },
    "harvester": {
        "select": ["采矿车待命", "矿舱状态正常"],
        "move": ["正在前往", "路线确认"],
        "attack": ["无法执行攻击"],
        "ready": ["采矿车已部署"]
    }
}

func _ready():
    call_deferred("_select_voice")

func _select_voice():
    var candidates = DisplayServer.tts_get_voices_for_language("zh")
    if candidates.is_empty():
        candidates = DisplayServer.tts_get_voices_for_language("zh-CN")
    if candidates.is_empty():
        candidates = DisplayServer.tts_get_voices_for_language("zh_TW")
    if not candidates.is_empty():
        voice_id = str(candidates[0])
        return
    for item in DisplayServer.tts_get_voices():
        if item is Dictionary and str(item.get("language", "")).to_lower().begins_with("zh"):
            voice_id = str(item.get("id", ""))
            return
    var all_voices = DisplayServer.tts_get_voices()
    if not all_voices.is_empty() and all_voices[0] is Dictionary:
        voice_id = str(all_voices[0].get("id", ""))

func speak(unit_id, event_name, force = false):
    if not bool(SaveManager.settings.get("unit_voices", true)):
        return
    var now = Time.get_ticks_msec()
    if not force and now < next_allowed_ms:
        return
    if voice_id == "":
        _select_voice()
    if voice_id == "":
        if not warned_unavailable:
            warned_unavailable = true
            EventBus.notification_requested.emit("系统未提供可用的文字转语音引擎，单位语音已自动跳过", "warning")
        return
    var unit_phrases = PHRASES.get(unit_id, {})
    var event_phrases = unit_phrases.get(event_name, [])
    if event_phrases.is_empty():
        return
    var text = str(event_phrases[randi() % event_phrases.size()])
    var master = clamp(float(SaveManager.settings.get("master_volume", 0.8)), 0.0, 1.0)
    var voice = clamp(float(SaveManager.settings.get("voice_volume", 0.75)), 0.0, 1.0)
    var volume = int(round(master * voice * 100.0))
    if volume <= 0:
        return
    var pitch = 0.92 if unit_id in ["tank", "harvester"] else 1.02
    DisplayServer.tts_speak(text, voice_id, volume, pitch, 1.08, 0, true)
    next_allowed_ms = now + 1050

func stop():
    DisplayServer.tts_stop()


func speak_adjutant(event_name, detail = ""):
    if not bool(SaveManager.settings.get("unit_voices", true)):
        return
    var phrases = {
        "building_ready": ["建筑已就绪", "建筑部署准备完成"],
        "unit_ready": ["单位已就绪", "增援单位已经抵达"],
        "unit_attacked": ["我们的单位遭到攻击", "部队正在承受攻击"],
        "harvester_attacked": ["我们的矿车遭到攻击", "采矿单位正在遭受攻击"],
        "building_attacked": ["我们的建筑遭到攻击", "基地设施正在遭受攻击"],
        "cancel": ["已取消", "命令取消"],
        "low_power": ["电力不足", "基地电力供应不足"]
    }
    var options = phrases.get(event_name, [])
    if options.is_empty(): return
    var now = Time.get_ticks_msec()
    if now < adjutant_next_allowed_ms: return
    if voice_id == "": _select_voice()
    if voice_id == "": return
    var text = str(options[randi() % options.size()])
    if detail != "": text += "，" + detail
    var volume = int(round(clamp(float(SaveManager.settings.get("master_volume",0.8)),0.0,1.0) * clamp(float(SaveManager.settings.get("voice_volume",0.75)),0.0,1.0) * 100.0))
    DisplayServer.tts_speak(text, voice_id, volume, 1.0, 1.03, 0, true)
    adjutant_next_allowed_ms = now + 3200
