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
SYS_NEWFSTATAT = 262

O_RDONLY = 0x0	# kinda useless but heck, why not
O_DIRECTORY = 0x10000
DT_REG = 8
DT_DIR = 4
DT_LNK = 10

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
OFFOF_STRUCT_STAT_st_size = 48
OFFOF_STRUCT_STAT_st_mtime = 88
SIZEOF_STRUCT_STAT = 144


# other source files to be included
# Note: We do this here instead of passing multiple
# files to gcc so that we have access to any
# helper macros/defines declared here
# (I guess I could also outsource them into helpers.h, but whatever :P)
#include "str.S"
#include "pbuf.S"
#include "tpl.S"
#include "time.S"



# https://filippo.io/linux-syscall-table/
# https://man7.org/linux/man-pages/man2/syscall.2.html#NOTES


# preserved: 	rbx, rsp, rbp, r12, r13, r14, r15
# scratch:		rax, rdi, rsi, rdx, rcx, r8, r9, r10, r11
# syscall params	rax (syscall nr), di, si, dx, r10, r8, r9
# syscall clobbers: rax, rcx, r11



.section .rodata
STR_AND_LEN(msg_hello, "Hello! Accepting connections now...\n")
STR_AND_LEN(msg_die, "a syscall failed, dying now\n")
# STR_AND_LEN(test_resp, "HTTP/1.1 200 OK\r\nContent-Length: 47\r\n\r\n<!DOCTYPE html><html><body>hello!</body></html>\r\n")

