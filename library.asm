; =============================================================================
;  APU LIBRARY MANAGEMENT SYSTEM
;  Module : CT073-3-2 Computer System Low Level Techniques
;  Target : x86 32-bit (Linux, ELF32) - assembled with NASM, linked with ld
;
;  Build  : nasm -f elf32 library.asm -o library.o
;           ld -m elf_i386 library.o -o library
;  Run    : ./library
;
;  Demonstrates the three required constructs:
;     * Arithmetic  - fine = days * FINE_RATE, copy counts, running totals
;     * Loops       - iterate over the book catalogue (display / search / stats)
;     * Jumps       - conditional (je/jl/jge...) + unconditional (jmp) branching
;
;  Design note: book records are held in parallel arrays (book_ids, book_avail,
;  book_total and a title-pointer table). This keeps each field naturally
;  aligned and easy to index with [base + index*4].
; =============================================================================

; ------------------------------ Constants ------------------------------------
NUM_BOOKS   equ 5           ; number of titles in the catalogue
MAX_BORROW  equ 3           ; a member may hold at most this many books
FINE_RATE   equ 1           ; overdue fine charged per day (RM)
INPUT_LEN   equ 32          ; size of the keyboard input buffer
NUM_BUF_LEN equ 12          ; scratch space used when printing an integer

SYS_EXIT    equ 1
SYS_READ    equ 3
SYS_WRITE   equ 4
STDIN       equ 0
STDOUT      equ 1

; ============================ Initialised data ===============================
section .data

; ----- Catalogue (parallel arrays, one entry per book) -----
book_ids    dd 101, 102, 103, 104, 105          ; unique book ID
book_avail  dd   3,   2,   0,   5,   1           ; copies currently on the shelf
book_total  dd   3,   2,   4,   5,   2           ; copies the library owns

; Pointer table -> each entry is the address of a null-terminated title string
title_ptrs  dd title1, title2, title3, title4, title5
title1      db "The C Programming Language", 0
title2      db "Computer Organization & Design", 0
title3      db "Operating System Concepts", 0
title4      db "Introduction to Algorithms", 0
title5      db "Assembly Language Step-by-Step", 0

; ----- Runtime state -----
member_count dd 0           ; how many books the current member is holding

; ----- User-interface strings (all null-terminated) -----
banner      db 10, "===============================================", 10
            db "         APU LIBRARY MANAGEMENT SYSTEM          ", 10
            db "===============================================", 10, 0

menu_msg    db 10, "----------------- MAIN MENU -----------------", 10
            db "  1. Display catalogue", 10
            db "  2. Search for a book (by ID)", 10
            db "  3. Borrow a book", 10
            db "  4. Return a book", 10
            db "  5. Library statistics", 10
            db "  6. Exit", 10
            db "---------------------------------------------", 10
            db "  Enter your choice: ", 0

cat_header  db 10, "  ID   | Availability | Title", 10
            db "  -----+--------------+-----------------------", 10, 0

row_id      db "  ", 0
row_pad1    db "  |     ", 0
row_avail   db "     | ", 0
row_slash   db " / ", 0
row_title   db "  | ", 0
newline     db 10, 0
space       db " ", 0

ask_id      db "  Enter book ID: ", 0
ask_days    db "  Enter number of overdue days: ", 0

found_msg   db 10, "  [FOUND]", 10, 0
notfound_msg db 10, "  >> No book matches that ID.", 10, 0
unavail_msg db 10, "  >> Sorry, all copies of this book are on loan.", 10, 0
borrow_ok   db 10, "  >> Book borrowed successfully. Enjoy your reading!", 10, 0
limit_msg   db 10, "  >> Borrow limit reached (max 3 books per member).", 10, 0
notborrowed db 10, "  >> All copies are already on the shelf - nothing to return.", 10, 0
return_ok   db 10, "  >> Book returned successfully.", 10, 0
fine_msg    db "  >> Overdue fine payable: RM ", 0

