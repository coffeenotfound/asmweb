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
SYS_CLOSE = 3
SYS_OPEN = 2
SYS_GETDENTS64 = 217

O_RDONLY = 0x0	# kinda useless but heck, why not
O_DIRECTORY = 0x10000
DT_REG = 8
DT_DIR = 4

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
# syscall clobbers: rax, rcx, r11


.section .rodata
STR_AND_LEN(msg_hello, "Hello! Accepting connections now...\n")
STR_AND_LEN(msg_die, "a syscall failed, dying now\n")
STR_AND_LEN(test_resp, "HTTP/1.1 200 OK\r\nContent-Length: 47\r\n\r\n<!DOCTYPE html><html><body>hello!</body></html>\r\n")

STR_AND_LEN(default_resp_headers, "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n<!DOCTYPE html><html><body>")

STR_AND_LEN(str_path_single_slash, "/")
STR_AND_LEN(str_path_index_html, "/index.html")

data_dir_pathz: .asciz "data"



.section .data
g_socket_fd:		.int 0
g_peer_socket_fd:	.int 0
g_data_dir_fd: 		.int 0

req_read_buf_size = 4096
g_req_read_buf:			.space req_read_buf_size, 0
g_req_bytes_read: 		.quad 0
g_req_status_line_len: 	.quad 0
g_req_path_offset: 		.quad 0
g_req_path_len: 		.quad 0
g_req_path_ptr: 		.quad 0

getdents_buf_size = 4096
g_getdents_buf:			.space getdents_buf_size, 0

intfmt_buf_len = 24
g_intfmt_buf:			.space intfmt_buf_len, 0
g_intfmt_ptrz:			.quad 0


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
	# clear connection state
	mov qword ptr [g_req_bytes_read], 0
	
	# accept syscall
	sub rsp, (16 + 4)		# alloca(sockaddr, sockaddr_len)
	mov rax, SYS_ACCEPT
	mov edi, [g_socket_fd]
	lea rsi, [rsp]
	lea rdx, [rsp + 16]
	syscall
	add rsp, (16 + 4)
	
	# ignore if invalid
	cmp rax, 0
	jl _accept_loop
	mov [g_peer_socket_fd], eax
	
	# process the request
	call process_request
	
	jmp _accept_loop
	
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
	
	xor rax, rax		# rax = -1
	dec rax				# .
	ret
	
_found_bit:
	add rax, r8			# ret cursor_offset + local_bit_idx
	ret


# string MUST be null terminated!
# in rdi	-- str_ptr
# out rax	-- len of string (offset of first nul byte)
str_len:
	mov rdx, 0x00	# needle = 0x00
	xor rcx, rcx
	dec rcx			# str_len = u64::MAX
	jmp str_bfind


# Compare two strings with lengths
# in rdi	-- str_ptr1
# in rsi	-- str_ptr2
# in rcx	-- str_len1
# in rdx	-- str_len2
# out ZF	-- ZF=1 if equal
str_cmp_nn:
	// if len1 != len2, return unequal (ZF=0)
	cmp rcx, rdx
	jne _not_eq
	# compare rcx number of bytes at rdi & rsi
	cld		# clear DF -> loop forwards
	repe cmpsb
_not_eq:
	ret		# ret ZF set by cmpsb or the first cmp


# in r10	-- u64 to format
fmt_u64:
	# load ptr to upper (last byte is nul byte)
	lea r9, [offset g_intfmt_buf + intfmt_buf_len - 2]		# r9 = buf_cursor_ptr
_digit_loop:
	# Unsigned divide RDX:RAX by r/m64,
	# with result stored in RAX := Quotient, RDX := Remainder
	xor rdx, rdx
	mov rax, r10
	mov rbx, 10
	div rbx

	add rdx, '0'
	mov byte ptr [r9], dl
	
	dec r9
	mov r10, rax
	cmp r10, 0
	jnbe _digit_loop
	
	# store final int ptr
	mov [g_intfmt_ptrz], r9
	ret


