class_name MoonData
extends RefCounted
## Mean orbital elements of the major moons at J2000 (JPL Planetary Satellite Mean Elements,
## epoch 2000-01-01 12:00 TDB, ssd.jpl.nasa.gov/sats/elem).
##
## Angles in degrees. "omega" is the argument of periapsis, "M" the mean anomaly, "i" the
## inclination and "node" the ascending node, all relative to a reference plane: the ecliptic
## for the Moon (no "pole_ra"), or the satellite's local Laplace plane, whose pole is given by
## "pole_ra"/"pole_dec" (J2000 equatorial). "period_days" is the orbital period and
## "papsis_years"/"pnode_years" the apsidal and nodal precession periods (0 = none).
##
## Uranus's and Neptune's moons are referred to their planet's equator ("pole_ra"/"pole_dec" are the
## planet's spin pole; for Uranus that is the pole the moons orbit around, i.e. opposite the IAU
## "north" used for its tilt) except Nereid, which uses the ecliptic and an epoch of 2020-01-01.
## Triton orbits retrograde (inclination 157 degrees). Triton and Proteus use their observed
## sidereal periods in place of the rounded values in the JPL table.
##
## "radius" and "color" are for drawing only (the radius is exaggerated).

const MOONS: Array[Dictionary] = [
	{
		"name": "Moon", "planet": "Earth",
		"a_km": 384400.0, "e": 0.0554, "omega": 318.15, "M": 135.27, "i": 5.16, "node": 125.08,
		"period_days": 27.322, "papsis_years": 5.997, "pnode_years": 18.600,
		"radius": 0.55, "color": Color(0.72, 0.71, 0.69),
	},
	{
		"name": "Io", "planet": "Jupiter",
		"a_km": 421800.0, "e": 0.004, "omega": 49.1, "M": 330.9, "i": 0.0, "node": 0.0,
		"period_days": 1.762732, "papsis_years": 1.333, "pnode_years": 0.0,
		"pole_ra": 268.1, "pole_dec": 64.5,
		"radius": 0.55, "color": Color(0.92, 0.8, 0.3),
	},
	{
		"name": "Europa", "planet": "Jupiter",
		"a_km": 671100.0, "e": 0.009, "omega": 45.0, "M": 345.4, "i": 0.5, "node": 184.0,
		"period_days": 3.525463, "papsis_years": 1.394, "pnode_years": 30.202,
		"pole_ra": 268.1, "pole_dec": 64.5,
		"radius": 0.5, "color": Color(0.86, 0.82, 0.74),
	},
	{
		"name": "Ganymede", "planet": "Jupiter",
		"a_km": 1070400.0, "e": 0.001, "omega": 198.3, "M": 324.8, "i": 0.2, "node": 58.5,
		"period_days": 7.155588, "papsis_years": 68.301, "pnode_years": 137.812,
		"pole_ra": 268.2, "pole_dec": 64.6,
		"radius": 0.7, "color": Color(0.6, 0.55, 0.5),
	},
	{
		"name": "Callisto", "planet": "Jupiter",
		"a_km": 1882700.0, "e": 0.007, "omega": 43.8, "M": 87.4, "i": 0.3, "node": 309.1,
		"period_days": 16.690440, "papsis_years": 277.921, "pnode_years": 577.264,
		"pole_ra": 268.7, "pole_dec": 64.8,
		"radius": 0.65, "color": Color(0.42, 0.37, 0.33),
	},
	{
		"name": "Mimas", "planet": "Saturn",
		"a_km": 186000.0, "e": 0.020, "omega": 160.4, "M": 275.3, "i": 1.6, "node": 66.2,
		"period_days": 0.942422, "papsis_years": 0.493, "pnode_years": 0.986,
		"pole_ra": 40.6, "pole_dec": 83.5,
		"radius": 0.22, "color": Color(0.75, 0.75, 0.75),
	},
	{
		"name": "Enceladus", "planet": "Saturn",
		"a_km": 238400.0, "e": 0.005, "omega": 119.5, "M": 57.0, "i": 0.0, "node": 0.0,
		"period_days": 1.370218, "papsis_years": 2.916, "pnode_years": 0.0,
		"pole_ra": 40.6, "pole_dec": 83.5,
		"radius": 0.25, "color": Color(0.95, 0.97, 1.0),
	},
	{
		"name": "Tethys", "planet": "Saturn",
		"a_km": 295000.0, "e": 0.001, "omega": 335.3, "M": 0.0, "i": 1.1, "node": 273.0,
		"period_days": 1.887802, "papsis_years": 0.005, "pnode_years": 4.982,
		"pole_ra": 40.6, "pole_dec": 83.5,
		"radius": 0.35, "color": Color(0.86, 0.86, 0.85),
	},
	{
		"name": "Dione", "planet": "Saturn",
		"a_km": 377700.0, "e": 0.002, "omega": 116.0, "M": 212.0, "i": 0.0, "node": 0.0,
		"period_days": 2.736916, "papsis_years": 11.698, "pnode_years": 0.0,
		"pole_ra": 40.6, "pole_dec": 83.5,
		"radius": 0.35, "color": Color(0.8, 0.8, 0.78),
	},
	{
		"name": "Rhea", "planet": "Saturn",
		"a_km": 527200.0, "e": 0.001, "omega": 44.3, "M": 31.5, "i": 0.3, "node": 133.7,
		"period_days": 4.517503, "papsis_years": 33.939, "pnode_years": 35.775,
		"pole_ra": 40.6, "pole_dec": 83.5,
		"radius": 0.42, "color": Color(0.78, 0.77, 0.75),
	},
	{
		"name": "Titan", "planet": "Saturn",
		"a_km": 1221900.0, "e": 0.029, "omega": 78.3, "M": 11.7, "i": 0.3, "node": 78.6,
		"period_days": 15.945448, "papsis_years": 346.680, "pnode_years": 687.370,
		"pole_ra": 36.4, "pole_dec": 84.0,
		"radius": 0.7, "color": Color(0.86, 0.6, 0.26),
	},
	{
		"name": "Iapetus", "planet": "Saturn",
		"a_km": 3561700.0, "e": 0.028, "omega": 254.5, "M": 74.8, "i": 7.6, "node": 86.5,
		"period_days": 79.331002, "papsis_years": 1662.900, "pnode_years": 3130.302,
		"pole_ra": 288.7, "pole_dec": 78.9,
		"radius": 0.42, "color": Color(0.6, 0.55, 0.5),
	},
	{
		"name": "Miranda", "planet": "Uranus",
		"a_km": 129846.0, "e": 0.001, "omega": 154.8, "M": 73.0, "i": 4.4, "node": 100.9,
		"period_days": 1.413479, "papsis_years": 8.939, "pnode_years": 17.787,
		"pole_ra": 77.311, "pole_dec": 15.175,
		"radius": 0.2, "color": Color(0.75, 0.75, 0.78),
	},
	{
		"name": "Ariel", "planet": "Uranus",
		"a_km": 190929.0, "e": 0.001, "omega": 9.6, "M": 193.5, "i": 0.0, "node": 0.0,
		"period_days": 2.520379, "papsis_years": 28.901, "pnode_years": 0.0,
		"pole_ra": 77.311, "pole_dec": 15.175,
		"radius": 0.3, "color": Color(0.8, 0.8, 0.82),
	},
	{
		"name": "Umbriel", "planet": "Uranus",
		"a_km": 265986.0, "e": 0.004, "omega": 183.4, "M": 253.0, "i": 0.1, "node": 174.8,
		"period_days": 4.144177, "papsis_years": 64.126, "pnode_years": 129.945,
		"pole_ra": 77.311, "pole_dec": 15.175,
		"radius": 0.3, "color": Color(0.45, 0.45, 0.47),
	},
	{
		"name": "Titania", "planet": "Uranus",
		"a_km": 436298.0, "e": 0.002, "omega": 184.0, "M": 68.1, "i": 0.1, "node": 29.5,
		"period_days": 8.705869, "papsis_years": 579.928, "pnode_years": 1644.649,
		"pole_ra": 77.311, "pole_dec": 15.175,
		"radius": 0.4, "color": Color(0.7, 0.66, 0.62),
	},
	{
		"name": "Oberon", "planet": "Uranus",
		"a_km": 583511.0, "e": 0.002, "omega": 132.2, "M": 143.6, "i": 0.1, "node": 76.8,
		"period_days": 13.463237, "papsis_years": 158.604, "pnode_years": 192.798,
		"pole_ra": 77.311, "pole_dec": 15.175,
		"radius": 0.4, "color": Color(0.6, 0.55, 0.52),
	},
	{
		"name": "Triton", "planet": "Neptune",
		"a_km": 354800.0, "e": 0.0, "omega": 0.0, "M": 63.0, "i": 157.3, "node": 177.7,
		"period_days": 5.876854, "papsis_years": 675.2, "pnode_years": 299.4,
		"pole_ra": 299.36, "pole_dec": 43.46,
		"radius": 0.6, "color": Color(0.9, 0.82, 0.78),
	},
	{
		"name": "Proteus", "planet": "Neptune",
		"a_km": 117700.0, "e": 0.001, "omega": 357.2, "M": 297.4, "i": 0.6, "node": 355.5,
		"period_days": 1.122315, "papsis_years": 6.5, "pnode_years": 13.1,
		"pole_ra": 299.36, "pole_dec": 43.46,
		"radius": 0.3, "color": Color(0.45, 0.43, 0.42),
	},
	{
		"name": "Nereid", "planet": "Neptune",
		"a_km": 5513900.0, "e": 0.751, "omega": 296.8, "M": 318.5, "i": 5.1, "node": 319.5,
		"period_days": 360.133039, "papsis_years": 7990.433, "pnode_years": 9426.334,
		"epoch_days": 7304.5,
		"radius": 0.25, "color": Color(0.7, 0.7, 0.72),
	},
]
