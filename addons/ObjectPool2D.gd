# ObjectPool2D.gd
# Simple generic pool for Node2D-based effects (skid trails, clouds, sparks).
# Usage:
#   var pool := preload("res://addons/ObjectPool2D.gd").new(packed_scene, 64, get_tree().current_scene)
#   var node = pool.get()
#   pool.recycle(node)
class_name ObjectPool2D
extends Node

var _scene: PackedScene
var _parent: Node
var _free: Array[Node] = []
var _all: Array[Node] = []

func _init(scene: PackedScene = null, initial: int = 0, parent: Node = null):
    if scene: setup(scene, initial, parent)

func setup(scene: PackedScene, initial: int, parent: Node) -> void:
    _scene = scene
    _parent = parent
    _prewarm(initial)

func _prewarm(n: int) -> void:
    for i in n:
        var inst := _scene.instantiate()
        _parent.add_child(inst)
        inst.visible = false
        _free.push_back(inst)
        _all.push_back(inst)

func get() -> Node:
    if _free.is_empty():
        var inst := _scene.instantiate()
        _parent.add_child(inst)
        _all.push_back(inst)
        return inst
    var node := _free.pop_back()
    node.visible = true
    return node

func recycle(node: Node) -> void:
    if node == null: return
    node.visible = false
    if node.get_parent() == null and _parent != null:
        _parent.add_child(node)
    _free.push_back(node)

func recycle_all() -> void:
    for n in _all:
        recycle(n)