process_request:
_read_loop:
	# read some bytes from socket
	mov r9, [g_req_bytes_read]		# r9 = bytes_read
	mov r10, req_read_buf_size		# r10 = buf_bytes_remaining
	sub r10, r9
	
	mov rax, SYS_READ
	mov edi, [g_peer_socket_fd]
	lea rsi, [g_req_read_buf + r9]		# start = g_read_buf + bytes_read
	mov rdx, r10						# size = buf_bytes_remaining
	syscall
	call syscall_fail
	add [g_req_bytes_read], rax		# g_req_bytes_read += sys_read bytes read
	
	# check if we have received a newline
	# (a little inefficiently by scanning the whole buf everytime)
	# we just ignore everything beyond the http status line
	lea rdi, [g_req_read_buf]
	mov rcx, [g_req_bytes_read]
	mov rdx, 13		# 13 = '\r'
	call str_bfind
	js _read_loop 	# if no \r found goto loop, else rax = offset of \r in read buffer
	
	mov [g_req_status_line_len], rax
	
	# -- extract url path
	# find beginning
	lea rdi, [g_req_read_buf]
	mov rcx, [g_req_status_line_len]
	mov rdx, 32		# 32 = ' '
	call str_bfind	# todo: handle error but we expect status lines to be formatted properly for now
	inc rax			# todo: assuming method and path are separated by a single space
	mov [g_req_path_offset], rax
	
	lea r8, [g_req_read_buf + rax]
	mov [g_req_path_ptr], r8		# g_req_path_ptr = g_req_read_buf + g_req_path_offset
	
	# todo: trim further potential whitespace
	# find end of path
	add rdi, rax
	sub rcx, rax
	call str_bfind	# todo: handle error but we expect status lines to be formatted properly for now
	mov [g_req_path_len], rax
	
	# -- route request
	# compare "/"
	mov rdi, [g_req_path_ptr]
	mov rsi, offset str_path_single_slash
	mov rcx, [g_req_path_len]
	mov rdx, str_path_single_slash_len
	call str_cmp_nn
	je _do_index_resp
	# compare "/index.html"
	mov rdi, [g_req_path_ptr]
	mov rsi, offset str_path_index_html
	mov rcx, [g_req_path_len]
	mov rdx, str_path_index_html_len
	call str_cmp_nn
	je _do_index_resp
	jmp _try_file_resp
	
_do_index_resp:
	call send_index_resp
	jmp _resp_done
_try_file_resp:
	call send_file_resp
	jmp _resp_done
	
_resp_done:
	# close the socket to end the http transaction
	mov rax, SYS_CLOSE
	mov edi, [g_peer_socket_fd]
	syscall
	call syscall_fail
	
	ret


dirent64_off_reclen = 8+8
dirent64_off_type = 8+8+2
dirent64_off_name = 8+8+2+1

send_index_resp:
	# -- walk files to serve
	# open data dir
	mov rax, SYS_OPEN
	mov rdi, offset data_dir_pathz
	mov rsi, (O_DIRECTORY | O_RDONLY)
	mov rdx, 0		# todo: (u)mode_t but no clue what this is needed for, most references don't even specify it...
	syscall
	call syscall_fail
	mov [g_data_dir_fd], eax
	
	# send response headers
	mov rax, SYS_WRITE
	mov edi, [g_peer_socket_fd]
	mov rsi, offset default_resp_headers
	mov rdx, default_resp_headers_len
	syscall
	call syscall_fail
	
_getdents_loop:	
	# loop over dir files
	mov rax, SYS_GETDENTS64
	mov edi, [g_data_dir_fd]
	mov rsi, offset g_getdents_buf
	mov rdx, getdents_buf_size
	syscall
	call syscall_fail
	jz _getdents_done
	
	mov r10, rax					# r10 = bytes_read
	mov r9, offset g_getdents_buf	# r9 = entry_cursor_ptr
_getdents_entry_loop:
	# ignore non-reg files
	mov al, byte ptr [r9 + dirent64_off_type] 	# al = entry->d_type
	cmp al, DT_REG
	jne _getdents_skip_entry
	
		# DEBUG: write same data back to socket
		lea rdi, [r9 + dirent64_off_name]
		call str_len
		mov rdx, rax
		
		mov rax, SYS_WRITE
		mov edi, [g_peer_socket_fd]
		lea rsi, [r9 + dirent64_off_name]
		# rdx is set above
		syscall
		call syscall_fail
_getdents_skip_entry:
	# incr cursor and check for end
	mov bx, word ptr [r9 + dirent64_off_reclen]		# read d_reclen
	add r9, rbx
	lea rax, [g_getdents_buf + r10]
	cmp r9, rax
	jb _getdents_entry_loop
	jmp _getdents_loop
	
_getdents_done:
	
	/*
	# DEBUG: write same data back to socket
	mov rax, SYS_WRITE
	mov edi, [g_peer_socket_fd]
	mov rsi, offset default_resp_headers
	mov rdx, default_resp_headers_len
	syscall
	call syscall_fail
	
	mov rax, SYS_WRITE
	mov edi, [g_peer_socket_fd]
	# lea rsi, [g_req_read_buf]
	# mov rdx, r9
	lea rsi, [g_req_read_buf]
	add rsi, [g_req_path_offset]
	mov rdx, [g_req_path_len]
	syscall
	call syscall_fail
	*/
	ret


send_file_resp:
	ret


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
	
	# mov word ptr [rsp + 2], 0x901F			# port 8080, in network order
	mov rax, 8080
	bswap eax
	shr eax, 16
	mov word ptr [rsp + 2], ax
	
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
