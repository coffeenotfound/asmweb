.intel_syntax noprefix


#define STR_AND_LEN(name, str) \
	name: .asciz str; \
	name##_len = . - name - 1;


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
SYS_FSTAT = 5

O_RDONLY = 0x0	# kinda useless but heck, why not
O_DIRECTORY = 0x10000
DT_REG = 8
DT_DIR = 4

# https://manpages.debian.org/testing/manpages/S_ISDIR.3.en.html
# (note, these are octal literals!)
S_IFMT = 0170000 	# bit mask for the file type bit field
S_IFREG = 0100000 	# regular file
S_IFDIR = 0040000 	# directory

AF_INET = 2
SOCK_STREAM = 1
IPPROTO_TCP = 6
SOL_SOCKET = 1
SO_REUSEADDR = 2

# struct stat layout on x86_64: https://github.com/torvalds/linux/blob/e05b559f9cda350d0ab33c44a8c1151ca62d2875/arch/x86/include/uapi/asm/stat.h#L83
OFFOF_STRUCT_STAT_st_mode = 24
SIZEOF_STRUCT_STAT = 144


# other source files to be included
# Note: We do this here instead of passing multiple
# files to gcc so that we have access to any
# helper macros/defines declared here
# (I guess I could also outsource them into helpers.h, but whatever :P)
#include "str.S"
#include "pbuf.S"
#include "tpl.S"



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
STR_AND_LEN(str_resp_headers_ok, "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
# not sending Content-Type seems to be enough for getting MIME sniffing in browsers to work
STR_AND_LEN(str_resp_headers_file_ok, "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Disposition:inline\r\n\r\n")
STR_AND_LEN(str_resp_headers_404, "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n")

STR_AND_LEN(str_path_single_slash, "/")
STR_AND_LEN(str_path_index_html, "/index.html")

STR_AND_LEN(data_dir_pathz, "./data")

html_index:
	#embed "../html/index.html" prefix(.byte ) suffix(, 0)
html_index_len = . - html_index

html_slot_indexfile:
	#embed "../html/slot_indexfile.html" prefix(.byte ) suffix(, 0)
html_slot_indexfile_len = . - html_slot_indexfile

STR_AND_LEN(STRZ_SLOT_INDEXFILE_NEXT, "<!--SLOT_INDEXFILE_NEXT-->")
STR_AND_LEN(STRZ_SLOT_INDEXFILE_PATH, "<!--SLOT_INDEXFILE_PATH-->")


STR_AND_LEN(STRZ_AAA, "aaa bb ccc")
STR_AND_LEN(STRZ_BBB, "bb")
STR_AND_LEN(STRZ_ZZZ, "111##!##!bb!##!##333")



.section .data
g_socket_fd:		.int 0
g_peer_socket_fd:	.int 0
g_data_dir_fd: 		.int 0
g_open_resp_file_fd:	.int 0

req_read_buf_size = 4096
g_req_read_buf:			.space req_read_buf_size, 0
g_req_bytes_read: 		.quad 0
g_req_status_line_len: 	.quad 0
g_req_path_offset: 		.quad 0
# url_path points into the req buf and is not nul-terminated
g_req_url_path_len: 		.quad 0
g_req_url_path_ptr: 		.quad 0
# data_path is assembled to be the actual requested file path ("data/<url_path>")
# and *is* nul-terminated
g_req_data_pathz_len: 		.quad 0
req_data_path_len = 2048
g_req_data_pathz_buf: 		.space req_data_path_len, 0

getdents_buf_size = 4096
g_getdents_buf:			.space getdents_buf_size, 0

resp_fsend_buf_size = 4094*8
g_resp_fsend_buf:		.space resp_fsend_buf_size, 0

intfmt_buf_len = 24
g_intfmt_buf:			.space intfmt_buf_len, 0
g_intfmt_ptrz:			.quad 0


# g_pbuf_
tpl_buf_mem_len = 0x100000
g_tpl_buf_mem_a:			.space tpl_buf_mem_len, 0
g_tpl_buf_mem_b:			.space tpl_buf_mem_len, 0
g_tpl_buf_ptr:				.quad 0
g_tpl_buf_ptr_tmp:			.quad 0
g_tpl_buf_written_bytes:	.quad 0



.section .text

.global _start
_start:
	# print message
	mov rsi, offset msg_hello
	mov rdx, msg_hello_len
	call print_n
	
	/*
	# DEBUG: test str_sfind_nn
	mov rdi, offset html_template
	mov rsi, offset STRZ_SLOT_INDEXFILE_NEXT
	mov rcx, html_template_len
	mov rdx, STRZ_SLOT_INDEXFILE_NEXT_len
	call str_sfind_nn
	*/
	
	# init tpl ptrs
	mov qword ptr [g_tpl_buf_ptr], offset g_tpl_buf_mem_a
	mov qword ptr [g_tpl_buf_ptr_tmp], offset g_tpl_buf_mem_b
	
	/*
	# DEBUG: Write initial tpl str
	MEM_COPY(offset STRZ_AAA, [g_tpl_buf_ptr], STRZ_AAA_len)
	mov qword ptr [g_tpl_buf_written_bytes], STRZ_AAA_len
	*/
	mov rsi, offset STRZ_AAA
	mov rcx, STRZ_AAA_len
	call tpl_write_first
	
	# DEBUG: test substitution
	# in rsi (r15)	-- search_str_ptr
	# in rdi (r14)	-- replace_str_ptr
	# in rcx (r13)	-- search_str_len
	# in rdx (r12)	-- replace_str_len
	mov rsi, offset STRZ_BBB
	mov rdi, offset STRZ_ZZZ
	mov rcx, STRZ_BBB_len
	mov rdx, STRZ_ZZZ_len
	call tpl_subst
	mov rsi, offset STRZ_BBB
	mov rdi, offset STRZ_ZZZ
	mov rcx, STRZ_BBB_len
	mov rdx, STRZ_ZZZ_len
	call tpl_subst
	
	
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


# in r10				-- u64 to format
# out g_intfmt_ptrz		-- ptr to formatted strz
fmt_u64:
	# load ptr to upper (last byte is nul byte)
	mov r9, offset g_intfmt_buf + intfmt_buf_len - 2		# r9 = buf_cursor_ptr
_digit_loop:
	# Unsigned divide RDX:RAX by r/m64,
	# with result stored in RAX := Quotient, RDX := Remainder
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
	call str_bfind	# todo: handle errors but we expect status lines to be formatted properly for now
	inc rax			# todo: assuming method and path are separated by a single space
	mov [g_req_path_offset], rax
	
	lea r8, [g_req_read_buf + rax]
	mov [g_req_url_path_ptr], r8		# g_req_path_ptr = g_req_read_buf + g_req_path_offset
	
	# todo: trim further potential whitespace
	# find end of path
	add rdi, rax
	sub rcx, rax
	call str_bfind	# todo: handle error but we expect status lines to be formatted properly for now
	mov [g_req_url_path_len], rax

	# -- build data file path from url path
	# essentially we just copy data_dir_path ("data")
	# and then the url path. Since the url path always has a
	# leading slash (i think? :D), that's automatically
	# the seperator between data dir and url path
	mov rdi, offset g_req_data_pathz_buf
	MEM_COPY(offset data_dir_pathz, rdi, data_dir_pathz_len)		# copy data_dir ("data")
	mov r8, data_dir_pathz_len
	add rdi, r8
	MEM_COPY([g_req_url_path_ptr], rdi, [g_req_url_path_len])		# copy url path
	add r8, [g_req_url_path_len]
	add rdi, [g_req_url_path_len]
	mov byte ptr [rdi], 0		# nul-terminate path
	mov [g_req_data_pathz_len], r8
	
	# -- try open path
	mov rax, SYS_OPEN
	mov rdi, offset g_req_data_pathz_buf
	mov rsi, O_RDONLY
	mov rdx, 0		# todo: (u)mode_t but no clue what this is needed for, most references don't even specify it...
	syscall
	cmp eax, 0
	jl _file_not_found
	mov dword ptr [g_open_resp_file_fd], eax
	
	# -- stat file to determine if its a folder
	sub rsp, SIZEOF_STRUCT_STAT		# alloc struct stat
	
	mov rax, SYS_FSTAT
	mov edi, [g_open_resp_file_fd]
	mov rsi, rsp
	syscall
	# todo: error handling
	
	mov r9d, dword ptr [rsp + OFFOF_STRUCT_STAT_st_mode]	# r9 = stat.st_mode
	add rsp, SIZEOF_STRUCT_STAT
	
	# check if its a folder
	and r9d, S_IFMT
	cmp r9d, S_IFDIR
	jz _as_folder
	cmp r9d, S_IFREG
	jz _as_file
	jmp _file_not_found
	
_as_folder:
	call send_folder_index_resp
	jmp _resp_done
_as_file:
	call send_file_resp
	jmp _resp_done
_file_not_found:
	# send 404 back
	mov rsi, offset str_resp_headers_404
	mov rdx, str_resp_headers_404_len
	call write_resp_str
	jmp _resp_done
	
	# -- route request
	/*
	# compare "/"
	mov rdi, [g_req_path_ptr]
	mov rsi, offset str_path_single_slash
	mov rcx, [g_req_path_len]
	mov rdx, str_path_single_slash_len
	call str_cmp_nn
	je _do_root_index_resp
	# compare "/index.html"
	mov rdi, [g_req_path_ptr]
	mov rsi, offset str_path_index_html
	mov rcx, [g_req_path_len]
	mov rdx, str_path_index_html_len
	call str_cmp_nn
	je _do_root_index_resp
	jmp _try_file_resp
	
_do_index_resp:
	call send_index_resp
	jmp _resp_done
_try_file_resp:
	call send_file_resp
	jmp _resp_done
	*/
	
_resp_done:
	# close the socket to end the http transaction
	mov rax, SYS_CLOSE
	mov edi, [g_peer_socket_fd]
	syscall
	call syscall_fail
	
	ret


send_file_resp:
	# send success headers
	# in rsi	-- str_ptr
	# in rdx	-- str_len (-1 for null-terminated)
	mov rsi, offset str_resp_headers_file_ok
	mov rdx, str_resp_headers_file_ok_len
	call write_resp_str
	
	# -- send file data back in chunks
_read_chunk_loop:	
	# read data from file
	mov rax, SYS_READ
	mov edi, [g_open_resp_file_fd]
	mov rsi, offset g_resp_fsend_buf
	mov rdx, resp_fsend_buf_size
	syscall
	cmp rax, 0
	jz _file_send_done		# 0 bytes -> end of file
	# todo: handle error
	
	mov r9, rax		# r9 = bytes left to send
	xor r8, r8		# r8 = send cursor
_write_chunk_loop:
	mov rax, SYS_WRITE
	mov edi, [g_peer_socket_fd]
	lea rsi, [r8 + offset g_resp_fsend_buf]
	mov rdx, r9
	syscall
	# todo: handle error
	add r8, rax
	sub r9, rax
	jnle _write_chunk_loop		# this chunk still has bytes, do write() again
	jmp _read_chunk_loop		# read next chunk
	
_file_send_done:
	# close file
	mov rax, SYS_CLOSE
	mov edi, [g_open_resp_file_fd]
	syscall
	call syscall_fail
	
	ret


dirent64_off_reclen = 8+8
dirent64_off_type = 8+8+2
dirent64_off_name = 8+8+2+1

send_folder_index_resp:
	# -- walk files to serve
	/*
	# open data dir
	mov rax, SYS_OPEN
	mov rdi, offset data_dir_pathz
	mov rsi, (O_DIRECTORY | O_RDONLY)
	mov rdx, 0		# todo: (u)mode_t but no clue what this is needed for, most references don't even specify it...
	syscall
	call syscall_fail
	mov [g_data_dir_fd], eax
	*/
	
	# start templating
	mov rsi, offset html_index
	mov rcx, html_index_len
	call tpl_write_first
	
_getdents_loop:
	# loop over dir files
	mov rax, SYS_GETDENTS64
	mov edi, [g_open_resp_file_fd]
	mov rsi, offset g_getdents_buf
	mov rdx, getdents_buf_size
	syscall
	call syscall_fail
	jz _getdents_done
	
	mov r10, rax					# r10 = bytes_read
	mov r9, offset g_getdents_buf	# r9 = entry_cursor_ptr
_getdents_entry_loop:
	# only list reg and dir files
	mov al, byte ptr [r9 + dirent64_off_type] 	# al = entry->d_type
	cmp al, DT_REG
	je _getdents_accept_entry
	# todo: this also accepts . and .. meta files (we should probably ignore these)
	cmp al, DT_DIR
	je _getdents_accept_entry
	jmp _getdents_skip_entry
_getdents_accept_entry:
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
	mov r8w, word ptr [r9 + dirent64_off_reclen]		# read d_reclen
	add r9, r8
	lea rax, [g_getdents_buf + r10]
	cmp r9, rax
	jb _getdents_entry_loop
	jmp _getdents_loop
	
_getdents_done:
	
	# send ok response headers
	# todo: maybe send 500 if something went wrong
	mov rsi, offset default_resp_headers
	mov rdx, default_resp_headers_len
	call write_resp_str
	
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


# in rsi	-- str_ptr
# in rdx	-- str_len (-1 for null-terminated)
write_resp_str:
	cmp rdx, 0
	jge _dont_str_len
	
	# call str_len
	push rsi
	
	mov rdi, rsi
	call str_len
	mov rdx, rax
	
	pop rsi
_dont_str_len:
	mov rax, SYS_WRITE
	mov edi, [g_peer_socket_fd]
	mov rsi, rsi
	mov rdx, rdx
	syscall
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
	
	# mov word ptr [rsp + 2], 0x901F		# port 8080, in network order
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
