class_name PlanetData
extends RefCounted
## Orbital elements for the planets at the J2000 epoch (JPL "Keplerian elements for
## approximate positions", 1800-2050), plus the visual properties used to draw them.
##
## "radius_km" is the real equatorial radius; "w0"/"w_rate" (degrees, degrees/day) give the IAU
## prime meridian angle W = w0 + w_rate * days since J2000 (negative rate = retrograde spin).
## "pole_ra"/"pole_dec" give the planet's north pole (IAU J2000 equatorial, degrees), which sets its
## axial tilt and the ring plane. Angles are in degrees, distances in astronomical units (AU), periods in days.

## The Sun's north pole (IAU, J2000 equatorial, degrees).
const SUN_POLE_RA := 286.13
const SUN_POLE_DEC := 63.87
## Sun rotation (IAU): prime meridian angle W = W0 + rate * days since J2000.
const SUN_W0 := 84.176
const SUN_W_RATE := 14.1844

## Masses are relative to the Sun (Sun = 1).
const PLANETS: Array[Dictionary] = [
	{
		"name": "Mercury", "a": 0.38709927, "e": 0.20563593, "i": 7.00497902,
		"L": 252.25032350, "varpi": 77.45779628, "node": 48.33076593, "period": 87.969,
		"radius": 1.0, "color": Color(0.62, 0.58, 0.55),
		"radius_km": 2440, "w0": 329.5469, "w_rate": 6.1385025,
		"mass": 1.6601e-07,
		"pole_ra": 281.0103, "pole_dec": 61.4155,
	},
	{
		"name": "Venus", "a": 0.72333566, "e": 0.00677672, "i": 3.39467605,
		"L": 181.97909950, "varpi": 131.60246718, "node": 76.67984255, "period": 224.701,
		"radius": 1.6, "color": Color(0.90, 0.78, 0.52),
		"radius_km": 6052, "w0": 160.2, "w_rate": -1.4813688,
		"mass": 2.4478e-06,
		"pole_ra": 272.76, "pole_dec": 67.16,
	},
	{
		"name": "Earth", "a": 1.00000261, "e": 0.01671123, "i": -0.00001531,
		"L": 100.46457166, "varpi": 102.93768193, "node": 0.0, "period": 365.256,
		"radius": 1.7, "color": Color(0.22, 0.45, 0.85),
		"radius_km": 6378, "w0": 190.147, "w_rate": 360.9856235,
		"mass": 3.0404e-06,
		"pole_ra": 0.0, "pole_dec": 90.0,
	},
	{
		"name": "Mars", "a": 1.52371034, "e": 0.09339410, "i": 1.84969142,
		"L": -4.55343205, "varpi": -23.94362959, "node": 49.55953891, "period": 686.980,
		"radius": 1.3, "color": Color(0.80, 0.36, 0.20),
		"radius_km": 3396, "w0": 176.63, "w_rate": 350.89198226,
		"mass": 3.2272e-07,
		"pole_ra": 317.68143, "pole_dec": 52.8865,
	},
	{
		"name": "Jupiter", "a": 5.20288700, "e": 0.04838624, "i": 1.30439695,
		"L": 34.39644051, "varpi": 14.72847983, "node": 100.47390909, "period": 4332.589,
		"radius": 4.5, "color": Color(0.80, 0.68, 0.52),
		"radius_km": 71492, "w0": 284.95, "w_rate": 870.536,
		"mass": 0.00095479,
		"pole_ra": 268.056595, "pole_dec": 64.495303,
	},
	{
		"name": "Saturn", "a": 9.53667594, "e": 0.05386179, "i": 2.48599187,
		"L": 49.95424423, "varpi": 92.59887831, "node": 113.66242448, "period": 10759.22,
		"radius": 3.9, "color": Color(0.90, 0.82, 0.60), "rings": true,
		"radius_km": 60268, "w0": 38.9, "w_rate": 810.7939024,
		"mass": 0.00028588,
		"pole_ra": 40.589, "pole_dec": 83.537,
	},
	{
		"name": "Uranus", "a": 19.18916464, "e": 0.04725744, "i": 0.77263783,
		"L": 313.23810451, "varpi": 170.95427630, "node": 74.01692503, "period": 30685.4,
		"radius": 2.8, "color": Color(0.55, 0.82, 0.86),
		"radius_km": 25559, "w0": 203.81, "w_rate": -501.1600928,
		"mass": 4.3662e-05,
		"pole_ra": 257.311, "pole_dec": -15.175,
	},
	{
		"name": "Neptune", "a": 30.06992276, "e": 0.00859048, "i": 1.77004347,
		"L": -55.12002969, "varpi": 44.96476227, "node": 131.78422574, "period": 60189.0,
		"radius": 2.7, "color": Color(0.25, 0.38, 0.88),
		"radius_km": 24764, "w0": 253.18, "w_rate": 536.3128492,
		"mass": 5.1514e-05,
		"pole_ra": 299.36, "pole_dec": 43.46,
	},
	{
		"name": "Pluto", "a": 39.48211675, "e": 0.24882730, "i": 17.14001206,
		"L": 238.92903833, "varpi": 224.06891629, "node": 110.30393684, "period": 90560.0,
		"radius": 0.9, "color": Color(0.74, 0.65, 0.58),
		"radius_km": 1188, "w0": 302.695, "w_rate": 56.3625225,
		"mass": 6.5e-09,
		"pole_ra": 132.993, "pole_dec": -6.163,
	},
]
