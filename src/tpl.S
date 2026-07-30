.section text

# in rdi	-- str_ptr
# in rcx	-- str_len
tpl_write_first:
	MEM_COPY(rdi, [g_tpl_buf_ptr], rcx)
	mov qword ptr [g_tpl_buf_written_bytes], rcx
	ret


# in rsi (r15)	-- search_str_ptr
# in rdi (r14)	-- replace_str_ptr
# in rcx (r13)	-- search_str_len
# in rdx (r12)	-- replace_str_len
tpl_subst:
	push r15
	push r14
	push r13
	push r12
	
	mov r15, rsi
	mov r14, rdi
	mov r13, rcx
	mov r12, rdx
	
	# find substring
	mov rdi, [g_tpl_buf_ptr]
	mov rsi, r15
	mov rcx, [g_tpl_buf_written_bytes]
	mov rdx, r13
	call str_sfind_nn
	
	# copy pre-match str
	MEM_COPY([g_tpl_buf_ptr], [g_tpl_buf_ptr_tmp], rax)
	# copy replace str
	mov r9, [g_tpl_buf_ptr_tmp]		# r9 = *g_tpl_buf_ptr_tmp + substr_offset
	add r9, rax
	MEM_COPY(r14, r9, r12)
	# copy post-match str
	mov r9, [g_tpl_buf_ptr]			# r9 = *g_tpl_buf_ptr + substr_offset + search_str_len
	add r9, rax
	add r9, r13
	mov r8, [g_tpl_buf_ptr_tmp]		# r8 = *g_tpl_buf_ptr_tmp + substr_offset + replace_str_len
	add r8, rax
	add r8, r12
	mov r10, [g_tpl_buf_written_bytes]	# r10 = *g_tpl_buf_written_bytes - substr_offset - search_str_len
	sub r10, rax
	sub r10, r13
	MEM_COPY(r9, r8, r10)
	
	sub [g_tpl_buf_written_bytes], r13
	add [g_tpl_buf_written_bytes], r12
	
	
	pop r12
	pop r13
	pop r14	
	pop r15
	
	
	# swap buffers
	mov r9, [g_tpl_buf_ptr]
	mov r8, [g_tpl_buf_ptr_tmp]
	mov [g_tpl_buf_ptr], r8
	mov [g_tpl_buf_ptr_tmp], r9
	
	
	ret
	
	