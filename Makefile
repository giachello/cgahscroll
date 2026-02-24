sfast.com: sfast.asm
	nasm -f bin sfast.asm -o sfast.com -l sfast.lst

.PHONY: clean
clean:
	rm -f sfast.com sfast.lst
