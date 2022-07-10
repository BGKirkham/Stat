; nasm -f win64 Stat.asm -o Stat.obj
; gcc -m64 Stat.obj -o Stat.exe

bits 64
default rel

section .bss
avg:	resq 1
std:	resq 1
err:	resq 1
n:	resq 1

argc: 	resq 1
argv: 	resq 1
envp: 	resq 1

dat: 	resq 1   	;pointer to begining of malloc'd memory


section .data

fmtavg 	db 0xA, "Average = %.3f", 0xA, 0
fmtstd 	db "Std Dev = %.3f", 0xA, 0
fmterr 	db "Std Err = %.3f", 0xA, 0
fmtn 	db "Num Pts = %.0f", 0xA, 0xA, 0
fmt90 	db "    90%% Confidence Interval = %.3f%c%.3f", 0xA, 0
fmt95 	db "    95%% Confidence Interval = %.3f%c%.3f", 0xA, 0
fmt99 	db "    99%% Confidence Interval = %.3f%c%.3f", 0xA, 0
fmt999 	db "  99.9%% Confidence Interval = %.3f%c%.3f", 0xA, 0
fmt9999 db " 99.99%% Confidence Interval = %.3f%c%.3f", 0xA, 0
fmt99999 db "99.999%% Confidence Interval = %.3f%c%.3f", 0xA, 0

;error messages
invalid_input 	db 0xA, "Enter more than 2 data points", 0xA, 0
memory_err	db 0xA, "Unable to allocate memory", 0xA, 0

section .rodata
ONE:	dq 1.0
Z90:	dq 1.644854
Z95:	dq 1.959964
Z99:	dq 2.575829
Z999:	dq 3.290527
Z9999:	dq 3.890590
Z99999:	dq 4.417173
plm:	dq 241

section .text
	global main
	extern printf, atof, malloc, free
	extern ExitProcess
	extern __getmainargs

main:
	push    rbp
	mov     rbp, rsp
	sub     rsp, 32

	lea	rcx, [rel argc]		; pointer to number of command line arguments
	lea	rdx, [rel argv]		; double pointer to argument string
	lea	r8,  [rel envp]
	mov	r9, 0
	call	__getmainargs		; get the arguments, if any

	mov	rcx, [argc]		; number of arguments
	cmp 	rcx, 4			; check to see if there are at least 4 inputs (program name + 3 data points)
	jl 	err_inp

	cvtsi2sd xmm0, [argc]		; convert number of arguments to double
	subsd	xmm0, [ONE]		; and subtract 1 to represent total number of data points
	cvttsd2si rax, xmm0		; convert in back to integer
	mov	[n], rax		; and store it in "n" which is the number of data points

; now allocate dynamic memory to hold the numbers input on the command ine
allocMem:
	mov	rax, 8			; we're storing doubles, which are 8 bytes wide
	mov	rcx, [n]		; and n is the number of doubles to store
	mul	rcx			; multiply to get total number of bytes to allocate
	mov	rcx, rax 		; malloc expects the number of bytes to be in rcx
	call 	malloc             	; Allocate
	
	test 	rax, rax 		; check for malloc error
  	jz	alloc_err		; print the error

	mov	[dat], rax		; store the pointer to the allocated memory
	
getArgs:
	mov	rax, [n]		; number of data points
	mov	rdi, [argv]		; pointer to command line arguments
	mov	rcx, 16			; the string containing the path/program name are located 16 bytes into argv
	mov	rdx, 8			; plus 8 times 
	mul	rdx			; the number of arguments, which is in rax
	add	rcx, rax		; add it to the initial 16 bytes
	add	rdi, rcx		; now rdi points to the first string (prog path/prog name)
	call	strlen			; get the length of the prog path, which is returned in rax
	add	rdi, rax		; add it to rdi so it points to first argument


	mov	rax, [n]		; get the number of data points
	mov	r12, [dat]		; point to the allocated memory
	mov	r14, 0			; r14 is the multipler, initially set to zero
	
.loop:
	mov	rcx, rdi		; move the argument address to rcx for the call to atof
	mov	r13, rax		; save the count
	call	atof			; convert the string (rcx) to a double (xmm0)
	movsd	[r12 + 8 * r14], xmm0	; store it to the allocated array

	call	strlen			; find out how long the string was in rdi, length in rax
	add	rdi, rax		; add it to rdi so it points to the next argument string		

	mov	rax, r13		; restore the counter

	inc	r14			; increment the multiplier
	dec	rax			; decrement the counter
	jnz	.loop			; and see if we're at zero, meaning we're done.  If not, keep looping


