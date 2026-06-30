/datum/job/solfed_representative
	title = JOB_NT_REP
	description = "Represent the Solar Federation on the station, argue with everyone about federal law. Be hated as a fed."
	faction = FACTION_STATION
	total_positions = 1
	spawn_positions = 1
	supervisors = JOB_SOLFED
	minimal_player_age = 18
	exp_requirements = 600
	exp_required_type = EXP_TYPE_CREW
	exp_required_type_department = EXP_TYPE_COMMAND
	exp_granted_type = EXP_TYPE_CREW
	config_tag = "SOLFED_REPRESENTATIVE"

	department_for_prefs = /datum/job_department/captain

	departments_list = list(
		/datum/job_department/command,
		/datum/job_department/central_command
	)

	outfit = /datum/outfit/job/solfed_representative
	plasmaman_outfit = /datum/outfit/plasmaman/solfed_representative

	paycheck = PAYCHECK_COMMAND
	paycheck_department = ACCOUNT_CMD

	display_order = JOB_DISPLAY_ORDER_SOLFED_REPRESENTATIVE
	bounty_types = CIV_JOB_SEC

	family_heirlooms = list(/obj/item/book/manual/wiki/security_space_law)

	mail_goodies = list(
		/obj/item/cigarette/cigar/havana = 20,
		/obj/item/storage/fancy/cigarettes/cigars/havana = 15,
		/obj/item/reagent_containers/cup/glass/bottle/champagne = 10
	)

	nova_stars_only = TRUE
	job_flags = STATION_JOB_FLAGS | JOB_BOLD_SELECT_TEXT | JOB_CANNOT_OPEN_SLOTS | JOB_ANTAG_PROTECTED

/datum/outfit/job/solfed_representative
	name = "Sol Federation Representative"
	jobtype = /datum/job/solfed_representative

	belt = /obj/item/modular_computer/pda/nanotrasen_consultant
	glasses = /obj/item/clothing/glasses/sunglasses
	ears = /obj/item/radio/headset/heads/nanotrasen_consultant
	gloves = /obj/item/clothing/gloves/combat/naval/nanotrasen_consultant/black
	uniform =  /obj/item/clothing/under/rank/nanotrasen_consultant
	suit = /obj/item/clothing/suit/fedcoat/capt
	shoes = /obj/item/clothing/shoes/jackboots
	head = /obj/item/clothing/head/nanotrasen_consultant
	backpack_contents = list(
		/obj/item/melee/baton/telescopic = 1,
		/obj/item/choice_beacon/ntc = 1,
		)

	skillchips = list(/obj/item/skillchip/disk_verifier)

	backpack = /obj/item/storage/backpack
	satchel = /obj/item/storage/backpack/satchel
	duffelbag = /obj/item/storage/backpack/duffelbag
	messenger = /obj/item/storage/backpack/messenger

	implants = list(/obj/item/implant/mindshield)
	accessory = /obj/item/clothing/accessory/medal/gold/nanotrasen_consultant

	chameleon_extras = list(/obj/item/gun/energy/e_gun, /obj/item/stamp/centcom)

	id = /obj/item/card/id/advanced/solfed
	id_trim = /datum/id_trim/job/solfed_representative

/obj/item/encryptionkey/headset_cent/ccrep
	name = "\improper SolFed Representative's encryption key"
	channels = list(RADIO_CHANNEL_CENTCOM = 1, RADIO_CHANNEL_SECURITY = 1)

/obj/item/radio/headset/heads/nanotrasen_consultant
	name = "\proper the SolFed Representative's headset"
	desc = "An official Sol Federation headset."
	icon_state = "cent_headset"
	keyslot = new /obj/item/encryptionkey/headset_com
	keyslot2 = new /obj/item/encryptionkey/headset_cent/ccrep

/obj/item/radio/headset/heads/nanotrasen_consultant/alt
	name = "\proper the solfed representative's bowman headset"
	desc = "An official Central Command headset. Protects ears from flashbangs."
	icon_state = "cent_headset_alt"

/obj/item/radio/headset/heads/nanotrasen_consultant/alt/Initialize(mapload)
	. = ..()
	AddComponent(/datum/component/wearertargeting/earprotection, list(ITEM_SLOT_EARS))

/obj/effect/landmark/start/nanotrasen_consultant
	name = "Sol Federation Representative"
	icon_state = "Nanotrasen Consultant"
	icon = 'modular_nova/master_files/icons/mob/landmarks.dmi'

