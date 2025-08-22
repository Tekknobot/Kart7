# PropertyGuard.gd
# Micro-optimization helpers to avoid writing the same property every frame.
# Usage: if PropertyGuard.set_vec2_if_changed(node, &"position", target): ...
extends RefCounted

static func set_vec2_if_changed(obj: Object, prop: StringName, v: Vector2, eps: float = 0.001) -> bool:
    if not obj or not obj.has_method("get"):
        return false
    var cur: Vector2 = obj.get(prop)
    if cur.distance_squared_to(v) > eps * eps:
        obj.set(prop, v)
        return true
    return false

static func set_float_if_changed(obj: Object, prop: StringName, f: float, eps: float = 0.0001) -> bool:
    if not obj or not obj.has_method("get"):
        return false
    var cur: float = obj.get(prop)
    if abs(cur - f) > eps:
        obj.set(prop, f)
        return true
    return false

static func set_int_if_changed(obj: Object, prop: StringName, i: int) -> bool:
    if not obj or not obj.has_method("get"):
        return false
    var cur: int = obj.get(prop)
    if cur != i:
        obj.set(prop, i)
        return true
    return false
