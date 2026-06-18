// =============================================================================
// Arachnid silk abilities. Granted by /obj/item/organ/spider_spinneret on insert
// (and removed on uninsert) via the standard organ `actions` list pipeline.
//
// Two click-driven cooldown actions:
//   * Spin Web    - lays a sticky web on the spinner's tile.
//   * Spin Cocoon - click-to-target an adjacent atom, wraps it into a cocoon.
//
// Both abilities are dual-gated on a cooldown AND a nutrition cost - "costly
// in more than time". Each weave is a long do_after that cancels on either the
// spinner or the victim moving (matching the WS feel; modern do_after with the
// default NONE flags already enforces this).
//
// Spawns distinct structure subtypes (`/arachnid_spun`) for both webs and
// cocoons so admins/maintainers can tune balance independently of admin /
// NPC giant-spider stickywebs and cocoons without affecting non-Arachnid
// spider mobs.
//
// Both actions inherit from existing TG-side base classes
// (`/datum/action/cooldown/mob_cooldown/lay_web` and `.../wrap`) which already
// handle button-icon swapping, do_after movement cancellation, balloon alerts,
// and click-to-target plumbing. Our subclasses only override the bits that
// differ from the NPC giant-spider versions.
// =============================================================================

// --- Tunables ----------------------------------------------------------------
#define ARACHNID_SILK_NUTRITION_FLOOR  NUTRITION_LEVEL_HUNGRY
#define ARACHNID_WEB_NUTRITION_COST    35
#define ARACHNID_WEB_COOLDOWN          (30 SECONDS)
#define ARACHNID_WEB_SPIN_TIME         (10 SECONDS)
#define ARACHNID_WEB_STUCK_CHANCE      20
#define ARACHNID_COCOON_NUTRITION_COST 200
#define ARACHNID_COCOON_COOLDOWN       (30 SECONDS)
#define ARACHNID_COCOON_WRAP_TIME      (10 SECONDS)
#define ARACHNID_COCOON_SUFFOCATION_DAMAGE 2

// --- Web action --------------------------------------------------------------
/datum/action/cooldown/mob_cooldown/lay_web/arachnid
	desc = "Spin a sticky web on your tile. Costs nutrition and a long uninterrupted spin - moving cancels it."
	cooldown_time = ARACHNID_WEB_COOLDOWN
	webbing_time = ARACHNID_WEB_SPIN_TIME

/datum/action/cooldown/mob_cooldown/lay_web/arachnid/IsAvailable(feedback = FALSE)
	. = ..()
	if(!.)
		return FALSE
	if(!ishuman(owner))
		return FALSE
	var/mob/living/carbon/human/spinner = owner
	if(spinner.nutrition < ARACHNID_SILK_NUTRITION_FLOOR)
		if(feedback)
			spinner.balloon_alert(spinner, "too hungry!")
		return FALSE
	return TRUE

/// Override of the base spawn point. existing_web is always null because the
/// base IsAvailable's obstructed_by_other_web() check gates against it.
/datum/action/cooldown/mob_cooldown/lay_web/arachnid/plant_web(turf/target_turf, obj/structure/spider/stickyweb/existing_web)
	var/mob/living/carbon/human/spinner = owner
	spinner.adjust_nutrition(-ARACHNID_WEB_NUTRITION_COST)
	new /obj/structure/spider/stickyweb/arachnid_spun(target_turf, spinner)

// --- Cocoon action -----------------------------------------------------------
// We deliberately do NOT inherit the NPC wrap's death() / egg-empower behavior
// from /datum/action/cooldown/mob_cooldown/wrap; only wrap_target() is overridden,
// so we keep the click-to-target mousepointer, button icon swap, do_after
// pipeline, and target validation (no MOB_SPECIAL/MOB_SPIRIT/anchored targets)
// from the base class.
/datum/action/cooldown/mob_cooldown/wrap/arachnid
	desc = "Wrap an adjacent target into a sticky cocoon. Costs nutrition and a long \
		uninterrupted weave - moving cancels it. Activate, then click on a target."
	cooldown_time = ARACHNID_COCOON_COOLDOWN
	wrap_time = ARACHNID_COCOON_WRAP_TIME

/datum/action/cooldown/mob_cooldown/wrap/arachnid/IsAvailable(feedback = FALSE)
	. = ..()
	if(!.)
		return FALSE
	if(!ishuman(owner))
		return FALSE
	var/mob/living/carbon/human/spinner = owner
	if(spinner.nutrition < ARACHNID_SILK_NUTRITION_FLOOR)
		if(feedback)
			spinner.balloon_alert(spinner, "too hungry!")
		return FALSE
	return TRUE

/// Override: spawn our distinct subtype, deduct nutrition on success, and
/// notably skip the kill-on-wrap behavior of the base NPC giant-spider wrap.
/// WS-faithful: the cocoon imprisons but does not kill.
/datum/action/cooldown/mob_cooldown/wrap/arachnid/wrap_target(mob/living/to_wrap)
	var/mob/living/carbon/human/spinner = owner
	spinner.adjust_nutrition(-ARACHNID_COCOON_NUTRITION_COST)
	var/obj/structure/spider/cocoon/arachnid_spun/casing = new(to_wrap.loc)
	to_wrap.forceMove(casing)
	if(isliving(to_wrap) && (to_wrap.mob_biotypes & MOB_HUMANOID))
		casing.icon_state = pick("cocoon_large1", "cocoon_large2", "cocoon_large3")
	else
		casing.icon_state = pick("cocoon1", "cocoon2", "cocoon3")
	if(isliving(to_wrap))
		log_combat(spinner, to_wrap, "arachnid cocooned")

