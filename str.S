
.section .text


# in rsi	-- src ptr
# in rdi	-- dst ptr
# in rcx	-- len
#define MEM_COPY(src, dst, len) \
	push rsi; \
	push rdi; \
	push rcx; \
	\
	mov rsi, src; \
	mov rdi, dst; \
	mov rcx, len; \
	\
	cld; /* clear DF -> loop forwards */  \
	rep movsb; \
	\
	pop rcx; \
	pop rdi; \
	pop rsi;


# NOTE: doesn't impl scalar tails, so make sure your buffer
#  has at least 32 bytes beginning at str_ptr
# in rdi	-- str ptr
# in rcx	-- str len
# in rdx	-- needle byte to find
# out rax	-- first found byte offset or -1
# out flags
#	- SF if not found
str_bfind:
	xor r8, r8					# cursor_offset
	vmovd xmm1, rdx
	vpbroadcastb ymm1, xmm1		# cmp_mask = broadcast(needle:rdx)
	
_chunk_loop:
	vmovups ymm0, [rdi + r8]
	vpcmpeqb ymm2, ymm0, ymm1
	vpmovmskb rax, ymm2
	bsf rax, rax		# sets ZF if src == 0
	jnz _found_bit
	
	add r8, 32			# ymm size
	cmp r8, rcx			# cmp(cursor_offset, str_len)
	jnae _chunk_loop
	
	mov rax, -1
	ret
	
_found_bit:
	add rax, r8			# ret cursor_offset + local_bit_idx
	ret


# Can read up to 31 bytes beyond the haystack
# (note: not very efficient at all!)
# in rdi	-- haystack_ptr
# in rsi	-- needle_ptr
# in rcx	-- haystack_len
# in rdx	-- needle_len
# out ZF	-- ZF=1 if substring found
str_sfind_nn:
	xor r8, r8					# cursor_offset
	vmovd xmm1, [rsi]			# cmp_mask = broadcast(needle[0])
	vpbroadcastb ymm1, xmm1		# |
	
_chunk_loop2:
	vmovups ymm0, [rdi + r8]
	vpcmpeqb ymm2, ymm0, ymm1
	vpmovmskb rax, ymm2
	
_local_bit_loop:
	bsf r9, rax		# r9 = local_bit_idx
	jz _end_curr_chunk
	blsr rax, rax		# unset lowest bit (local_bit_idx) in r9
	
	# push regs used by str_cmp_nn
	# (this is stupid, we should store our shit in preserved regs instead!!!)
	push rdi
	push rsi
	push rcx
	push rdx
	
	add rdi, r8
	add rdi, r9
	# mov rsi, rsi
	mov rcx, rdx
	# mov rdx, rdx
	call str_cmp_nn
	
	pop rdx
	pop rcx
	pop rsi
	pop rdi
	
	jnz _local_bit_loop		# ZF comes form call str_cmp_nn above (push doesn't affect flags)
	
	lea rax, [r8 + r9]
	ret						# out ZF comes from above -- will be ZF=1 if it survived the jnz

_end_curr_chunk:
	add r8, 32			# ymm size
	cmp r8, rcx			# cmp(cursor_offset, str_len)
	jnae _chunk_loop2
	
	mov rax, -1
	test rsp, rsp		# set ZF=0 (https://stackoverflow.com/questions/54499327/setting-and-clearing-the-zero-flag-in-x86)
	ret


# string MUST be null terminated!
# in rdi	-- str_ptr
# out rax	-- len of string (offset of first nul byte)
str_len:
	mov rdx, 0x00	# needle = 0x00
	mov rcx, -1		# str_len = u64::MAX
	jmp str_bfind


# Compare two strings with lengths
# in rdi	-- str_ptr1
# in rsi	-- str_ptr2
# in rcx	-- str_len1
# in rdx	-- str_len2
# out ZF	-- ZF=1 if equal
str_cmp_nn:
	# if_ len1 != len2, return unequal (ZF=0)
	cmp rcx, rdx
	jne _not_eq
	# compare rcx number of bytes at rdi & rsi
	cld		# clear DF -> loop forwards
	repe cmpsb
_not_eq:
	ret		# ret ZF set by cmpsb or the first cmp

