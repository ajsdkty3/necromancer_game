extends RefCounted
const Policy = preload("res://scripts/ai/HeuristicPolicy.gd")
var policy = Policy.new()
const Planner = preload("res://scripts/ai/FocusPlanner.gd")
var planner = Planner.new()
var focus_plan: Dictionary = {}

func choose_action(observation: Dictionary, legal_actions: Array) -> Dictionary:
	focus_plan = planner.plan(observation)
	if not focus_plan.is_empty() and focus_plan.contributors.has(observation.active_human):
		var focused = observation.duplicate(true)
		focused.focus_target_id = focus_plan.target_id
		var choices = legal_actions.filter(func(a): return not a.has("target_unit_id") or a.target_unit_id==focus_plan.target_id)
		return policy.choose_action(focused,choices)
	return policy.choose_action(observation,legal_actions)