/obj/item/clothing/accessory/medal/gold/nanotrasen_consultant
	name = "medal of diplomacy"
	desc = "A golden medal awarded exclusively to those promoted to the rank of Sol Federation Representative. It signifies the diplomatic abilities of said individual and their sheer dedication to the Solar Federation."
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | ACID_PROOF

/datum/outfit/plasmaman/solfed_representative
	name = "Solfed Representative Plasmaman"

	uniform = /obj/item/clothing/under/plasmaman/centcom_official
	gloves = /obj/item/clothing/gloves/captain //Too iconic to be replaced with a plasma version
	head = /obj/item/clothing/head/helmet/space/plasmaman/centcom_official

/obj/item/modular_computer/pda/nanotrasen_consultant
	name = "solfed representative's PDA"
	inserted_disk = /obj/item/disk/computer/command/captain
	inserted_item = /obj/item/pen/fountain/solfed
	greyscale_colors = "#017941#0060b8"

/obj/item/storage/bag/garment/nanotrasen_consultant
	name = "solfed representatives's garment bag"
	desc = "A bag for storing extra clothes and shoes. This one belongs to the SolFed Representative."

/obj/item/storage/bag/garment/nanotrasen_consultant/PopulateContents()
	new /obj/item/clothing/shoes/sneakers/brown(src)
	new /obj/item/clothing/glasses/sunglasses/gar/giga(src)
	new /obj/item/clothing/gloves/combat/naval/nanotrasen_consultant/black(src)
	new /obj/item/clothing/under/rank/nanotrasen_consultant(src)
	new /obj/item/clothing/under/rank/nanotrasen_consultant/skirt(src)
	new /obj/item/clothing/under/imperial/nanotrasen_consultant(src)
	new /obj/item/clothing/under/imperialskirt/nanotrasen_consultant(src)
	new /obj/item/clothing/head/nanotrasen_consultant(src)
	new /obj/item/clothing/head/nanotrasen_consultant/beret(src)
	new /obj/item/clothing/suit/armor/vest/nanotrasen_consultant/green(src)

/obj/structure/closet/secure_closet/nanotrasen_consultant
	name = "solfed representative's locker"
	req_access = list(ACCESS_CAPTAIN, ACCESS_CENT_GENERAL)
	icon_state = "solfed"
	icon = 'modular_nova/master_files/icons/obj/closet.dmi'

/obj/structure/closet/secure_closet/nanotrasen_consultant/PopulateContents()
	..()
	new /obj/item/storage/backpack/satchel/leather(src)
	new /obj/item/clothing/neck/petcollar(src)
	new /obj/item/pet_carrier(src)
	new /obj/item/clothing/suit/armor/vest(src)
	new /obj/item/radio/headset/heads/nanotrasen_consultant/alt(src)
	new /obj/item/radio/headset/heads/nanotrasen_consultant(src)
	new /obj/item/storage/photo_album/personal(src)
	new /obj/item/storage/bag/garment/nanotrasen_consultant(src)

//Choice Beacon, I hope in the future they're going to be given proper unique gun but this will do.


/obj/item/choice_beacon/ntc
	name = "gunset beacon"
	desc = "A single use beacon to deliver a gunset of your choice. Please only call this in your office"
	icon_state = "cc_beacon"
	inhand_icon_state = "cc_beacon"
	icon = 'modular_nova/modules/modular_items/icons/remote.dmi'
	lefthand_file = 'modular_nova/modules/modular_items/icons/inhand/mobs/lefthand_remote.dmi'
	righthand_file = 'modular_nova/modules/modular_items/icons/inhand/mobs/righthand_remote.dmi'
	company_source = "Trappiste Fabriek Company"
	company_message = span_bold("Supply Pod incoming please stand by")

/obj/item/choice_beacon/ntc/generate_display_names()
	var/static/list/selectable_gun_types = list(
		"Takbok Revolver Set" = /obj/item/storage/toolbox/guncase/nova/pistol/trappiste_small_case/takbok,
		"Skild Pistol Set" = /obj/item/storage/toolbox/guncase/nova/pistol/trappiste_small_case/skild,
	)

	return selectable_gun_types

