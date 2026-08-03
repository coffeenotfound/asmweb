.section .bss

intfmt_buf_len = 24
g_intfmt_buf:			.space intfmt_buf_len, 0
g_intfmt_ptrz:			.quad 0
g_intfmt_len:			.quad 0
g_intfmt_opt_mindigits:	.quad 0		# set to pad out leading zero digits if wanted, gets reset to 0 on each fmt_u64 call

bytesize_fmt_buf_len = 64
g_bytesize_fmt_buf:		.space bytesize_fmt_buf_len, 0
g_bytesize_fmt_len: 	.quad 0


.section .text

# in r10				-- u64 to format
# out g_intfmt_ptrz		-- ptr to formatted strz
fmt_u64:
	# load ptr to second last byte (last byte is nul byte)
	# since we write from the back to the front to get
	# the correct order of digits.
	# Then at the end set the ptr to point at the first digit
	# so the calling code can then use the formatted number str
	mov r9, offset g_intfmt_buf + intfmt_buf_len - 2		# r9 = buf_cursor_ptr
_digit_loop:
	# "Unsigned divide RDX:RAX by r/m64,
	# with result stored in RAX := Quotient, RDX := Remainder"
	# (https://www.felixcloutier.com/x86/div)
	xor rdx, rdx
	mov rax, r10
	mov rcx, 10
	div rcx
	
	add rdx, '0'
	mov byte ptr [r9], dl
	
	dec r9
	mov r10, rax
	cmp r10, 0
	jnbe _digit_loop
	
	# store formatted str ptr
	inc r9		# r9 points to the next (downwards) free byte, so the first byte of the string is r9+1
	mov [g_intfmt_ptrz], r9
	# store str len
	mov rax, (offset g_intfmt_buf + intfmt_buf_len - 1)	# len = buf_ptr + buf_len - 1 (null byte) - buf_cursor_ptr
	sub rax, r9
	mov [g_intfmt_len], rax
	
	# -- emit leading zeros if needed
	mov rax, [g_intfmt_opt_mindigits]
	
	mov rdi, intfmt_buf_len - 1		# cap mindigits to buf_len - 1
	cmp rax, rdi
	cmovg rax, rdi
	
	sub rax, [g_intfmt_len]			# zeros_to_emit = mindigits - fmt_len	
_lead_zeros_loop:
	cmp rax, 0
	jle _lead_zeros_done
	
	dec qword ptr [g_intfmt_ptrz]
	mov rdi, [g_intfmt_ptrz]
	mov byte ptr [rdi], '0'
	inc qword ptr [g_intfmt_len]
	dec rax
	
	jmp _lead_zeros_loop
	
_lead_zeros_done:
	mov qword ptr [g_intfmt_opt_mindigits], 0
	
	ret


# in r10	-- u64 byte size to format
fmt_byte_size:
	cmp r10, 1000
	jb _no_suffix
	
	mov rcx, 1000/10
	mov rsi, 'K'
	cmp r10, 1000000
	jb _with_suffix
	mov rcx, 1000000/10
	mov rsi, 'M'
	cmp r10, 1000000000
	jb _with_suffix
	mov rcx, 1000000000/10
	mov rsi, 'G'
	
_with_suffix:
	xor rdx, rdx
	mov rax, r10
	div rcx
	
	mov r10, rax
	call fmt_u64
	
	mov rax, [g_intfmt_len]
	mov r9, rax
	mov r8, rax
	dec r8
	MEM_COPY([g_intfmt_ptrz], offset g_bytesize_fmt_buf, r8)
	
	mov byte ptr [r8 + offset g_bytesize_fmt_buf], '.'
	
	mov rax, [g_intfmt_ptrz]
	mov rax, [rax + r8]
	mov byte ptr [r8 + 1 + offset g_bytesize_fmt_buf], al
	
	mov byte ptr [r8 + 2 + offset g_bytesize_fmt_buf], sil
	
	add r8, 3
	mov [g_bytesize_fmt_len], r8
	ret
	
_no_suffix:
	call fmt_u64
	MEM_COPY([g_intfmt_ptrz], offset g_bytesize_fmt_buf, [g_intfmt_len])
	mov rcx, [g_intfmt_len]
	mov [g_bytesize_fmt_len], rcx
	ret
