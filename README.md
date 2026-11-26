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

then the simulator sends the prompt to devstral, which creates the proper path. The path is returned to the app, which then converts the results into the proper coordinates. This was an exercise in 
1. Installing a local LLM on my computer (and realizing that 32GB of RAM is not really enough...), and
2. Actually using the local LLM in a program.

https://github.com/user-attachments/assets/e8e38597-c830-48db-a750-4c5ec3a5769a

The app is 3D aware and can be rotated as the user desires.

### Textures
I had Claude create textures similar to planetary surfaces rather than use actual images. The goal of this program was not to have realistic-looking planets but see the orbital motions of the planets.

### Local AI Installation
I used instructions in the book _Build Applications with Local AI Models on a Mac_ for installing ollama and LLMs on my computer. 

There were two things of interest I found:
1. My Mac Mini has 32GB of RAM. That is just barely sufficient to run devstral:24b and Xcode and Godot IDE simultaneously (but sluggishly). (I tried a qwen LLM but it was even slower.) I later found out I don't have to run the model explicitly - ollama will run it via a call from the app. I had Claude add instructions to unload the model when the app closes to keep my system responsive.
2. Even though LLMs are fast for what they do, they are slow for a user waiting for a response. It takes noticeable time to get a flight route back from the LLM.
