# Makefile
CC=clang

all: main.c 
	$(CC) -o playmidi main.c -framework CoreFoundation -framework AudioToolbox -framework CoreMIDI

clean: 
	$(RM) playmidi