extends Control

func setPlayerName(newName: String):
	%nameLabel.text = newName

func setHPBarRatio(ratio):
	%hpBar.value = ratio

# Stamina bar is hidden when full so it only appears during active use.
func setStaminaBarRatio(ratio):
	%staminaBar.value = ratio
	%staminaBar.visible = ratio < 1.0

# Shows a crown + win count above the player when they have at least one win.
func setCrownWins(count: int) -> void:
	if count > 0:
		%crownLabel.text = "♛%d" % count
		%crownLabel.visible = true
	else:
		%crownLabel.visible = false
