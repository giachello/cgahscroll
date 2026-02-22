# AGENTS.md

This file is located at the repository root:

`/Users/giac/Coding/cgahscroll/AGENTS.md`

Use this file for agent-specific working instructions for this project.

Use Intel 8086 assembly instruction set. This means not using instructions that only work on newer processors. for example mov cx,[ax+offset] doesn't work; only BX can be used as a displacement. Also shl ax,3 doesn't work. it needs to be replaced with mov cl,3 shl ax,cl

