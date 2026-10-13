#define BITB_BAR_WIDTH 320
#define BITB_BAR_HEIGHT 10
#define BITB_COLOR_TRACK "#1a1a1a"
#define BITB_COLOR_FILL "#9147ff"
#define BITB_COLOR_MET "#2ecc71"

/// Holder for the Neuro Fiscal Tracker overlay. Untransformed so its parts can scale independently.
/atom/movable/screen/bitb_goal_bar
	name = "shareholder goal"
	icon = null
	screen_loc = "TOP-1,CENTER"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	var/atom/movable/screen/bitb_bar_part/track
	var/atom/movable/screen/bitb_bar_part/fill
	var/atom/movable/screen/bitb_bar_part/label
	var/atom/movable/screen/bitb_bar_part/alert_text
	var/goal_met = FALSE

/atom/movable/screen/bitb_goal_bar/Initialize(mapload, datum/hud/hud_owner)
	. = ..()
	track = new(null, null)
	track.icon = 'icons/effects/alphacolors.dmi'
	track.icon_state = "white"
	track.color = BITB_COLOR_TRACK
	track.alpha = 200
	track.transform = matrix(BITB_BAR_WIDTH / ICON_SIZE_X, 0, 0, 0, BITB_BAR_HEIGHT / ICON_SIZE_Y, 0)

	fill = new(null, null)
	fill.icon = 'icons/effects/alphacolors.dmi'
	fill.icon_state = "white"
	fill.color = BITB_COLOR_FILL
	fill.transform = fill_matrix(0)

	label = new(null, null)
	label.maptext_width = BITB_BAR_WIDTH
	label.maptext_height = 16
	label.pixel_x = -(BITB_BAR_WIDTH - ICON_SIZE_X) / 2
	label.pixel_y = 8

	alert_text = new(null, null)
	alert_text.maptext_width = BITB_BAR_WIDTH
	alert_text.maptext_height = 16
	alert_text.pixel_x = -(BITB_BAR_WIDTH - ICON_SIZE_X) / 2
	alert_text.pixel_y = -10
	alert_text.alpha = 0

	vis_contents += list(track, fill, label, alert_text)

/atom/movable/screen/bitb_goal_bar/Destroy()
	vis_contents.Cut()
	QDEL_NULL(track)
	QDEL_NULL(fill)
	QDEL_NULL(label)
	QDEL_NULL(alert_text)
	return ..()

/// Scale for a left-anchored fill covering `ratio` of the track.
/atom/movable/screen/bitb_goal_bar/proc/fill_matrix(ratio)
	var/fill_width = max(BITB_BAR_WIDTH * ratio, 0.01)
	var/offset = -(BITB_BAR_WIDTH - fill_width) / 2
	return matrix(fill_width / ICON_SIZE_X, 0, offset, 0, BITB_BAR_HEIGHT / ICON_SIZE_Y, 0)

/// `goal_label` must already be HTML-encoded.
/atom/movable/screen/bitb_goal_bar/proc/update_progress(earned, goal, goal_label, amount, source)
	var/ratio = goal > 0 ? clamp(earned / goal, 0, 1) : 1
	var/percent = round(ratio * 100)
	goal_met = goal > 0 && earned >= goal
	animate(fill, transform = fill_matrix(ratio), color = goal_met ? BITB_COLOR_MET : BITB_COLOR_FILL, time = 1 SECONDS, easing = SINE_EASING)
	label.maptext = MAPTEXT_PIXELLARI("<span style='text-align: center; font-size: 8pt'>[goal_label]: [bitb_credits(earned)] / [bitb_credits(goal)] cr ([percent]%)</span>")
	if(amount)
		show_contribution("+[bitb_credits(amount)] cr - [source]!")
	else if(goal_met)
		set_alert_line("AARP PAYOUT UNLOCKED - STAY ALIVE", BITB_COLOR_MET)

/atom/movable/screen/bitb_goal_bar/proc/set_alert_line(text, text_color)
	animate(alert_text)
	alert_text.maptext = MAPTEXT_PIXELLARI("<span style='text-align: center; font-size: 8pt; color: [text_color]'>[text]</span>")
	alert_text.alpha = 255

/// Donation-style popup under the bar that fades out, then falls back to the payout line if the goal is met.
/atom/movable/screen/bitb_goal_bar/proc/show_contribution(text)
	set_alert_line(text, "#ffd700")
	animate(alert_text, alpha = 255, time = 4 SECONDS)
	animate(alpha = 0, time = 1 SECONDS)
	if(goal_met)
		addtimer(CALLBACK(src, PROC_REF(set_alert_line), "AARP PAYOUT UNLOCKED - STAY ALIVE", BITB_COLOR_MET), 5 SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)

/atom/movable/screen/bitb_bar_part
	icon = null
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = APPEARANCE_UI | KEEP_APART

#undef BITB_BAR_WIDTH
#undef BITB_BAR_HEIGHT
#undef BITB_COLOR_TRACK
#undef BITB_COLOR_FILL
#undef BITB_COLOR_MET