STR_AND_LEN(default_resp_headers, "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
STR_AND_LEN(str_resp_headers_ok, "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
# not sending Content-Type seems to be enough for getting MIME sniffing in browsers to work
STR_AND_LEN(str_resp_headers_file_ok, "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Disposition:inline\r\n\r\n")
STR_AND_LEN(str_resp_headers_404, "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n")

STR_AND_LEN(str_path_single_slash, "/")
STR_AND_LEN(str_path_index_html, "/index.html")
STR_AND_LEN(data_dir_pathz, "./data")
STR_AND_LEN(FILENAME_DOT, ".")
STR_AND_LEN(FILENAME_DOTDOT, "..")

html_index:
	#embed "../html/index.html" prefix(.byte ) suffix(, 0)
html_index_len = . - html_index

html_slot_indexfile:
	#embed "../html/slot_indexfile.html" prefix(.byte ) suffix(, 0)
html_slot_indexfile_len = . - html_slot_indexfile

STR_AND_LEN(SLOT_DIR_PATH, "<!--SLOT_DIR_PATH-->")
STR_AND_LEN(SLOT_INDEXFILE_NEXT, "<!--SLOT_INDEXFILE_NEXT-->")
STR_AND_LEN(SLOT_INDEXFILE_NAME, "<!--SLOT_INDEXFILE_NAME-->")
STR_AND_LEN(SLOT_INDEXFILE_SIZE, "<!--SLOT_INDEXFILE_SIZE-->")
STR_AND_LEN(SLOT_INDEXFILE_MTIME, "<!--SLOT_INDEXFILE_MTIME-->")
STR_AND_LEN(SLOT_INDEXFILE_URL, "<!--SLOT_INDEXFILE_URL-->")
STR_AND_LEN(SLOT_INDEXFILE_FTYPE, "<!--SLOT_INDEXFIL_FTYPE-->")

STR_AND_LEN(FTYPE_FILE, "file")
STR_AND_LEN(FTYPE_DIR, "dir")

STR_AND_LEN(ICON_URL_FILE, "<!--SLOT_INDEXFILE_NEXT-->")

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

dir_tmp_file_url_len = 2048
g_dir_tmp_file_url_buf: 	.space dir_tmp_file_url_len, 0
g_dir_tmp_file_url_len:		.quad 0
g_dir_tmp_file_name_len: 	.quad 0
g_dir_tmp_file_size:		.quad 0
g_dir_tmp_file_mtime_secs:	.quad 0
g_dir_tmp_file_is_dir:		.quad 0

getdents_buf_size = 4096
g_getdents_buf:			.space getdents_buf_size, 0

resp_fsend_buf_size = 4094*8
g_resp_fsend_buf:		.space resp_fsend_buf_size, 0

intfmt_buf_len = 24
g_intfmt_buf:			.space intfmt_buf_len, 0
g_intfmt_ptrz:			.quad 0
g_intfmt_len:			.quad 0
g_intfmt_opt_mindigits:	.quad 0		# set to pad out leading zero digits if wanted, gets reset to 0 on each fmt_u64 call

# g_pbuf_
tpl_buf_mem_len = 0x100000
g_tpl_buf_mem_a:			.space tpl_buf_mem_len, 0
g_tpl_buf_mem_b:			.space tpl_buf_mem_len, 0
g_tpl_buf_ptr:				.quad 0
g_tpl_buf_ptr_tmp:			.quad 0
g_tpl_buf_written_bytes:	.quad 0

bytesize_fmt_buf_len = 64
g_bytesize_fmt_buf:		.space bytesize_fmt_buf_len, 0
g_bytesize_fmt_len: 	.quad 0


.section .text

.global _start
_start:
	# print message
	mov rsi, offset msg_hello
	mov rdx, msg_hello_len
	call print_n
	
	/*
	# DEBUG: time
	mov rdi, 1785688495
	call fmt_epoch_timestamp_secs
	
	mov rax, SYS_WRITE
	mov edi, 1
	mov rsi, offset tm_datetime_fmt_buf
	mov rdx, [tm_datetime_fmt_len]
	syscall
	*/
	
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
	#MEM_COPY(offset STRZ_AAA, [g_tpl_buf_ptr], STRZ_AAA_len)
	#mov qword ptr [g_tpl_buf_written_bytes], STRZ_AAA_len
	
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
	*/
	
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
	mov rdx, ' '
	call str_bfind	# todo: handle errors but we expect status lines to be formatted properly for now
	inc rax			# todo: assuming method and path are separated by a single space
	mov [g_req_path_offset], rax
	
	lea r8, [g_req_read_buf + rax]
	mov [g_req_url_path_ptr], r8		# g_req_path_ptr = g_req_read_buf + g_req_path_offset
	
	# todo: trim further potential whitespace
	# find end of path
	add rdi, rax
	sub rcx, rax
	mov rdx, ' '
	call str_bfind	# todo: handle error but we expect status lines to be formatted properly for now
	mov [g_req_url_path_len], rax
	
	# strip query params off url
	mov rdi, [g_req_url_path_ptr]
	mov rcx, [g_req_url_path_len]
	mov rdx, '?'
	call str_bfind
	cmp rax, 0
	jl _no_query_params
		mov [g_req_url_path_len], rax
	_no_query_params:
	
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
	
	# -- stat requested file to determine if its a folder
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
	push r15
	push r14
	
	# -- walk files to serve
	# start templating
	mov rsi, offset html_index
	mov rcx, html_index_len
	call tpl_write_first
	
	# template dir path
	mov rsi, offset SLOT_DIR_PATH
	mov rdi, [g_req_url_path_ptr]
	mov rcx, SLOT_DIR_PATH_len
	mov rdx, [g_req_url_path_len]
	call tpl_subst
	
_getdents_loop:
	# loop over dir files
	mov rax, SYS_GETDENTS64
	mov edi, [g_open_resp_file_fd]
	mov rsi, offset g_getdents_buf
	mov rdx, getdents_buf_size
	syscall
	call syscall_fail
	jz _getdents_done
	
	mov r15, rax					# r15 = bytes_read
	mov r14, offset g_getdents_buf	# r14 = entry_cursor_ptr
_getdents_entry_loop:
	# calc path len
	lea rdi, [r14 + dirent64_off_name]
	call str_len
	mov [g_dir_tmp_file_name_len], rax
	
	# ignore files "." and ".."
	lea rdi, [r14 + dirent64_off_name]
	mov rsi, offset FILENAME_DOT
	mov rcx, [g_dir_tmp_file_name_len]
	mov rdx, FILENAME_DOT_len
	call str_cmp_nn
	je _getdents_skip_entry
	
	lea rdi, [r14 + dirent64_off_name]
	mov rsi, offset FILENAME_DOTDOT
	mov rcx, [g_dir_tmp_file_name_len]
	mov rdx, FILENAME_DOTDOT_len
	call str_cmp_nn
	je _getdents_skip_entry
	
	# only list reg, dir and link files
	movzx rax, byte ptr [r14 + dirent64_off_type] 	# al = entry->d_type
	cmp al, DT_REG
	je _getdents_accept_entry
	cmp al, DT_DIR
	je _getdents_accept_entry
	cmp al, DT_LNK
	je _getdents_accept_entry
	jmp _getdents_skip_entry
_getdents_accept_entry:
		# fstat file
		sub rsp, SIZEOF_STRUCT_STAT
		
		mov rax, SYS_NEWFSTATAT
		mov edi, dword ptr [g_open_resp_file_fd]		# int dirfd: if we are here we know this is a folder
		lea rsi, [r14 + dirent64_off_name]	# char* path
		mov rdx, rsp 						# stat* statbuf
		xor r10, r10 						# int flags
		syscall
		# todo: error handling
		call syscall_fail
		
		mov rcx, qword ptr [rsp + OFFOF_STRUCT_STAT_st_size]
		mov qword ptr [g_dir_tmp_file_size], rcx	# store file_size
		mov rcx, qword ptr [rsp + OFFOF_STRUCT_STAT_st_mtime]
		mov qword ptr [g_dir_tmp_file_mtime_secs], rcx	# store file_mtime
		
		# check if file is a dir
		mov r9d, dword ptr [rsp + OFFOF_STRUCT_STAT_st_mode]	# r9 = stat.st_mode
		and r9d, S_IFMT
		cmp r9d, S_IFDIR
		setz al
		movzx rax, al
		mov qword ptr [g_dir_tmp_file_is_dir], rax	# store is_dir
		
		add rsp, SIZEOF_STRUCT_STAT
		
		# -- template file entry
		mov rsi, offset SLOT_INDEXFILE_NEXT
		mov rdi, offset html_slot_indexfile
		mov rcx, SLOT_INDEXFILE_NEXT_len
		mov rdx, html_slot_indexfile_len
		call tpl_subst
		
		# template file name
		mov rsi, offset SLOT_INDEXFILE_NAME
		lea rdi, [r14 + dirent64_off_name]
		mov rcx, SLOT_INDEXFILE_NAME_len
		mov rdx, [g_dir_tmp_file_name_len]
		call tpl_subst
		
		# template file size
		# in r10				-- u64 to format
		# out g_intfmt_ptrz		-- ptr to formatted strz
		mov r10, [g_dir_tmp_file_size]
		call fmt_u64
		
		mov rsi, offset SLOT_INDEXFILE_SIZE
		mov rdi, [g_intfmt_ptrz]
		mov rcx, SLOT_INDEXFILE_SIZE_len
		mov rdx, [g_intfmt_len]
		call tpl_subst
		
		# assembly file url
		mov rdi, offset g_dir_tmp_file_url_buf
		MEM_COPY([g_req_url_path_ptr], rdi, [g_req_url_path_len])
		mov r8, [g_req_url_path_len] 	# r8 = url len
		
		mov rax, [g_req_url_path_ptr]
		add rax, [g_req_url_path_len]
		dec rax
		cmp byte ptr [rax], '/'
		je _dont_insert_url_slash
			mov byte ptr [rdi + r8], '/'
			inc r8
		_dont_insert_url_slash:
		lea rax, [r14 + dirent64_off_name]
		lea rdx, [rdi + r8]
		MEM_COPY(rax, rdx, [g_dir_tmp_file_name_len])
		add r8, [g_dir_tmp_file_name_len]
		mov [g_dir_tmp_file_url_len], r8
		
		# template file url
		mov rsi, offset SLOT_INDEXFILE_URL
		mov rdi, offset g_dir_tmp_file_url_buf
		mov rcx, SLOT_INDEXFILE_URL_len
		mov rdx, [g_dir_tmp_file_url_len]
		call tpl_subst
		
		# template file ftype
		mov rdi, offset FTYPE_FILE
		mov rdx, FTYPE_FILE_len
		
		mov rax, [g_dir_tmp_file_is_dir]
		cmp rax, 0
		je _is_ftype_file
			mov rdi, offset FTYPE_DIR
			mov rdx, FTYPE_DIR_len
		_is_ftype_file:
		
		mov rsi, offset SLOT_INDEXFILE_FTYPE
		mov rcx, SLOT_INDEXFILE_FTYPE_len
		call tpl_subst
		
		# template mtime
		/*
		xor rdx, rdx
		mov rax, [g_dir_tmp_file_mtime_secs]
		mov rcx, 86400		# ratio secs to days
		div rcx
		*/
		mov rdi, [g_dir_tmp_file_mtime_secs]
		call fmt_epoch_timestamp_secs
		
		mov rsi, offset SLOT_INDEXFILE_MTIME
		mov rdi, offset tm_datetime_fmt_buf
		mov rcx, SLOT_INDEXFILE_MTIME_len
		mov rdx, [tm_datetime_fmt_len]
		call tpl_subst
		
		/*
		# DEBUG
		mov rax, SYS_WRITE
		mov edi, 1
		mov rsi, [g_tpl_buf_ptr]
		mov rdx, [g_tpl_buf_written_bytes]
		syscall
		*/
		
		/*
		# DEBUG: write same data back to socket
		lea rdi, [r14 + dirent64_off_name]
		call str_len
		mov rdx, rax
		
		mov rax, SYS_WRITE
		# mov edi, [g_peer_socket_fd]
		mov edi, 1
		lea rsi, [r14 + dirent64_off_name]
		# rdx is set above
		syscall
		call syscall_fail
		*/
_getdents_skip_entry:
	# incr cursor and check for end
	movzx r8, word ptr [r14 + dirent64_off_reclen]		# read d_reclen
	add r14, r8
	lea rax, [offset g_getdents_buf + r15]
	cmp r14, rax
	jb _getdents_entry_loop
	jmp _getdents_loop
	
_getdents_done:
	
	# send ok response headers
	# todo: maybe send 500 if something went wrong
	mov rsi, offset default_resp_headers
	mov rdx, default_resp_headers_len
	call write_resp_str
	
	# send templated data
	mov rsi, [g_tpl_buf_ptr]
	mov rdx, [g_tpl_buf_written_bytes]
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
	
	pop r14
	pop r15
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
