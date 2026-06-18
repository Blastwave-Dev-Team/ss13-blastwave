GLOBAL_LIST_INIT(first_names_male_vulp, world.file2list("modular_nova/modules/customization/strings/names/first_male_vulp.txt"))
GLOBAL_LIST_INIT(first_names_female_vulp, world.file2list("modular_nova/modules/customization/strings/names/first_female_vulp.txt"))
GLOBAL_LIST_INIT(last_names_vulp, world.file2list("modular_nova/modules/customization/strings/names/last_vulp.txt"))
GLOBAL_LIST_INIT(first_names_male_taj, world.file2list("modular_nova/modules/customization/strings/names/first_male_taj.txt"))
GLOBAL_LIST_INIT(first_names_female_taj, world.file2list("modular_nova/modules/customization/strings/names/first_female_taj.txt"))
GLOBAL_LIST_INIT(last_names_taj, world.file2list("modular_nova/modules/customization/strings/names/last_taj.txt"))
GLOBAL_LIST_INIT(callsigns_nri, world.file2list("modular_nova/modules/customization/strings/names/callsigns_nri.txt"))

/// Loads a rachnid name file, falling back to an inline list if the txt is missing at runtime.
/// Regenerate the txt files with modular_nova/modules/customization/tools/generate-rachnid-names.sh
/proc/load_rachnid_name_list(filename)
	. = world.file2list(filename)
	if(length(.))
		return
	if(findtext(filename, "first"))
		return list(
			"Zerzir", "Lalnuth", "Avisreb", "Qeqarnai", "Rhikkiezhith", "Necaqtex", "Aqi", "Shozhish",
			"Sraiza", "Ranqu", "Zellalshi", "Necoq", "Zaqod", "Salaree", "Xavis", "Cheqirni", "Nieqi",
			"Cakirkix", "Ivad", "Shenqazhe", "Azurte", "Lizire", "Ivur", "Kavur", "Raicheca", "Iqashe",
			"Eq'za", "Sak'sad", "Hiezih", "Cessix",
		)
	return list(
		"Ik'sir", "Sechathi", "Qok'sut", "Yeqied", "Iravhoh", "Kriaqux", "Yikih", "Khaqa", "Azasnet",
		"Qhecid", "Qhin'qu", "Zhechikzor", "Qhovi", "Hirath", "Szornud", "Zasokaq", "Lhaqish", "Qhiretid",
		"Avizad", "Qallazi", "Qhizrud", "Qicirne", "Sezuveth", "Zelriker", "Rhiallor", "Zhaliesh",
		"Qoutirk'ab", "Chavi", "Riel'shes", "Khentax",
	)

GLOBAL_LIST_INIT(rachnid_first_names, load_rachnid_name_list("modular_nova/modules/customization/strings/names/rachnid_first.txt"))
GLOBAL_LIST_INIT(rachnid_last_names, load_rachnid_name_list("modular_nova/modules/customization/strings/names/rachnid_last.txt"))
GLOBAL_LIST_INIT(phonetic_alphabet_numbers, world.file2list("modular_nova/modules/customization/strings/names/phonetic_alphabet_numbers.txt"))
