
build:
	gcc server.s -static -nostdlib -g -o server

run: build
	./server
