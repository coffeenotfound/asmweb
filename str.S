
.section .text


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


# in rdi	-- haystack_strz_ptr
# in rsi	-- needle_strz_ptr
str_sfind_zz:
	# TODO


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

