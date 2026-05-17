extends Control

func setPlayerName(newName: String):
	%nameLabel.text = newName

func setHPBarRatio(ratio):
	%hpBar.value = ratio

func setStaminaBarRatio(ratio):
	%staminaBar.value = ratio
	%staminaBar.visible = ratio < 1.0