stat_total    db 10, "  Total copies owned    : ", 0
stat_avail    db "  Copies on the shelf   : ", 0
stat_borrowed db "  Copies on loan        : ", 0
stat_titles   db "  Distinct titles       : ", 0
stat_holding  db "  You are holding       : ", 0

invalid_msg db 10, "  >> Invalid choice, please pick 1-6.", 10, 0
bye_msg     db 10, "  Thank you for using the APU Library System. Goodbye!", 10, 10, 0

; ============================ Uninitialised data =============================
section .bss
input_buf   resb INPUT_LEN          ; raw keyboard input
num_buf     resb NUM_BUF_LEN        ; scratch buffer for integer -> ASCII

; ================================= Code ======================================
section .text
global _start

_start:
    ; ---- one-time welcome banner ----
    mov  esi, banner
    call print

; ------------------------------- MAIN MENU LOOP ------------------------------
; Reads a menu choice and dispatches with conditional jumps. Every handler
; jumps back here (unconditional jmp) once it has finished.
main_loop:
    mov  esi, menu_msg
    call print
    call read_int               ; eax = menu choice

    cmp  eax, 1
    je   do_display
    cmp  eax, 2
    je   do_search
    cmp  eax, 3
    je   do_borrow
    cmp  eax, 4
    je   do_return
    cmp  eax, 5
    je   do_stats
    cmp  eax, 6
    je   do_exit

    mov  esi, invalid_msg       ; fell through -> not 1..6
    call print
    jmp  main_loop

; ---------------------------------------------------------------------------
; 1) DISPLAY CATALOGUE  - a counted loop over every book record
; ---------------------------------------------------------------------------
do_display:
    mov  esi, cat_header
    call print
    xor  ecx, ecx               ; ecx = loop index (0 .. NUM_BOOKS-1)
.next_book:
    cmp  ecx, NUM_BOOKS
    jge  .done                  ; index reached the end -> stop looping

    call print_row              ; helper prints one formatted catalogue row
    inc  ecx
    jmp  .next_book             ; unconditional jump = top of the loop
.done:
    jmp  main_loop

; ---------------------------------------------------------------------------
; 2) SEARCH BY ID
; ---------------------------------------------------------------------------
do_search:
    mov  esi, ask_id
    call print
    call read_int               ; eax = wanted ID
    call find_book              ; eax = index, or -1 if not present
    cmp  eax, -1
    je   .missing

    mov  ecx, eax               ; ecx = found index
    mov  esi, found_msg
    call print
    mov  esi, cat_header
    call print
    call print_row              ; show the matching record
    jmp  main_loop
.missing:
    mov  esi, notfound_msg
    call print
    jmp  main_loop

; ---------------------------------------------------------------------------
; 3) BORROW A BOOK  - checks member limit, then availability
; ---------------------------------------------------------------------------
do_borrow:
    mov  eax, [member_count]    ; enforce the per-member limit first
    cmp  eax, MAX_BORROW
    jl   .ask_id                ; below the limit -> allowed to borrow
    mov  esi, limit_msg
    call print
    jmp  main_loop
.ask_id:
    mov  esi, ask_id
    call print
    call read_int
    call find_book              ; eax = index or -1
    cmp  eax, -1
    je   .missing

    mov  ecx, eax               ; ecx = book index
    mov  eax, [book_avail + ecx*4]
    cmp  eax, 0
    jle  .unavailable           ; no copies left on the shelf

    dec  eax                    ; arithmetic: one fewer copy available
    mov  [book_avail + ecx*4], eax
    inc  dword [member_count]   ; arithmetic: member now holds one more
    mov  esi, borrow_ok
    call print
    jmp  main_loop
.unavailable:
    mov  esi, unavail_msg
    call print
    jmp  main_loop
.missing:
    mov  esi, notfound_msg
    call print
    jmp  main_loop

