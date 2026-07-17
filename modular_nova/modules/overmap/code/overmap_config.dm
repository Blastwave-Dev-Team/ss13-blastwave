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

/datum/config_entry/number/max_overmap_named_sites
	default = 10
	min_val = 0

/// How many small (≤ OVERMAP_CLUSTER_RUIN_MAX_SIDE) ruins share one cluster Z.
/// Z count ≈ solos + ceil(smalls / capacity). SPACE_BUDGET still spends per ruin.
/datum/config_entry/number/overmap_cluster_capacity
	default = 4
	min_val = 1

/// Landing zones seeded per named site Z (multi-ship adversarial docking).
/datum/config_entry/number/overmap_site_lz_count
	default = 3
	min_val = 1

/datum/config_entry/number/max_overmap_landing_zone_dimension
	default = 80
	min_val = 10
