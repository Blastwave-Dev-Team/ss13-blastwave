// MODULE ID: OVERMAP
// Screen objects for the direct pilot HUD overlay. Minimal: brake button
// and speed/heading readout. These are added to client.screen during
// pilot_link() and removed on unlink().

/atom/movable/screen/pilot_hud
	icon = 'modular_nova/modules/overmap/icons/overmap.dmi'
	icon_state = "object"
	var/datum/overmap_pilot_link/parent_link

/atom/movable/screen/pilot_hud/Destroy()
	parent_link = null
	return ..()

/// Brake button - center of screen. Click to all-stop.
/atom/movable/screen/pilot_hud/brake
	name = "ALL STOP"
	icon_state = "yourship"
	screen_loc = "CENTER,CENTER"
	maptext_width = 64
	maptext_height = 32
	maptext_x = -16
	maptext_y = -20

/atom/movable/screen/pilot_hud/brake/Initialize(mapload)
	. = ..()
	maptext = {"<span style='font-family: monospace; font-size: 8px; color: #ff4444; text-align: center;'>BRAKE \[Q\]</span>"}

/atom/movable/screen/pilot_hud/brake/Click(location, control, params)
	if(!parent_link?.active || !parent_link.linked_ship)
		return
	parent_link.linked_ship.all_stop()

/// Speed/heading readout - top center of screen.
/atom/movable/screen/pilot_hud/speed_readout
	name = "Speed Readout"
	screen_loc = "CENTER,NORTH-1"
	maptext_width = 200
	maptext_height = 32
	maptext_x = -84
	maptext_y = 0
	icon_state = "yourship"
	alpha = 0
	var/update_timer_id

/atom/movable/screen/pilot_hud/speed_readout/Initialize(mapload)
	. = ..()
	update_timer_id = addtimer(CALLBACK(src, PROC_REF(update_readout)), 5, TIMER_STOPPABLE | TIMER_LOOP)

/atom/movable/screen/pilot_hud/speed_readout/Destroy()
	if(update_timer_id)
		deltimer(update_timer_id)
		update_timer_id = null
	return ..()

/atom/movable/screen/pilot_hud/speed_readout/proc/update_readout()
	if(!parent_link?.active || !parent_link.linked_ship)
		return
	var/obj/structure/overmap/ship/ship = parent_link.linked_ship
	var/speed_pct = round(clamp(ship.get_speed() / max(ship.max_speed, 0.01), 0, 1) * 100)
	var/hdg = ship.get_heading_degrees()
	maptext = {"<span style='font-family: monospace; font-size: 10px; color: #88ccff; text-align: center;'>SPD [speed_pct]% | HDG [hdg]&deg;</span>"}
