.intel_syntax noprefix



# preserved: 	rbx, rsp, rbp, r12, r13, r14, r15
# scratch:		rax, rdi, rsi, rdx, rcx, r8, r9, r10, r11



.section .rodata
mystr: .ascii "Hello World\n"
mystr_len = . - mystr



.section .text
.global _start
_start:
	# print message
	mov rsi, offset mystr
	mov rdx, mystr_len
	call print
	
	# exit(0)
	mov rax, 60
	xor rdi, rdi
	syscall


# in rsi -- string ptr
# in rdx -- string length
print:
	mov eax, 1		# sys_write
	mov rdi, 1		# fd = standard out
	syscall
	ret