/obj/item/paper/solfed_rep_guide1
	name = "FEDERAL OVERSIGHT DIRECTIVE 12-77"
	default_raw_text = "</center><center><h3> SUBJECT: ESTABLISHMENT OF SOL FEDERATION REPRESENTATIVE OFFICE</h3></center><hr><br>The NT Consultant program was intended to demonstrate nanotrasen's capacity for internal self-regulation under federally approved Corporate Regulations. Repeated station reviews have shown systemic failure of internal oversight during high-stress conditions.<br><br>Common findings include:<br>Breakdown of due process during emergencies, unlawful or excessive security enforcement, inconsistent application of sentencing standards, failure of post-incident corrective mechanisms, failure to protect basic Federal civil rights.<br><br>These failures occur despite prior CentCom review and intervention. Therefore, after much negotiation, investigation and legal action, the Federation has determined that internal oversight alone is insufficient as a compliance guarantee.<br><br>The Sol Federation Representative Office is established aboard licensed nanotrasen stations to provide independent observation of station legal proceedings, documentation of rights compliance and escalation channel to federal authorities when required.<br>This office does not replace nanotrasen command structures. It operates alongside them as an external oversight presence."

/obj/item/paper/solfed_rep_guide2
	name = "SOLFED REP - ROLE SUMMARY"
	default_raw_text = "</center><center><h3> SUBJECT: FUNCTIONAL ROLE OF THE REPRESENTATIVE</center></h3><hr><br>You are <b>NOT</b> station command, <b>NOT</b> security, <b>NOT</b> corporate legal staff(1), and <b>NOT</b> part of nanotrasen chain of command.<br><font size=1>(1)Although this is true, corporate lawyers share a common goal with you, and working with them is highly recommended and encouraged.</font><br><br>Your core responsibilities include observing station legal and security activity (you are granted limited security access), ensuring compliance with the Federal Declaration of Rights, documenting significant events, receiving complaints from crew, and escalating serious violations to Federation channels.<br>Importantly, your primary focus is not punishment or command intervention, but rights compliance and lawful procedure monitoring. You do not manage daily operations. You monitor whether operations remain legally and constitutionally valid.<br><br>If you ever wish to query the local Federal office, or have a situation elevated to Federal channels, or you require our help to enforce your role, simply send a complaint to our Fax and we may get back to you. Remember that once the situation starts touching Federal territory, that's when you step in.<br><br>Remember that while you may lawfully request station records, observe detentions, trials and security procedures, speak with crew regarding complaints, report findings to CC and Federal authority, declare an incident under federal review consideration, and request preservation of evidence during ongoing incidents, you CANNOT issue orders to station personnel, override Captain or Security authority, alter sentences or release prisoners, obstruct active operations, assume command of station departments, or enforce Corporate Law directly. That is the station crew's job, not yours. If you overstep, we are holding you accountable. We are professionalsm, and we expect you to act so.<br><br><h2>Guide to Federal Procedure</h2><br><br>Say you find out and have concluded that a security officer or authority figure on station has potentially violated a fundemental civil right according to the Federal Declaration of Rights. Here is a good step-by-step faithful process on how to solve this, escalation being the last resort. You do not need to escalate steps further once the situation has been resolved:<br><br><b>1. Identify the violation.</b><br>- Inform the responsible party of the apparent violation.<br>- Request correction, explanation, and justification<br>- Hear their explanation<br><b>2. Issue a Formal Notice of Concern</b><br>- Inform the responsible party that the action appears inconsistent with federal law or protected rights.<br>- Give them an opportunity to rectify the issue<br><b>3. Declare the matter under Federal Review</b><br>- Formally state that the incident is now being documented as a potential federal rights violation. Include, where applicable, relevant evidence, witness statements, and any logs, all of which need to be preserved.<br><b>4. Formally notify station command</b></br>- Usually the Captain, or Acting Captain.<br>- Inform them that a federal review has been initated and explain why.<br><b>5. Escalate externally</b><br>- Should the matter remain unsolved and you conclude that station command has failed to rectify the situation, forward your findings to Federal authorities via Fax and/or Central Command. <b><u>PLEASE STAMP AND SIGN YOUR DOCUMENT FOR VERIFICATION</u></b><br><br>If you have escalated all the way to Step 5, your authority stops here. While your local Federal office is reviewing your findings, you are to monitor the situation. Remember that you are not part of the station crew, nor do you have command authority. The Federal office will decide what happens next. Under no circumstances are you allowed to take Federal law into your own hands."

