extends Node

signal credits_changed(player_id, value)
signal power_changed(player_id, produced, consumed)
signal selection_changed(selection)
signal objective_changed(title, detail)
signal notification_requested(text, severity)
signal match_ended(winner_id, reason)
