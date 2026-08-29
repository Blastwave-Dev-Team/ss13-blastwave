/// Checks that all automapper TOML entries actually link to a map and that the config exists.
/datum/unit_test/automapper
	var/config_path = "_maps/nova/automapper/automapper_config.toml"

/datum/unit_test/automapper/Run()
	var/test_config = rustg_read_toml_file(config_path)

	if(!test_config)
		TEST_FAIL("Automapper could not read/find TOML config [config_path]!")
		return

	for(var/template in test_config["templates"])
		var/selected_template = test_config["templates"][template]
		var/shuttle_id = selected_template["shuttle"]
		if(shuttle_id)
			TEST_ASSERT(SSmapping.shuttle_templates[shuttle_id], "[template] shuttle id [shuttle_id] is not a loaded shuttle template!")

		for(var/map in selected_template["map_files"])
			var/map_file = selected_template["directory"] + selected_template["map_files"][map]
			TEST_ASSERT(fexists(map_file), "[template] could not find map file [map_file]!") // Testing for map existence

		for(var/template_two in test_config["templates"]) // Testing for duplicate entries
			if(template_two == template)
				continue
			var/selected_template_two = test_config["templates"][template_two]
			if(selected_template["required_map"] != selected_template_two["required_map"])
				continue
			TEST_ASSERT_NOTEQUAL(selected_template["coordinates"], selected_template_two["coordinates"], "Automap template [template] had the same coords as [template_two] on [selected_template["required_map"]]!")
			if(selected_template["map_files"] && selected_template_two["map_files"])
				TEST_ASSERT_NOTEQUAL(selected_template["map_files"], selected_template_two["map_files"], "Automap template [template] had the same map files as [template_two]!")
