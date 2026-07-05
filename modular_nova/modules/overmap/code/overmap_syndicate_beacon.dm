// MODULE ID: OVERMAP
// Deployable syndicate station beacon — traitor uplink purchase.
// When activated on station, reveals the NT station overmap POI to
// DS2-affiliated viewers for the rest of the round.

/obj/item/syndicate_station_beacon
	name = "station tracking beacon"
	desc = "A compact subspace beacon. When deployed and activated, it broadcasts the station's precise coordinates on syndicate frequencies."
	icon = 'modular_nova/modules/overmap/icons/stationary_beacons.dmi'
	icon_state = "synd_beacon_item"
	w_class = WEIGHT_CLASS_SMALL
	/// Whether this has already been deployed.
	var/deployed = FALSE

/obj/item/syndicate_station_beacon/attack_self(mob/user)
	if(deployed)
		to_chat(user, span_warning("[src] has already been activated."))
		return
	if(!isturf(user.loc))
		to_chat(user, span_warning("You need to be standing on solid ground to deploy this."))
		return
	// Must be on a station Z
	var/turf/T = get_turf(user)
	if(!SSmapping.level_trait(T.z, ZTRAIT_STATION))
		to_chat(user, span_warning("This device must be deployed on the station."))
		return
	to_chat(user, span_notice("You activate [src] and attach it to the floor. The beacon begins transmitting..."))
	var/obj/structure/syndicate_station_beacon/deployed_beacon = new(T)
	deployed_beacon.visible_message(span_warning("[deployed_beacon] hums to life, emitting a faint red pulse."))
	deployed = TRUE
	qdel(src)

/obj/structure/syndicate_station_beacon
	name = "station tracking beacon"
	desc = "A deployed subspace beacon pulsing with a faint red light. It's broadcasting something on an encrypted frequency."
	icon = 'modular_nova/modules/overmap/icons/stationary_beacons.dmi'
	icon_state = "synd_beacon_deployed"
	anchored = TRUE
	density = FALSE
	max_integrity = 100

/obj/structure/syndicate_station_beacon/Initialize(mapload)
	. = ..()
	SSovermap.reveal_station_to_ds2()

/obj/structure/syndicate_station_beacon/examine(mob/user)
	. = ..()
	. += span_warning("It appears to be transmitting the station's coordinates on an encrypted channel.")

// Uplink entry
/datum/uplink_item/device/syndicate_station_beacon
	name = "Station Tracking Beacon"
	desc = "A deployable subspace beacon that reveals this station's location to allied forces on the starmap. Once activated, DS2 shuttles can navigate to and dock with the station. Single use."
	item = /obj/item/syndicate_station_beacon
	cost = 6
	surplus = 0
	purchasable_from = UPLINK_NUKE_OPS | UPLINK_CLOWN_OPS