; ---------------------------------------------------------------------------
; 4) RETURN A BOOK  - restocks the shelf and calculates an overdue fine
; ---------------------------------------------------------------------------
do_return:
    mov  esi, ask_id
    call print
    call read_int
    call find_book
    cmp  eax, -1
    je   .missing

    mov  ecx, eax               ; ecx = book index
    mov  eax, [book_avail + ecx*4]
    mov  edx, [book_total + ecx*4]
    cmp  eax, edx
    jge  .not_out               ; avail >= total -> none were borrowed

    push ecx                    ; preserve index across the keyboard read
    mov  esi, ask_days
    call print
    call read_int               ; eax = overdue days
    pop  ecx

    imul eax, eax, FINE_RATE    ; arithmetic: fine = days * FINE_RATE
    push eax                    ; keep the fine safe on the stack

    mov  eax, [book_avail + ecx*4]
    inc  eax                    ; arithmetic: copy is back on the shelf
    mov  [book_avail + ecx*4], eax

    mov  eax, [member_count]    ; member releases one book (guard against < 0)
    test eax, eax
    jle  .skip_dec
    dec  eax
    mov  [member_count], eax
.skip_dec:
    mov  esi, return_ok
    call print
    mov  esi, fine_msg
    call print
    pop  eax                    ; recover the fine we stored earlier
    call print_int
    mov  esi, newline
    call print
    jmp  main_loop
.not_out:
    mov  esi, notborrowed
    call print
    jmp  main_loop
.missing:
    mov  esi, notfound_msg
    call print
    jmp  main_loop

; ---------------------------------------------------------------------------
; 5) STATISTICS  - a loop that accumulates running totals (more arithmetic)
; ---------------------------------------------------------------------------
do_stats:
    xor  ecx, ecx               ; index
    xor  ebx, ebx               ; ebx = running total of available copies
    xor  edx, edx               ; edx = running total of owned copies
.sum:
    cmp  ecx, NUM_BOOKS
    jge  .report
    mov  eax, [book_avail + ecx*4]
    add  ebx, eax               ; accumulate available
    mov  eax, [book_total + ecx*4]
    add  edx, eax               ; accumulate owned
    inc  ecx
    jmp  .sum
.report:
    ; print_int / print preserve ebx and edx, so the totals survive the calls
    mov  esi, stat_total
    call print
    mov  eax, edx
    call print_int
    mov  esi, newline
    call print

    mov  esi, stat_avail
    call print
    mov  eax, ebx
    call print_int
    mov  esi, newline
    call print

    mov  esi, stat_borrowed
    call print
    mov  eax, edx
    sub  eax, ebx               ; arithmetic: on-loan = owned - available
    call print_int
    mov  esi, newline
    call print

    mov  esi, stat_titles
    call print
    mov  eax, NUM_BOOKS
    call print_int
    mov  esi, newline
    call print

    mov  esi, stat_holding
    call print
    mov  eax, [member_count]
    call print_int
    mov  esi, newline
    call print
    jmp  main_loop

; ---------------------------------------------------------------------------
; 6) EXIT  - terminate cleanly via sys_exit
; ---------------------------------------------------------------------------
do_exit:
    mov  esi, bye_msg
    call print
    mov  eax, SYS_EXIT
    xor  ebx, ebx               ; exit status 0
    int  0x80

; =============================================================================
;                              SUBROUTINES
; =============================================================================

; ---------------------------------------------------------------------------
; print_row : print one catalogue record.
;   input  : ecx = book index
;   All output helpers preserve ecx, so the caller's index is safe.
; ---------------------------------------------------------------------------
print_row:
    mov  esi, row_id
    call print
    mov  eax, [book_ids + ecx*4]
    call print_int

    mov  esi, row_avail
    call print
    mov  eax, [book_avail + ecx*4]
    call print_int
    mov  esi, row_slash
    call print
    mov  eax, [book_total + ecx*4]
    call print_int

    mov  esi, row_title
    call print
    mov  esi, [title_ptrs + ecx*4]
    call print
    mov  esi, newline
    call print
    ret

; ---------------------------------------------------------------------------
; find_book : linear search of the ID array (loop + conditional jumps).
;   input  : eax = target ID
;   output : eax = index if found, or -1 if not found
; ---------------------------------------------------------------------------
find_book:
    push ebx
    push ecx
    mov  ebx, eax               ; ebx = target ID
    xor  ecx, ecx               ; ecx = index
