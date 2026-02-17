# cgahscroll

This is a demo game that's entirely vibecoded with OpenAI's Codex 5.2. 

## Context
I've always wanted to code a hardware-assisted CGA shooter game, since I was a kid. The idea is something like Gradius. That type of game only became popular with gaming consoles and EGA/VGA on PC's in the mid-80s. However I wanted to see if it is possible to run it on a 1981 IBM PC. However, the amount of time required to get anything reasonable was just too long so I abandoned the idea after a half-hearted attempt a few years ago.

Enter codex and vibecoding.

## What is this

This is supposed to be a horizontal scroll videogame. A space ship flys into a cavern. It avoids things shooting at it (aliens, asteroids) and can destroy them using a laser beam. The only way to do this on a IBM PC (which has a memory mapped video card, no graphics acceleration and just 500K instructions per second) is to use some hardware tricks. And I try to push the hardware as hard as possible.  I may change it to vertical scroll which should afford better performance and smoother scrolling because CGA can only hardware scroll 8 pixels at a time horizontally but can do 1 line vertically.


## Why are you doing this?
To level set: this is not to write a game, nor to learn assembly language. I know 8086 assembly language. 

The purpose of this project is to understand:

- what are common pitfalls of vibecoding agents.
- how do I move from coding to effective spec writing.
- can a 2026 codex llm write software in a 40 year old programming language
- how fast is the vibecoding loop
- what other tools are required to debug

The answers are:
- pitfalls: state preservation across instructions, ignores implicit knowledge in the langauge
- spec writing: there is a sweet spot between small and large chunks. Give the model enough rope to make rapid progress but not too much to destroy the program
- 2026 codex knows 1986 assembly? yes by and large it codes really well
- I am iterating in 10 minute increments for individual features. The most time is spent checking and debugging issues. The most time saved is in writing correct code and reduced checking how to do certain things ( e.g. no need to read reference documentation)
- Traditional debug tools still required - which means that the developer needs to know how to use them and the basics of the underlying language


