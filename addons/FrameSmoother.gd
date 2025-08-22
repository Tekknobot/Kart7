# FrameSmoother.gd
# Drop-in helper to stabilize gameplay that uses variable delta.
# Usage:
#   var smoother := preload("res://addons/FrameSmoother.gd").new()
#   func _process(delta): var dt = smoother.smooth_delta(delta)
# You can also call smoother.frame_budget_beg()/end() to detect spikes.
extends RefCounted

@export var target_fps: float = 60.0
@export var ema_halflife_secs: float = 0.25   # smaller = more responsive
@export var clamp_min_scale: float = 0.8      # prevents slow-mo on hiccups
@export var clamp_max_scale: float = 1.2      # prevents speedups on tiny frames

var _ema_dt: float = 1.0 / 60.0
var _alpha: float = 0.0

# spike detector (optional)
var _accum_ms: float = 0.0
var _frame_ms: float = 0.0

func _init():
    _recompute_alpha()

func _recompute_alpha() -> void:
    # Convert half-life to EMA alpha per second
    # alpha = 1 - 0.5^(dt/halflife)
    _alpha = 1.0 - pow(0.5, (1.0/target_fps) / max(ema_halflife_secs, 0.001))

func set_target_fps(fps: float) -> void:
    target_fps = max(10.0, fps)
    _recompute_alpha()

func smooth_delta(raw_dt: float) -> float:
    # Update EMA (exponential moving average) of dt
    var a := _alpha
    _ema_dt = _ema_dt + a * (raw_dt - _ema_dt)
    # Clamp around EMA to avoid gameplay speed swings
    var clamp_lo := _ema_dt * clamp_min_scale
    var clamp_hi := _ema_dt * clamp_max_scale
    return clamp(raw_dt, clamp_lo, clamp_hi)

func frame_budget_beg() -> void:
    _accum_ms = Time.get_ticks_msec()

func frame_budget_end() -> float:
    _frame_ms = float(Time.get_ticks_msec() - _accum_ms)
    return _frame_ms  # useful for logging or on‑screen graphs
