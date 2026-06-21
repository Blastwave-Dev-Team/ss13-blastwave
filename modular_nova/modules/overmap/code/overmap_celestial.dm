// MODULE ID: OVERMAP
// Celestial bodies: stars, planets, moons. These follow pre-computed
// Kepler orbits and exert gravitational pull on nearby ships.

/// Base celestial body type. Has mass, sphere of influence, and
/// optional Kepler orbital parameters.
/obj/structure/overmap/celestial
	name = "celestial body"
	desc = "A massive astronomical object."
	icon = 'modular_nova/modules/overmap/icons/overmap.dmi'
	icon_state = "object"
	anchored = TRUE
	density = TRUE

	/// Gravitational mass. Determines pull strength on ships within SOI.
	var/gravity_mass = 100
	/// Sphere of influence in pixels. Beyond this distance, gravity is ignored.
	var/sphere_of_influence = 96
	/// Cached SOI^2 to avoid sqrt in distance checks.
	var/soi_sq = 9216
	/// Weakref to the body this celestial orbits (null = fixed position).
	var/datum/weakref/orbital_parent
	/// Semi-major axis in pixels (orbital radius for circular orbits).
	var/semi_major_axis = 0
	/// Eccentricity: 0 = circle, 0..1 = ellipse.
	var/eccentricity = 0
	/// Orbital period in seconds for one full revolution.
	var/orbital_period = 600
	/// Starting phase angle in degrees.
	var/phase_offset = 0
	/// Cached: absolute pixel X of this body (for gravity calcs).
	var/px = 0
	/// Cached: absolute pixel Y of this body (for gravity calcs).
	var/py = 0

/obj/structure/overmap/celestial/Initialize(mapload)
	. = ..()
	soi_sq = sphere_of_influence * sphere_of_influence
	update_pixel_pos()
	SSovermap.gravity_wells |= src
	update_orbit_registration()

/obj/structure/overmap/celestial/Destroy()
	SSovermap.gravity_wells -= src
	STOP_PROCESSING(SSfastprocess, src)
	return ..()

/obj/structure/overmap/celestial/process(seconds_per_tick)
	update_orbit(world.time / (1 SECONDS))

/// Start or stop SSfastprocess ticks for Kepler orbit integration.
/obj/structure/overmap/celestial/proc/update_orbit_registration()
	if(orbital_parent)
		START_PROCESSING(SSfastprocess, src)
	else
		STOP_PROCESSING(SSfastprocess, src)

/// Assign an orbital parent and register for per-body orbit ticks.
/obj/structure/overmap/celestial/proc/set_orbital_parent(obj/structure/overmap/celestial/parent)
	orbital_parent = parent ? WEAKREF(parent) : null
	update_orbit_registration()

/// Sync cached pixel position from tile + fractional offset.
/obj/structure/overmap/celestial/proc/update_pixel_pos()
	px = get_overmap_abs_px()
	py = get_overmap_abs_py()

/// Update position from Kepler orbital parameters. Ticked by SSfastprocess
/// via `process()` when `orbital_parent` is set. Fixed bodies skip processing.
/obj/structure/overmap/celestial/proc/update_orbit(time_seconds)
	if(!orbital_parent)
		return
	var/obj/structure/overmap/celestial/parent = orbital_parent.resolve()
	if(!parent)
		orbital_parent = null
		update_orbit_registration()
		return

	var/mean_anomaly = ((time_seconds / orbital_period) * 360 + phase_offset)
	// Approximate eccentric anomaly via one Newton-Raphson step
	// (sufficient for low eccentricities typical in game)
	var/E = mean_anomaly + eccentricity * sin(mean_anomaly) * (180 / PI)
	var/true_anomaly = E

	var/radius = semi_major_axis * (1 - eccentricity * eccentricity) / (1 + eccentricity * cos(true_anomaly))
	var/orbit_x = parent.px + cos(true_anomaly) * radius
	var/orbit_y = parent.py + sin(true_anomaly) * radius

	// Convert absolute pixel position back to tile + step
	var/new_x = round(orbit_x / ICON_SIZE_ALL) + 1
	var/new_y = round(orbit_y / ICON_SIZE_ALL) + 1

	var/turf/dest = locate(new_x, new_y, z)
	if(!dest)
		return
	if(dest != loc)
		forceMove(dest)
	offset_x = (orbit_x - (new_x - 1) * ICON_SIZE_ALL) / ICON_SIZE_ALL
	offset_y = (orbit_y - (new_y - 1) * ICON_SIZE_ALL) / ICON_SIZE_ALL
	pixel_x = offset_x * ICON_SIZE_ALL
	pixel_y = offset_y * ICON_SIZE_ALL
	update_pixel_pos()

/// Compute escape velocity at a given distance from this body.
/obj/structure/overmap/celestial/proc/escape_velocity(distance)
	if(distance <= 0)
		return 999
	return sqrt(2 * gravity_mass / distance)

/// Compute required circular orbital velocity at a given distance.
/obj/structure/overmap/celestial/proc/orbital_velocity(distance)
	if(distance <= 0)
		return 999
	return sqrt(gravity_mass / distance)

// --- Concrete celestial subtypes ---

/obj/structure/overmap/celestial/star
	name = "Kepler 453"
	desc = "The binary star at the center of this stellar neighborhood."
	icon = 'modular_nova/modules/overmap/icons/overmap_large.dmi'
	icon_state = "kepler_453"
	opacity = TRUE
	pixel_x = -32
	pixel_y = -32
	gravity_mass = 500
	sphere_of_influence = 256

/obj/structure/overmap/celestial/planet
	name = "planet"
	desc = "A terrestrial body in orbit."
	icon_state = "globe"
	gravity_mass = 50
	sphere_of_influence = 128

/obj/structure/overmap/celestial/moon
	name = "moon"
	desc = "A small natural satellite."
	icon_state = "object"
	gravity_mass = 10
	sphere_of_influence = 64