calcAvg:	
	mov	rax, [n]		; get the number of data points
	pxor	xmm0, xmm0		; zero out the xmm0 register.  Using it to hold the sum of the data points
	mov	r14, 0			; zero out the multiplier

.loop:
	addsd	xmm0, [r12 + 8 * r14]	; get a data point and add it to xmm0
	inc	r14			; increment the multiplier
	dec	rax			; decrement the counter
	jnz	.loop			; loop until the counter hits zero


	cvtsi2sd xmm1, [n]		; convert the number of data points from integer to double
	divsd	xmm0, xmm1		; avg = sum / n
	movsd	[avg], xmm0		; store the average

	lea	rcx, [fmtavg]		; load the address of the average output format
	movq	xmm0, qword [avg]	; load the average to xmm0
	movq	rdx, xmm0		; then move it to rdx for the call to printf
	call	printf

calcStdDev:
	mov	rax, [n]		; get the number of data points
	pxor	xmm0, xmm0		; zero out xmm0.  it will be used to calculate (xi-xavg)^2
	pxor	xmm1, xmm1		; zero out xmm1.  it will be used to hold the sum of (xi-xavg)^2
	mov	r14, 0			; zero out the multiplier

.loop:
	movsd	xmm0, [r12 + 8 * r14]	; get a data point
	subsd	xmm0, [avg]		; subtract the average
	mulsd	xmm0, xmm0		; and square it
	addsd	xmm1, xmm0		; add it to xmm1
	
	inc	r14			; increment the multiplier
	dec	rax			; decrement the counter
	jnz	.loop			; loop until the counter hits zero

	cvtsi2sd xmm2, [n]		; get the number of data points
	subsd	xmm2, [ONE]		; subtract 1 (n-1)
	divsd	xmm1, xmm2		; divide it into sum of (xi-xavg)^2
	sqrtsd	xmm0, xmm1		; take the quare root, shich is the standard deviation

	movsd	[std], xmm0		; store the standard deviation

	lea	rcx, [fmtstd]		; load the address of the standard deviation output format
	movq	xmm0, qword [std]	; load the standard deviation to xmm0
	movq	rdx, xmm0		; and move it to rdx for the call to printf
	call	printf

calcStdErr:	
	movsd	xmm0, [std]		; load standard deviation
	cvtsi2sd xmm1, [n]		; get the number of data points and convert to double
	sqrtsd	xmm1, xmm1		; and take the square root
	divsd	xmm0, xmm1		; divide it into the standard deviation to get stdandard error
	movsd	[err], xmm0		; store it

	lea	rcx, [fmterr]		; load the address of the standard erroroutput format
	movq	xmm0, qword [err]	; moving frequency to rdx is a two part process
	movq	rdx, xmm0
	call	printf

	lea	rcx, [fmtn]		; load the address of standard error format text
	cvtsi2sd xmm0, [n]		; load the standard error to xmm0
	movq	rdx, xmm0		; then move it to rdx for the call to printf
	call	printf

