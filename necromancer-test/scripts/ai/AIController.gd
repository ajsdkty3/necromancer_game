extends RefCounted
const Policy = preload("res://scripts/ai/HeuristicPolicy.gd")
var policy = Policy.new()

func choose_action(observation: Dictionary, legal_actions: Array) -> Dictionary:
	return policy.choose_action(observation,legal_actions)