/obj/item/paper/solfed_rep_guide3
	name = "FEDERAL DECLARATION OF RIGHTS"
	default_raw_text = "All citizens of the Federation have the innate and inviolable right to freedom of speech, the right to vote, the right to freedom of religion and conscience, the right to peaceful assembly, the right to petition the government for redress of grievances, the right to due process of law, the right to equal protection under the law, the right to be secure in their persons, homes, papers, and effects against unreasonable searches and seizures, and the right to life, liberty, and property, which shall not be deprived except by due process of law.<br><br>On nanotrasen stations, these rights remain applicable to all persons under Federation jurisdiction unless lawfully restricted under:<br>- Valid criminal procedure<br>- Emergency statute<br>- and/or Authorized detention conditions.<br><br>Your role is to identify potential violations, including but not limited to:<br>- Denial of charges or explanation of arrest,<br>- Unlawful detention, or unlawful detention duration or conditions,<br>- Arbitrary searches without justification<br>- Unequal or discriminatory enforcement<br>- Suppression of complaints, testimony, or free speech<br>- Extrajudicial punishment or execution<br>- Excessive security force<br>- Unauthorised use of non-lethal and/or lethal force.<br>- Abuse of corporate authority that includes violating these rights<br><br>You do not determine guilt, you determine whether rights were respected."

/obj/item/paper/civil_rights
	name = "FEDERAL DECLARATION OF RIGHTS"
	default_raw_text = "All citizens of the Federation have the innate and inviolable right to:<br>- Freedom of speech<br>- Right to Vote<br>- Freedom of religion and conscience<br>- Peaceful assembly<br>- Petition the government for refress of grievances<br>- Due process of law<br>- Equal protection under the law<br>- Be secure in their persons, homes, papers, and effects against unreasonable searches and seizures<br>- Life, liberty, and property, which shall not be deprived except by due process of law.<br><br>On nanotrasen stations, these rights remain applicable to all persons under Federation jurisdiction unless lawfully restricted under:<br>- Valid criminal procedure<br>- Emergency statute<br>- and/or Authorized detention conditions."

/obj/item/paper/solfed_command_notice
	name = "SolFed Presence Notice"
	default_raw_text = "<center><h2>Central Command Notice</h2><br><br><h3>SUBJECT: SOL FEDERATION REPRESENTATIVE</center></h3><hr><br>To: Station Command<br><br>Our Consultant role has been replaced by an appointed Sol Federation Representative following federal review and legal action.<br><br>The Representative is an independent federal observer and liaison, not part of station command, Security, or corporate legal structure. Their function is to monitor compliance with federal rights protections and maintain an external record of station legal and security proceedings.<br><br>They granted necessary access rights equivalent to the former Consultant role under existing agreements and are to be treated as protected federal personnel. They do not issue operational orders and do not replace station command authority.<br><br>The Representative serves as an observer and escalation channel only. They are permitted within the brige, security, and given limited access to departments. Their official purpose is to ensure that station command and security personnel enforce basic federal civil rights and that all actions are in accordance with federal law.<br><br>In the event of operational conflict with this individual, de-escalate and contact Central Command if needed.<br><br>"

/obj/item/paper/notice_to_lawyers
	name = "CC Legal Email Copy"
	default_raw_text = "<code><b>From:</b> CC Legal Department<br><b>To:</b> Station Lawyer's Office<br><b>Subject:</b> Feds on board<hr><br>Hey,<br><br>Just so you know, you now have a Fed stationed with you. Pretty sure they're called the \"Sol Federation Representative\" or something similar. They've replaced the old consultant role.<br><br>They're basically federal-side legal oversight, while you're corporate-side legal representation. Different frameworks, but there's overlap in what you're both trying to do, like fair processing, proper detention handling, correct charges, that kind of thing.<br><br>You're not under their authority, and they're not under yours, but in practice you'll both be looking at the same arrests and Security decisions from different angles. When handled properly, that overlap actually works in everyone's favour.<br><br>Cooperation is recommended where it makes sense. If both sides are on the same pagee, it will make both your lives easier.<br><br>If disagreements do come up, document them normally and escalate through us if things get worse.<br><br>- CC Legal"

/obj/item/pen/fountain/solfed
	name = "solfed fountain pen"
	desc = "It's an expensive fountain pen."
	icon = 'modular_nova/master_files/icons/obj/bureaucracy.dmi'
	icon_state = "pen-fountain-nt"
	colour = "#5f1414"
	custom_materials = list(/datum/material/gold = SMALL_MATERIAL_AMOUNT*7.5)
