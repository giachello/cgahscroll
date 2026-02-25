# Superfast - a completely vibecoded 8086 assembly code game (including the clipart)

This is a demo game that's entirely vibecoded with OpenAI's Codex 5.2. 

I've always wanted to code a game like Gradius that would work on a 1981 IBM PC. That required coding it all in assembly and using lots of hardware tricks. However, the work required to get anything working was just too long, so I abandoned it after a half-hearted attempt a few years ago.

Enter OpenAI Codex and vibe coding. I wrote this in a few hours while watching TV.

It is written for the IBM PC in 8086 assembly language and runs on emulators like 86Box, DosBox and on original hardware (CGA/EGA/VGA required).

<img width="955" height="720" alt="Screenshot 2026-02-21 at 23 06 50" src="https://github.com/user-attachments/assets/74aae0bd-9701-455c-bd58-21db654898c6" />
<img width="959" height="724" alt="Screenshot 2026-02-21 at 23 08 34" src="https://github.com/user-attachments/assets/d7838a28-8829-4e23-918d-7a2672342b8d" />


## What is this
This is a horizontal scroll videogame. A space ship flys into a cavern. It avoids things (aliens, asteroids) and can destroy them using a laser beam. 

The only way to do this on a IBM PC (which has a memory mapped video card, no graphics acceleration and just 300-400K memory access instructions per second) is to use assembly and hardware tricks. Everything is vibecoded using VSCode and Codex, including the art and music using ChatGPT.

To run it, copy the repo, and use [nasm](https://www.nasm.us) to assemble into a .COM file.

## Why are you doing this?
This is not about writing a game, or learn assembly language. 

The purpose of this project is to understand:

- what are common pitfalls of vibecoding agents.
- how do I become proficient with agents? how do I move from coding to effective spec writing.
- can a 2026 LLM write software in a 40-50 year old programming language
- how fast is the vibecoding loop
- how effective is Codex at learning to develop and will it improve over time?
- what other tools are required (e.g., debug)

## A few learnings
- pitfalls: state preservation across instructions, ignores implicit knowledge in the langauge
- spec writing: there is a sweet spot between small and large chunks. Give the model enough rope to make rapid progress but not too much to destroy the program
- 2026 codex knows 1986 assembly? yes by and large it codes really well
- I am iterating in 10 minute increments for individual features. The most time is spent checking and debugging issues. The most time saved is in writing correct code and reduced checking how to do certain things ( e.g. no need to read reference documentation)
- Traditional debug tools still required - which means that the developer needs to know how to use them and the basics of the underlying language
- You can insist that the LLM check specific things and it will improve. For example, when trying to find a bug, I gave it increasingly specific instructions and typically it figures out the problem. 


