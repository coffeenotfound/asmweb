.intel_syntax noprefix


#define STR_AND_LEN(name, str) \
	name: .ascii str; \
	name##_len = . - name;


# common symbols
SYS_EXIT = 60
SYS_WRITE = 1
SYS_SOCKET = 41

AF_INET = 2
SOCK_STREAM = 1
IPPROTO_TCP = 6


# preserved: 	rbx, rsp, rbp, r12, r13, r14, r15
# scratch:		rax, rdi, rsi, rdx, rcx, r8, r9, r10, r11

# syscall params	rax (syscall nr), rdi, rsi, rdx, r10, r8, r9


.section .rodata
STR_AND_LEN(msg_hello, "Hello! Accepting connections now...\n")
STR_AND_LEN(msg_die, "a syscall failed, dying now\n")


.section .text
.global _start
_start:
	# print message
	mov rsi, offset msg_hello
	mov rdx, msg_hello_len
	call print_n
	
	# create tcp socket
	mov rax, SYS_SOCKET
	mov rdi, AF_INET
	mov rsi, SOCK_STREAM
	mov rdx, IPPROTO_TCP
	syscall
	call syscall_fail
	
	
	
	# exit(0)
	xor rdi, rdi
	call exit_with_code


# in rdi -- exit code
exit_with_code:
	# exit(rdi)
	mov rax, SYS_EXIT
	xor rdi, rdi
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


# in rsi -- string ptr
# in rdx -- string length
print_n:
	mov rax, SYS_WRITE
	mov rdi, 1		# fd = stdout
	syscall
	ret
