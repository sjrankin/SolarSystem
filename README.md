# Solar System
Stuart Rankin/
November 2026

## Description
Godot program that shows the planets in the solar system revolve around the sun. Gravity wells are shown and time can be sped up to see the planetary motion better.

## Implementation
This app is implement in Godot for better graphics and to make it straightforward to port to other platforms. To date, only macOS has been tested. Claude was used to create the Godot scripts from my design.

### Local AI
On my local Mac, I installed ollama and devstral:24b. I then added a feature to the Solar System simulator to show flights between planets. To to that, the user enters a path, along the lines of
> fly from the Earth to Neptune with a flyby of Jupiter
then the simulator sends the prompt to devstral, which creates the proper path. The path is returned to the app, which then converts the results into the proper coordinates.
