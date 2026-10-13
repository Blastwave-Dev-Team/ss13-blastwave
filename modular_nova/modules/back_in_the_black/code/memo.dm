/datum/station_trait/back_in_the_black/get_report()
	return "<i>[name]</i> - Nanotrasen is broke. Every associate is fitted with a Neuro Fiscal Tracker; hit the revenue target and the AARP pays the living. Memorandum to follow."

/datum/station_trait/back_in_the_black/proc/get_memo(memo_number)
	var/list/lines = list(
		"<b>NANOTRASEN OFFICE OF FISCAL RECOVERY</b>",
		"<b>MEMORANDUM FR-[memo_number] -- ALL HANDS -- MANDATORY READING</b>",
		"",
		"To the valued associates of [station_name()],",
		"",
		"Nanotrasen remains a world-class leader in the Blastwave Sector. The holding company for the Blastwave Sector's operations, however, is broke.",
		"",
		"Effective immediately, research, exploration, and \"science\" are suspended in favor of a more urgent mission: MONEY. Today you are not crew. You are shareholder value.",
		"",
		"<b>WHAT HAS HAPPENED TO YOUR HEAD</b>",
		"Every associate on the crew manifest at the start of the shift has been fitted with an Interdyne Neuro Fiscal Tracker (NFT). The NFT projects a live fundraising overlay into your field of vision so you never lose sight of what matters.",
		"",
		"<b>THE TARGET</b>",
		"Shift revenue target: [bitb_credits(get_goal())] cr ([bitb_credits(BITB_GOAL_PER_CREW)] cr per enrolled associate).",
		"Only revenue from OUTSIDE the station counts: cargo exports and bounties, and income from the station's service venues. Moving money between your own accounts is not revenue, and the NFT knows it.",
		"",
		"<b>THE ALIVE ASSOCIATE RETURN PROGRAM (AARP)</b>",
		"If the target is met by end of shift, the AARP returns [BITB_BONUS_FRACTION * 100]% of all shift revenue to the associates who earned it. It is split evenly and deposited to your persistent personal ledger. Membership requirements are strict: you must be ALIVE at end of shift, with your NFT installed. The AARP does not recognize posthumous membership.",
		"",
		"<b>NEW HIRES</b>",
		"Late arrivals are not enrolled automatically. The Chief Medical Officer holds spare NFT units. Each new enrollment raises the target by one associate's share, so new hires add to the pot rather than diluting it.",
		"",
		"<b>PERFORMANCE MANAGEMENT</b>",
		"An associate who is not contributing may have their NFT removed. A removed unit stays enrolled until it is presented to the Captain, who may void it with Captain-level authorization. Voiding a unit lowers the target by one associate's share. Units that are lost or destroyed stay enrolled. Please do not lose your coworkers.",
		"",
		"The full NFT Associate Handbook can be printed at any library console (ugc/interdyne-neuro-fiscal-tracker). A copy is also packed with the CMO's spare units.",
		"",
		"Thank you for your sacrifice.",
		"<i>-- Office of Fiscal Recovery, on behalf of the Nanotrasen Board</i>",
	)
	return jointext(lines, "<br>")

/datum/station_trait/back_in_the_black/proc/print_memo()
	var/memo_number = rand(100, 999)
	print_command_report(get_memo(memo_number), "Office of Fiscal Recovery: Memorandum FR-[memo_number]", announce = TRUE)
