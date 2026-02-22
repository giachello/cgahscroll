# Superfast - a completely vibecoded 8086 assembly code game (runs on the original IBM PC)

This is a demo game that's entirely vibecoded with OpenAI's Codex 5.2. 

It is written for the IBM PC in 8086 assembly language and requires nasm to assemble into a .COM file. The .COM can be run on emulators like 86Box and on original hardware with a CGA card and some EGA/VGA that are hardware compatible with it.

<img width="955" height="720" alt="Screenshot 2026-02-21 at 23 06 50" src="https://github.com/user-attachments/assets/74aae0bd-9701-455c-bd58-21db654898c6" />
<img width="959" height="724" alt="Screenshot 2026-02-21 at 23 08 34" src="https://github.com/user-attachments/assets/d7838a28-8829-4e23-918d-7a2672342b8d" />

## Context
I've always wanted to code a hardware-assisted CGA shooter game. The idea is something like Gradius. I wanted to see if it is possible to run it on a 1981 IBM PC. 

However, the work required to get anything working was just too long, so I abandoned it after a half-hearted attempt a few years ago.

Enter codex and vibecoding.

## What is this
This is a horizontal scroll videogame. A space ship flys into a cavern. It avoids things (aliens, asteroids) and can destroy them using a laser beam. 

The only way to do this on a IBM PC (which has a memory mapped video card, no graphics acceleration and just 500K-1M memory access instructions per second) is to use assembly and hardware tricks. Everything is vibecoded using VSCode and Codex, including the art and music using ChatGPT.


## Why are you doing this?
To level set: this is not about writing a game, or learn assembly language. 

The purpose of this project is to understand:

- what are common pitfalls of vibecoding agents.
- how do I move from coding to effective spec writing.
- can a 2026 codex llm write software in a 40 year old programming language
- how fast is the vibecoding loop
- what other tools are required to debug

## A few learnings
- pitfalls: state preservation across instructions, ignores implicit knowledge in the langauge
- spec writing: there is a sweet spot between small and large chunks. Give the model enough rope to make rapid progress but not too much to destroy the program
- 2026 codex knows 1986 assembly? yes by and large it codes really well
- I am iterating in 10 minute increments for individual features. The most time is spent checking and debugging issues. The most time saved is in writing correct code and reduced checking how to do certain things ( e.g. no need to read reference documentation)
- Traditional debug tools still required - which means that the developer needs to know how to use them and the basics of the underlying language

## Looking forward
I may change it to vertical scroll which should have better performance and smoother scrolling because CGA can only hardware scroll 8 pixels at a time horizontally but can do 1 line vertically.
