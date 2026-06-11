// MODULE ID: OVERMAP
// Configuration entries for the overmap system. Reads from config/game_options.txt.

/datum/config_entry/string/overmap_generator_type
	default = OVERMAP_GENERATOR_RANDOM

/datum/config_entry/number/max_overmap_events
	default = 12
	min_val = 0

/datum/config_entry/number/max_overmap_event_clusters
	default = 3
	min_val = 0

/datum/config_entry/number/max_overmap_dynamic_events
	default = 4
	min_val = 0
