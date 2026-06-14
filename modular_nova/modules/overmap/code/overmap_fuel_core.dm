// MODULE ID: OVERMAP
// Fuel cores: consumable reaction mass items that slot into overmap engines.
// The core provides reaction mass; the engine draws power from the ship's
// electrical grid. Thrust = f(available_power, core_efficiency).
//
// Future design (do not implement yet, preserve here):
// - Gravitational anomaly: 2.0x ISP, 80 mass — fuel-efficient explorer
// - Pyroclastic anomaly: 0.7x ISP, 150 mass — high burst thrust, burns fast
// - Flux anomaly: 1.5x ISP, 120 mass — balanced, pairs with high power grids
// - Bluespace anomaly: 1.2x ISP, 60 mass — enables blink/microjump special
// - Vortex anomaly: 3.0x ISP, 40 mass — unstable, catastrophic detonation
//   risk under heavy burn
// - Refined cores: science refinement process, type * 1.3x ISP, type * 1.5x mass
// - Acquisition paths: station anomaly events, overmap anomaly fields,
//   mining deposits, derelict salvage

/obj/item/fuel_core
	name = "plasma fuel core"
	desc = "A cylinder of compressed reaction mass used by overmap engines. Insert into an engine's core slot."
	icon = 'icons/obj/devices/new_assemblies.dmi'
	icon_state = "anomaly_core"
	w_class = WEIGHT_CLASS_NORMAL
	/// Current reaction mass remaining.
	var/reaction_mass = 100
	/// Maximum reaction mass capacity.
	var/reaction_mass_max = 100
	/// ISP efficiency multiplier. Higher = more thrust per mass consumed.
	var/efficiency = 1.0
	/// Display name for the core type.
	var/core_type = "Plasma"

/obj/item/fuel_core/examine(mob/user)
	. = ..()
	. += span_notice("Reaction mass: [round(reaction_mass, 0.1)]/[reaction_mass_max] ([round(reaction_mass / reaction_mass_max * 100)]%)")
	. += span_notice("Efficiency (ISP): [efficiency]x")
	. += span_notice("Core type: [core_type]")
	if(reaction_mass <= 0)
		. += span_warning("This core is depleted and must be replaced.")

/obj/item/fuel_core/proc/is_depleted()
	return reaction_mass <= 0

/// Anomaly-grade fuel core. Uniformly superior to plasma.
/obj/item/fuel_core/anomaly
	name = "anomaly fuel core"
	desc = "A fuel core refined from a captured anomaly. Superior reaction mass density and efficiency."
	icon_state = "flux_core"
	reaction_mass = 150
	reaction_mass_max = 150
	efficiency = 1.5
	core_type = "Anomaly"
