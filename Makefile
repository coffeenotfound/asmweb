
build:
	gcc -static -nostdlib -g -o server -I./src src/server.S

run: build
	./server

gdb: build
	gdb ./server