.scan:
    cmp  ecx, NUM_BOOKS
    jge  .none
    mov  eax, [book_ids + ecx*4]
    cmp  eax, ebx
    je   .hit
    inc  ecx
    jmp  .scan
.hit:
    mov  eax, ecx               ; return the index
    pop  ecx
    pop  ebx
    ret
.none:
    mov  eax, -1                ; sentinel = not found
    pop  ecx
    pop  ebx
    ret

; ---------------------------------------------------------------------------
; read_int : read one line from the keyboard and convert it to an integer.
;   output : eax = integer value
; ---------------------------------------------------------------------------
read_int:
    mov  eax, SYS_READ
    mov  ebx, STDIN
    mov  ecx, input_buf
    mov  edx, INPUT_LEN
    int  0x80                   ; read the line into input_buf
    cmp  eax, 0                 ; eax = number of bytes read
    jle  .eof                   ; 0 bytes = EOF (or error) -> exit cleanly
    mov  esi, input_buf
    call atoi
    ret
.eof:
    jmp  do_exit                ; leave the program instead of looping forever

; ---------------------------------------------------------------------------
; atoi : convert an ASCII decimal string to an integer.
;   input  : esi = address of the buffer
;   output : eax = integer value (stops at the first non-digit)
; ---------------------------------------------------------------------------
atoi:
    push ebx
    push ecx
    push edx
    xor  eax, eax               ; result accumulator
    xor  ecx, ecx               ; buffer index
.skip:                          ; ignore any leading spaces
    mov  bl, [esi + ecx]
    cmp  bl, ' '
    jne  .digits
    inc  ecx
    jmp  .skip
.digits:
    mov  bl, [esi + ecx]
    cmp  bl, '0'
    jb   .done                  ; below '0' -> not a digit
    cmp  bl, '9'
    ja   .done                  ; above '9' -> not a digit
    sub  bl, '0'                ; ASCII -> numeric value
    imul eax, eax, 10           ; arithmetic: shift the running total one place
    movzx edx, bl
    add  eax, edx               ; add the new digit
    inc  ecx
    jmp  .digits
.done:
    pop  edx
    pop  ecx
    pop  ebx
    ret

; ---------------------------------------------------------------------------
; print_int : print a non-negative integer in decimal.
;   input  : eax = value to print
;   Builds the digits backwards in num_buf, then writes them out.
; ---------------------------------------------------------------------------
print_int:
    push eax
    push ebx
    push ecx
    push edx
    mov  ecx, num_buf + NUM_BUF_LEN     ; ecx = one past the end of the buffer
    mov  ebx, 10                        ; divisor
    test eax, eax
    jnz  .convert
    dec  ecx                            ; special-case the value 0
    mov  byte [ecx], '0'
    jmp  .emit
.convert:
    xor  edx, edx
    div  ebx                            ; eax = quotient, edx = remainder
    add  dl, '0'                        ; remainder -> ASCII digit
    dec  ecx
    mov  [ecx], dl                      ; store digit (least significant first)
    test eax, eax
    jnz  .convert
.emit:
    mov  edx, num_buf + NUM_BUF_LEN
    sub  edx, ecx                       ; edx = number of digits produced
    mov  eax, SYS_WRITE
    mov  ebx, STDOUT
    int  0x80                           ; ecx already points at the first digit
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; print : write a null-terminated string to stdout.
;   input  : esi = address of the string
;   Preserves every general-purpose register the callers rely on.
; ---------------------------------------------------------------------------
print:
    push eax
    push ebx
    push ecx
    push edx
    call strlen                 ; edx = length of the string at esi
    mov  eax, SYS_WRITE
    mov  ebx, STDOUT
    mov  ecx, esi
    int  0x80
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; strlen : measure a null-terminated string.
;   input  : esi = address of the string
;   output : edx = length in bytes
; ---------------------------------------------------------------------------
strlen:
    push eax
    xor  edx, edx
.count:
    mov  al, [esi + edx]
    cmp  al, 0
    je   .end
    inc  edx
    jmp  .count
.end:
    pop  eax
    ret
