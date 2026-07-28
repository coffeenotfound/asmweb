.intel_syntax noprefix


#define STR_AND_LEN(name, str) \
	name: .ascii str; \
	name##_len = . - name;


# common symbols
SYS_EXIT = 60
SYS_READ = 0
SYS_WRITE = 1
SYS_SOCKET = 41
SYS_SETSOCKOPT = 54
SYS_BIND = 49
SYS_LISTEN = 50
SYS_ACCEPT = 43

AF_INET = 2
SOCK_STREAM = 1
IPPROTO_TCP = 6
SOL_SOCKET = 1
SO_REUSEADDR = 2



# https://filippo.io/linux-syscall-table/
# https://man7.org/linux/man-pages/man2/syscall.2.html#NOTES


# preserved: 	rbx, rsp, rbp, r12, r13, r14, r15
# scratch:		rax, rdi, rsi, rdx, rcx, r8, r9, r10, r11
# syscall params	rax (syscall nr), di, si, dx, r10, r8, r9



.section .rodata
STR_AND_LEN(msg_hello, "Hello! Accepting connections now...\n")
STR_AND_LEN(msg_die, "a syscall failed, dying now\n")
STR_AND_LEN(test_resp, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")


.section .data
g_socket_fd:		.int 0
g_peer_socket_fd:	.int 0

read_buf_size = 2048
g_read_buf:			.space read_buf_size, 0


.section .text
.global _start
_start:
	# print message
	mov rsi, offset msg_hello
	mov rdx, msg_hello_len
	call print_n
	
	# create socket
	call create_server_socket

_accept_loop:
	# accept syscall
	sub rsp, (16 + 4)
	mov rax, SYS_ACCEPT
	mov edi, [g_socket_fd]
	lea rsi, [rsp]
	lea rdx, [rsp + 16]
	syscall
	add rsp, (16 + 4)
	
	# check if valid
	cmp rax, 0
	jl _accept_loop
	mov [g_peer_socket_fd], eax
	
	# read from socket
	mov rax, SYS_READ
	mov edi, [g_peer_socket_fd]
	lea rsi, [g_read_buf]
	mov rdx, read_buf_size
	syscall
	mov r11, rax
	call syscall_fail
	
	# write same data back to socket
	mov rax, SYS_WRITE
	mov edi, [g_peer_socket_fd]
	# lea rsi, [g_read_buf]
	# mov rdx, r11
	mov rsi, offset test_resp
	mov rdx, test_resp_len
	syscall
	call syscall_fail
	
	jmp _accept_loop;
	
	# exit(0)
	xor rdi, rdi
	call exit_with_code


# in rdi -- exit code
exit_with_code:
	# exit(rdi)
	mov rax, SYS_EXIT
	syscall


# dies if rax is < 0 (syscall failure)
syscall_fail:
	cmp rax, 0
	jl _die
	ret
_die:
	mov rsi, offset msg_die
	mov rdx, msg_die_len
	call print_n
	mov rdi, 1
	call exit_with_code


create_server_socket:
	# create tcp socket
	mov rax, SYS_SOCKET
	mov rdi, AF_INET
	mov rsi, SOCK_STREAM
	mov rdx, IPPROTO_TCP
	syscall
	mov [g_socket_fd], eax
	call syscall_fail
	
	# allow quick reuse of the port
	mov rax, SYS_SETSOCKOPT
	mov edi, [g_socket_fd]
	mov rsi, SOL_SOCKET
	mov rdx, SO_REUSEADDR
	
	sub rsp, 4		# opt = alloca(u32)
	mov dword ptr [rsp], 1
	mov r10, rsp	# rdx = &opt
	
	mov r8, 4		# size of opt (4 bytes)
	syscall
	add rsp, 4		# freea(opt)
	call syscall_fail
	
	# construct local addr (sockaddr_in)
	sub rsp, 16		# sizeof(sockaddr_in) == 16
	mov word ptr [rsp + 0], AF_INET			# in host order
	mov word ptr [rsp + 2], 0x901F			# port 8080, in network order
	mov dword ptr [rsp + 4], 0x0100007F		# 127.0.0.1 in hex, in network order
	
	# bind socket to local addr
	mov rax, SYS_BIND
	mov edi, [g_socket_fd]
	mov rsi, rsp
	mov rdx, 16		# sizeof(sockaddr_in) == 16
	syscall
	add rsp, 16
	call syscall_fail
	
	# listen on the socket
	mov rax, SYS_LISTEN
	mov edi, [g_socket_fd]
	mov rsi, 256	# backlog of 256 connections (idk but seems sensible to me)
	syscall
	call syscall_fail
	
	ret


# in rsi -- string ptr
# in rdx -- string length
print_n:
	mov rax, SYS_WRITE
	mov rdi, 1		# fd = stdout
	syscall
	ret
