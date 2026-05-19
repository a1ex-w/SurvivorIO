# Full-screen "How to Play" overlay shown from the Settings menu.
# Emits `closed` when the player dismisses it so the caller can restore focus.
# Usage: instance how_to_play.tscn, connect the `closed` signal, call show().
extends Control

signal closed

func _ready() -> void:
	hide()

func _on_close_pressed() -> void:
	hide()
	closed.emit()
