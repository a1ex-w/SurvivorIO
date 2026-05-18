## MCPBridge.gd
## Safe wrapper for the Godot MCP dev plugin.
##
## WHY THIS EXISTS:
##   The project uses a single build for both the dedicated server and clients.
##   The Godot MCP plugin (used locally so Claude can interact with the editor)
##   registers itself as an autoload in project.godot pointing to a file inside
##   addons/godot_mcp/. That addon is NOT deployed to the server, which caused
##   a fatal "File not found" crash on startup.
##
## HOW IT WORKS:
##   Instead of pointing the MCPGameBridge autoload directly at the addon path,
##   we point it here. This script checks at runtime whether the real bridge
##   file exists before trying to load it. If the addon isn't present (server,
##   exported client), it silently does nothing. If it is present (local dev),
##   it instantiates and attaches the real bridge node so MCP works normally.
##
## HOW TO USE:
##   1. In project.godot, the MCPGameBridge autoload should point to THIS file:
##        MCPGameBridge="res://scenes/autoloads/MCPBridge.gd"
##   2. When the Godot MCP plugin re-writes that entry to point to the addon
##      path, revert it back to this file (one edit in project.godot).
##   3. The addon can stay enabled in the editor — MCP will still work locally.

extends Node

const BRIDGE_PATH := "res://addons/godot_mcp/game_bridge/mcp_game_bridge.gd"

func _ready() -> void:
	if not ResourceLoader.exists(BRIDGE_PATH):
		# Addon not present (server or exported build) — nothing to do.
		return
	var script = load(BRIDGE_PATH)
	if script == null:
		return
	var bridge := Node.new()
	bridge.set_script(script)
	bridge.name = "MCPGameBridgeInner"
	add_child(bridge)