// --- Structures --------------------------------------------------------------
/// Player-spun web from an Arachnid. Exists as a distinct subtype so that
/// stuck_chance / projectile_stuck_chance / max_integrity / decay can be tuned
/// independently of admin spider / NPC giant-spider stickywebs without
/// affecting any NPC spider AI scripts (which still see the parent type).
/obj/structure/spider/stickyweb/arachnid_spun
	desc = "It's stringy and sticky, with a faint chitinous sheen. Spun by an arachnid."
	/// Arachnid who spun this tile; always passes through unhindered.
	var/mob/living/spinner

/obj/structure/spider/stickyweb/arachnid_spun/Initialize(mapload, mob/living/spinner)
	. = ..()
	src.spinner = spinner

/obj/structure/spider/stickyweb/arachnid_spun/is_whitelisted(mob/candidate)
	return candidate == spinner

/// Creator (and anyone they pull) never stick via is_whitelisted; other
/// Arachnids use a reduced stuck chance.
/obj/structure/spider/stickyweb/arachnid_spun/get_stuck_chance(mob/living/victim)
	if(isarachnid(victim) || (victim.pulledby && isarachnid(victim.pulledby)))
		return ARACHNID_WEB_STUCK_CHANCE
	return ..()

/// Arachnid-only examine blurb for stickywebs. Subtypes override for finer detail.
/obj/structure/spider/stickyweb/proc/get_arachnid_web_examine(mob/user)
	if(!isarachnid(user))
		return null
	if(istype(src, /obj/structure/spider/stickyweb/genetic))
		return null
	return "This crude web was spun by a lesser spider."

/obj/structure/spider/stickyweb/examine(mob/user)
	. = ..()
	var/arachnid_examine = get_arachnid_web_examine(user)
	if(arachnid_examine)
		. += span_notice(arachnid_examine)

/obj/structure/spider/stickyweb/arachnid_spun/get_arachnid_web_examine(mob/user)
	if(!isarachnid(user))
		return null
	if(QDELETED(spinner) || !spinner)
		return "This silk is unmistakably arachnid, but you can't tell who spun it."
	if(user == spinner)
		return "You recognize your own weave."
	return "You recognize the weave of [spinner]."

/// Player-spun cocoon from an Arachnid. Distinct subtype so that
/// max_integrity and breakout time can be tuned independently of admin
/// spider / NPC giant-spider cocoons.
/obj/structure/spider/cocoon/arachnid_spun
	desc = "Something wrapped in silken web by an arachnid."

/obj/structure/spider/cocoon/arachnid_spun/proc/occupant_breathes(mob/living/inmate)
	if(inmate.stat == DEAD)
		return FALSE
	if(HAS_TRAIT(inmate, TRAIT_NOBREATH) || HAS_TRAIT(inmate, TRAIT_NO_BREATHLESS_DAMAGE))
		return FALSE
	if(iscarbon(inmate))
		return !isnull(inmate.get_organ_slot(ORGAN_SLOT_LUNGS))
	if(istype(inmate, /mob/living/simple_animal))
		var/mob/living/simple_animal/simple_inmate = inmate
		return simple_inmate.unsuitable_atmos_damage && simple_inmate.atmos_requirements
	if(istype(inmate, /mob/living/basic))
		var/mob/living/basic/basic_inmate = inmate
		return basic_inmate.unsuitable_atmos_damage && basic_inmate.habitable_atmos
	return FALSE

/// Airtight wrap: carbons suffocate through the normal breath pipeline, while
/// simple/basic mobs with atmos requirements are handled in process() because
/// that element treats any non-turf loc (including this cocoon) as safe air.
/obj/structure/spider/cocoon/arachnid_spun/handle_internal_lifeform(mob/lifeform_inside_me, breath_request)
	if(breath_request <= 0 || !isliving(lifeform_inside_me))
		return ..()
	var/mob/living/inmate = lifeform_inside_me
	if(!occupant_breathes(inmate) || !iscarbon(inmate))
		return ..()
	return null

/obj/structure/spider/cocoon/arachnid_spun/Entered(atom/movable/arrival, atom/old_loc)
	. = ..()
	if(isliving(arrival) && occupant_breathes(arrival) && !iscarbon(arrival))
		START_PROCESSING(SSobj, src)

/obj/structure/spider/cocoon/arachnid_spun/process(seconds_per_tick)
	for(var/mob/living/inmate as anything in contents)
		if(!occupant_breathes(inmate) || iscarbon(inmate))
			continue
		var/damage = ARACHNID_COCOON_SUFFOCATION_DAMAGE * seconds_per_tick
		if(istype(inmate, /mob/living/simple_animal))
			inmate.adjust_brute_loss(damage)
		else
			inmate.apply_damage(damage, OXY)
		inmate.throw_alert(ALERT_NOT_ENOUGH_OXYGEN, /atom/movable/screen/alert/not_enough_oxy)
		return
	return PROCESS_KILL

// --- Cleanup -----------------------------------------------------------------
#undef ARACHNID_SILK_NUTRITION_FLOOR
#undef ARACHNID_WEB_NUTRITION_COST
#undef ARACHNID_WEB_COOLDOWN
#undef ARACHNID_WEB_SPIN_TIME
#undef ARACHNID_WEB_STUCK_CHANCE
#undef ARACHNID_COCOON_NUTRITION_COST
#undef ARACHNID_COCOON_COOLDOWN
#undef ARACHNID_COCOON_WRAP_TIME
#undef ARACHNID_COCOON_SUFFOCATION_DAMAGE
