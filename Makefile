
build:
	gcc -static -nostdlib -g -o server server.S

run: build
	./server
