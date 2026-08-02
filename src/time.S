.section .data

# these are used by civil_from_days
tm_doy:	.quad 0
tm_m:	.quad 0
tm_d: 	.quad 0
tm_y:	.quad 0

# these are used by fmt_epoch_timestamp_secs
tm_sec:	.quad 0
tm_min:	.quad 0
tm_hour:.quad 0

tm_datetime_fmt_buf_size = 64
tm_datetime_fmt_buf: 	.space tm_datetime_fmt_buf_size, 0
tm_datetime_fmt_len:	.quad 0


.section .text


# in rdi	-- secs since epoch  (only positive is supported right now)
fmt_epoch_timestamp_secs:
	push r15
	push r14
	
	xor rdx, rdx
	mov rax, rdi
	mov rcx, 60
	div rcx
	mov [tm_sec], rdx
	
	xor rdx, rdx
	mov rcx, 60
	div rcx
	mov [tm_min], rdx
	
	xor rdx, rdx
	mov rcx, 24
	div rcx
	mov [tm_hour], rdx
	
	mov rdi, rax
	call civil_from_days
	
	mov r15, offset tm_datetime_fmt_buf
	
	# fmt year
	mov r10, [tm_y]
	call fmt_u64
	MEM_COPY([g_intfmt_ptrz], r15, [g_intfmt_len])
	add r15, [g_intfmt_len]
	
	# write '-'
	mov byte ptr [r15], '-'
	inc r15
	
	# fmt month
	mov r10, [tm_m]
	call fmt_u64
	MEM_COPY([g_intfmt_ptrz], r15, [g_intfmt_len])
	add r15, [g_intfmt_len]
	
	# write '-'
	mov byte ptr [r15], '-'
	inc r15
	
	# fmt day
	mov r10, [tm_d]
	call fmt_u64
	MEM_COPY([g_intfmt_ptrz], r15, [g_intfmt_len])
	add r15, [g_intfmt_len]
	
	# write ' '
	mov byte ptr [r15], ' '
	inc r15
	
	# fmt hour
	mov r10, [tm_hour]
	call fmt_u64
	MEM_COPY([g_intfmt_ptrz], r15, [g_intfmt_len])
	add r15, [g_intfmt_len]
	
	# write ':'
	mov byte ptr [r15], ':'
	inc r15
	
	# fmt mins
	mov r10, [tm_min]
	call fmt_u64
	MEM_COPY([g_intfmt_ptrz], r15, [g_intfmt_len])
	add r15, [g_intfmt_len]
	
	# calc len
	mov rax, r15
	sub rax, offset tm_datetime_fmt_buf
	mov [tm_datetime_fmt_len], rax
	
	pop r14
	pop r15
	ret


# implementation of Howard Hinnant's civil_from_days:
# https://howardhinnant.github.io/date_algorithms.html#civil_from_days
# 
# in rdi	-- days since epoch  (only positive is supported right now)
# (clobbers about every register known to man)
civil_from_days:
	push r15
	push r14
	push r12
	
	mov r15, rdi
	
	# r12 := <tmp>
	# r15 := z
	# r14 := era
	# r11 := doe
	# r10 := yoe
	# r9 := y
	# r8 := mp
	
	## z += 719468;
	add r15, 719468
	
	## const int era = (z >= 0 ? z : z - 146096) / 146097;
	# (we just assume the passed in time is always positive)
	xor rdx, rdx
	mov rax, r15
	mov rcx, 146097
	idiv ecx		# 32 bit divide is a little faster
	mov r14, rax
	
	## const unsigned doe = static_cast<unsigned>(z - era * 146097)
	mov r11, r15
	imul rax, r14, 146097
	sub r11, rax
	
	## const unsigned yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365; 
	mov r10, r11
	
	xor rdx, rdx	# doe/1460
	mov rax, r11
	mov rcx, 1460
	div ecx
	sub r10, rax
	
	xor rdx, rdx	# doe/36524
	mov rax, r11
	mov rcx, 36524
	div ecx
	add r10, rax
	
	xor rdx, rdx	# doe/146096
	mov rax, r11
	mov rcx, 146096
	div ecx
	sub r10, rax
	
	xor rdx, rdx	# / 365
	mov rax, r10
	mov rcx, 365
	div ecx
	mov r10, rax
	
	## const int y = static_cast<Int>(yoe) + era * 400
	mov r9, r10
	imul rax, r14, 400
	add r9, rax
	
	## const unsigned doy = doe - (365*yoe + yoe/4 - yoe/100);
	imul r12, r10, 365	# 365*yoe
	
	mov rax, r10	# yoe/4
	shr rax, 2
	add r12, rax
	
	xor rdx, rdx	# yoe/100
	mov rax, r10
	mov rcx, 100
	div ecx
	sub r12, rax
	
	mov rax, r11	# doe - (..)
	sub rax, r12
	mov [tm_doy], rax
	
	## const unsigned mp = (5*doy + 2)/153;
	# rax from just above
	lea rax, [rax * 4 + rax + 2]	# oh yeeee boyyy
	
	xor rdx, rdx
	mov rcx, 153
	div ecx
	mov r8, rax
	
	## const unsigned d = doy - (153*mp+2)/5 + 1;
	mov r12, [tm_doy]
	
	imul rax, r8, 153 	# 153*mp+2
	add rax, 2
	
	xor rdx, rdx	# / 5
	mov rcx, 5
	div ecx
	
	sub r12, rax
	inc r12
	mov [tm_d], r12
	
	## const unsigned m = mp < 10 ? mp+3 : mp-9;
	lea r12, [r8 + 3]	# m = mp + 3
	cmp r8, 10
	jb _d
		sub r12, 9+3
	_d:
	mov [tm_m], r12
	
	## y = y + (m <= 2)
	cmp r12, 2		# r12 (m) from above
	jnbe _e
		inc r9
	_e:
	mov [tm_y], r9
	
	pop r12
	pop r14
	pop r15
	ret