confidenceInt:
	movsd	xmm0, [err]		; load the standard error to xmm0
	mulsd	xmm0, [Z90]		; and multiply it by the 90% Z-score, Z(.90)=1.644854

	lea	rcx, [fmt90]		; load the address of the 90% confidence format
	movq	r9, xmm0		; move the calculated confidence interval to r9, which is the 4th argument to printf
	movq	xmm0, qword [avg]	; move the average to xmm0
	movq	rdx, xmm0		; and then to rdx, which is the 2nd argument to printf
	movq	xmm0, qword [plm]	; plm is the ascii code to ±, which is 241
	movq	r8, xmm0		; move it to r8, which is the 3rd argument to printf
	call	printf


	movsd	xmm0, [err]		; load the standard error to xmm0
	mulsd	xmm0, [Z95]		; and multiply it by the 95% Z-score, Z(.95)=1.959964

	lea	rcx, [fmt95]		; load the address of the 95% confidence format
	movq	r9, xmm0		; move the calculated confidence interval to r9, which is the 4th argument to printf
	movq	xmm0, qword [avg]	; move the average to xmm0
	movq	rdx, xmm0		; and then to rdx, which is the 2nd argument to printf
	movq	xmm0, qword [plm]	; plm is the ascii code to ±, which is 241
	movq	r8, xmm0		; move it to r8, which is the 3rd argument to printf
	call	printf


	movsd	xmm0, [err]		; load the standard error to xmm0
	mulsd	xmm0, [Z99]		; and multiply it by the 99% Z-score, Z(.99)=2.575829

	lea	rcx, [fmt99]		; load the address of the 99% confidence format
	movq	r9, xmm0		; move the calculated confidence interval to r9, which is the 4th argument to printf
	movq	xmm0, qword [avg]	; move the average to xmm0
	movq	rdx, xmm0		; and then to rdx, which is the 2nd argument to printf
	movq	xmm0, qword [plm]	; plm is the ascii code to ±, which is 241
	movq	r8, xmm0		; move it to r8, which is the 3rd argument to printf
	call	printf


	movsd	xmm0, [err]		; load the standard error to xmm0
	mulsd	xmm0, [Z999]		; and multiply it by the 99.9% Z-score, Z(.999)=3.290527

	lea	rcx, [fmt999]		; load the address of the 99.9% confidence format
	movq	r9, xmm0		; move the calculated confidence interval to r9, which is the 4th argument to printf
	movq	xmm0, qword [avg]	; move the average to xmm0
	movq	rdx, xmm0		; and then to rdx, which is the 2nd argument to printf
	movq	xmm0, qword [plm]	; plm is the ascii code to ±, which is 241
	movq	r8, xmm0		; move it to r8, which is the 3rd argument to printf
	call	printf


	movsd	xmm0, [err]		; load the standard error to xmm0
	mulsd	xmm0, [Z9999]		; and multiply it by the 99.99% Z-score, Z(.9999)=3.890590

	lea	rcx, [fmt9999]		; load the address of the 99.99% confidence format
	movq	r9, xmm0		; move the calculated confidence interval to r9, which is the 4th argument to printf
	movq	xmm0, qword [avg]	; move the average to xmm0
	movq	rdx, xmm0		; and then to rdx, which is the 2nd argument to printf
	movq	xmm0, qword [plm]	; plm is the ascii code to ±, which is 241
	movq	r8, xmm0		; move it to r8, which is the 3rd argument to printf
	call	printf

	movsd	xmm0, [err]		; load the standard error to xmm0
	mulsd	xmm0, [Z99999]		; and multiply it by the 99.999% Z-score, Z(.99999)=4.417173

	lea	rcx, [fmt99999]		; load the address of the 99.999% confidence format
	movq	r9, xmm0		; move the calculated confidence interval to r9, which is the 4th argument to printf
	movq	xmm0, qword [avg]	; move the average to xmm0
	movq	rdx, xmm0		; and then to rdx, which is the 2nd argument to printf
	movq	xmm0, qword [plm]	; plm is the ascii code to ±, which is 241
	movq	r8, xmm0		; move it to r8, which is the 3rd argument to printf
	call	printf

; free up the memory we allocated
	mov	rcx, [dat]           	; Address needed in rcx
	call	free               	; And free it.
	
	jmp exit			; bypass the error messages

err_inp:
	lea	rcx, [invalid_input]
	call	printf
	jmp exit

alloc_err:
	lea	rcx, [memory_err]
	call	printf
	jmp exit

exit: 
	leave				; free up shadow space
	xor	rax, rax 
	call	ExitProcess		; exit
	

; Calculate the length of a texrt string	
strlen:
	push	rcx			; we will trash rcx in here, so save it
	xor	rax, rax		; zero out rax
	pxor	xmm0, xmm0		; zero out xmm0

strloop:	
	pcmpistri  xmm0, [rdi + rax], 0001000b	; Packed Compare Implicit Length Strings

	; IMM8[1:0]	= 00b
	;	Src data is unsigned bytes(16 packed unsigned bytes)
	; IMM8[3:2]	= 10b
	; 	Using Equal Each aggregation
	; IMM8[5:4]	= 00b
	;	Positive Polarity, IntRes2 = IntRes1
	; IMM8[6]	= 0b

	lea	rax, [rax + 16]		; inc offset 
	jnz	strloop			; branch based on pcmpistri's flags

	lea	rax, [rax + rcx - 16]	; subtract final increment
					; rcx will contain the offset from [rdi + rax] where the null terminator was found
	inc	rax			; point to next string (null terminator+1)
	pop 	rcx			; restore rcx
	ret
