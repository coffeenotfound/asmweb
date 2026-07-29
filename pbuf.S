
.section .text


.global pbuf_create
pbuf_create:
	mov rax, SYS_EXIT
	ret
