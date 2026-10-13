/obj/item/implantcase/neuro_fiscal_tracker
	name = "implant case - 'Neuro Fiscal Tracker'"
	desc = "A glass case containing an Interdyne Neuro Fiscal Tracker. Enrolling an associate raises the shift revenue target by one share."
	imp_type = /obj/item/implant/neuro_fiscal_tracker

/obj/item/storage/box/neuro_fiscal_tracker_implants
	name = "boxed Neuro Fiscal Tracker enrollment kit"
	desc = "Spare Interdyne Neuro Fiscal Trackers for enrolling late arrivals in the shift revenue drive."
	illustration = "implant"

/obj/item/storage/box/neuro_fiscal_tracker_implants/Initialize(mapload)
	. = ..()
	atom_storage.max_slots = BITB_LATEJOIN_IMPLANT_COUNT + 3

/obj/item/storage/box/neuro_fiscal_tracker_implants/PopulateContents()
	var/static/items_inside = list(
		/obj/item/implantcase/neuro_fiscal_tracker = BITB_LATEJOIN_IMPLANT_COUNT,
		/obj/item/implanter = 1,
		/obj/item/implantpad = 1,
		/obj/item/book/manual/wiki/ugc/neuro_fiscal_tracker = 1,
	)
	generate_items_inside(items_inside, src)

/obj/structure/closet/secure_closet/chief_medical
	/// Whether this locker existed at round start while Back in the Black was active.
	var/bitb_roundstart_locker = FALSE

/obj/structure/closet/secure_closet/chief_medical/Initialize(mapload)
	bitb_roundstart_locker = mapload && !SSticker.HasRoundStarted() && HAS_TRAIT(SSstation, STATION_TRAIT_BACK_IN_THE_BLACK)
	return ..()

/obj/structure/closet/secure_closet/chief_medical/PopulateContents()
	. = ..()
	if(bitb_roundstart_locker)
		new /obj/item/storage/box/neuro_fiscal_tracker_implants(src)
