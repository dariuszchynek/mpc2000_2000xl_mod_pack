/* Final firmware source: ping-pong.
 * Assembly source sections for this feature.
 */
/* xl_ping_pong: assembly unit 25. */
.if MOD_UNIT == 25
/* MPC2000XL OS 1.20 only: EDIT mode "PING-PONG > NEW SOUND".
 * From the LOOP screen EDIT's section is the loop (St = End - loop length);
 * from TRIM it is St..End. Not offered from ZONE.
 * DO IT creates a new sound named by New name (natively prefilled with a
 * free, numbered name, as for SECTION > NEW SOUND):
 *   source[0..End) + reverse(source[St+1..End-1)), loop St..new End.
 * The source is never written. Loop/End placement is the user's job; the
 * only guard keeps copy lengths valid (loop <= 2 words: plain copy).
 * Foreground only: no voice, DSP or playback hooks.
 *
 * Input identity. An earlier revision (7 hooks, also offered from ZONE) was
 * assembled with GNU as, placed at PINGPONG_CS=0x741b in stock 1.20 and
 * worked on the author's MPC2000XL. This revision (6 hooks) was built the same
 * way and also worked on hardware (2026-09-29).
 *   MPC2KXL.BIN, 524288 bytes, internal string "1.14c" at file 0xfe70,
 *   VER screen "1.2" at file 0x30e43, SHA-256
 *   100e3375b45072c209ffa2b1dbaecbf740c8c4ea29162827ac11cc6bf9cc7bab.
 *   File offset == segment * 16. Native EDIT code: CS 0x3e19, DS 0x582b.
 * Not verified against XL 1.14 or any modified image.
 *
 * Integration supplies PINGPONG_CS (free space for this module) and applies
 * hook_table after checking every expected_n. Image size and checksum rules
 * of the XL target apply; nothing here maintains them.
 */
.intel_syntax noprefix
.code16
.arch i186
.text
.ifndef PINGPONG_CS
.error "PINGPONG_CS must name the segment this module is placed at"
.endif
.global module_start, module_end, code_end
.global pp_edit_name, pp_layout_type, pp_doit_type, pp_change_type
.global pp_section_new, pp_ping_pong
.equ NATIVE_CS, 0x3e19
.equ LIB_CS, 0x35b0
/* EDIT window state, DS=0x582b. */
.equ EDIT_TYPE, 0x8d4c /* word: Edit: field value */
.equ EDIT_CALLER, 0x8d52 /* far: screen that opened EDIT */
.equ EDIT_NAMES, 0x25dc /* 9 far pointers: DISCARD..SLICE SOUND */
.equ ZONE_CALLER, 0xf1dc /* NATIVE_CS offset of the ZONE screen */
.equ TYPE_NEW_SOUND, 2 /* SECTION > NEW SOUND: New name: layout */
.equ TYPE_SLICE, 8 /* offered only when opened from ZONE */
/* Native routines, all FAR C calls (SI/DI/BP/DS preserved). */
.equ N_NAME_USED, 0x1d0e /* (far 0, far name) AX!=0: in use */
.equ N_CREATE, 0x328e /* (far *out, far src, far name, dword frames) */
.equ N_COPY, 0x2282 /* (far dst, dword at, far src, dword from, dword n) */
.equ N_REVERSE, 0x2eea /* (far section) REVERSE SECTION, in place */
.equ N_SECTION_NEW, 0x2a0a /* (far section, far name) SECTION > NEW SOUND */
.equ L_LOOP_CODE, 0x04fc /* (dword loop length, word 0) DSP loop code */
.equ E_NAME_USED, 0x3412 /* "Name already used" */
/* Section block (DS:0x98a6) and sound header offsets. */
.equ S_SOUND, 0
.equ S_RESULT, 4
.equ S_START, 8
.equ S_END, 12
.equ H_START, 0x26
.equ H_LOOP_LENGTH, 0x32
.equ H_LOOP_ON, 0x36
.equ H_LOOP_CODE, 0x3a
.macro fc seg,ip
 .byte 0x9a
 .word \ip,\seg
.endm
.macro fj seg,ip
 .byte 0xea
 .word \ip,\seg
.endm
module_start:

/* ZF=1 when EDIT_TYPE selects PING-PONG: the last entry, 8, from TRIM or
   LOOP. Not offered from ZONE, whose section is a zone, not a chosen loop;
   there 8 remains SLICE SOUND. AX lost. */
pp_check:
 mov ax,word ptr ds:[EDIT_TYPE]
 cmp ax,TYPE_SLICE
 jne .Lcheck_done
 cmp word ptr ds:[EDIT_CALLER+2],NATIVE_CS
 jne .Lcheck_ping_pong
 cmp word ptr ds:[EDIT_CALLER],ZONE_CALLER
 jne .Lcheck_ping_pong
 or ax,ax
 ret
.Lcheck_ping_pong:
 xor ax,ax
.Lcheck_done:
 ret

/* AX=native type, or SECTION > NEW SOUND for PING-PONG. */
pp_effective_type:
 call pp_check
 mov ax,TYPE_NEW_SOUND
 je .Leffective_done
 mov ax,word ptr ds:[EDIT_TYPE]
.Leffective_done:
 ret

/* Replaces the name table lookup. DX:AX=far name; BX lost as natively. */
pp_edit_name:
 call pp_check
 jne .Lname_native
 mov ax,offset pp_label-module_start
 mov dx,cs
 retf
.Lname_native:
 mov bx,word ptr ds:[EDIT_TYPE]
 shl bx,2
 mov ax,word ptr ds:[bx+EDIT_NAMES]
 mov dx,word ptr ds:[bx+EDIT_NAMES+2]
 retf

/* Replace MOV AX,[type] + CMP AX,n; flags come back for the native JA. */
pp_layout_type:
 call pp_effective_type
 cmp ax,8
 retf
pp_doit_type:
 call pp_effective_type
 cmp ax,7
 retf
/* Replaces MOV AX,[type] + DEC AX + DEC AX before the field switch. */
pp_change_type:
 call pp_effective_type
 dec ax
 dec ax
 retf

/* Replaces the SECTION > NEW SOUND call inside DO IT. Same FAR frame. */
pp_section_new:
 push ax
 call pp_check
 pop ax
 jne .Lsection_native
 jmp pp_ping_pong
.Lsection_native:
 fj NATIVE_CS,N_SECTION_NEW

/* FAR C (far section, far name): DX:AX=0 or far error text, like
   SECTION > NEW SOUND. On success section+4 = the new sound. */
pp_ping_pong:
 enter 0x28,0
 les bx,[bp+6]
 mov ax,es:[bx+S_SOUND]
 mov [bp-4],ax
 mov ax,es:[bx+S_SOUND+2]
 mov [bp-2],ax
 mov ax,es:[bx+S_START]
 mov [bp-8],ax
 mov ax,es:[bx+S_START+2]
 mov [bp-6],ax
 mov ax,es:[bx+S_END]
 mov [bp-0xc],ax
 mov ax,es:[bx+S_END+2]
 mov [bp-0xa],ax
 /* Mirror = End-St-2 words; none unless 0 <= St < End. */
 xor ax,ax
 mov [bp-0x10],ax
 mov [bp-0xe],ax
 cmp word ptr [bp-6],0
 jl .Lbad_start
 mov ax,[bp-0xc]
 mov dx,[bp-0xa]
 sub ax,[bp-8]
 sbb dx,[bp-6]
 jl .Lbad_start
 mov cx,ax
 or cx,dx
 jz .Lbad_start
 sub ax,2
 sbb dx,0
 jl .Lsection_ok
 mov [bp-0x10],ax
 mov [bp-0xe],dx
 jmp .Lsection_ok
.Lbad_start:
 xor ax,ax
 mov [bp-8],ax
 mov [bp-6],ax
.Lsection_ok:
 push word ptr [bp+0xc]
 push word ptr [bp+0xa]
 push 0
 push 0
 fc NATIVE_CS,N_NAME_USED
 add sp,8
 or ax,ax
 jz .Lname_free
 mov ax,E_NAME_USED
 mov dx,NATIVE_CS
 jmp .Ldone
.Lname_free:
 mov ax,[bp-0xc]
 mov dx,[bp-0xa]
 add ax,[bp-0x10]
 adc dx,[bp-0xe]
 mov [bp-0x28],ax
 mov [bp-0x26],dx
 /* Native create copies the source header and name, then sets Start 0,
    End/frames/loop length = new length. Its error text is returned. */
 push dx
 push ax
 push word ptr [bp+0xc]
 push word ptr [bp+0xa]
 push word ptr [bp-2]
 push word ptr [bp-4]
 push ss
 lea ax,[bp-0x14]
 push ax
 fc NATIVE_CS,N_CREATE
 add sp,0x10
 mov cx,ax
 or cx,dx
 jz .Lcreated
 jmp .Ldone
.Lcreated:
 push word ptr [bp-0xa]
 push word ptr [bp-0xc]
 push 0
 push 0
 push word ptr [bp-2]
 push word ptr [bp-4]
 push 0
 push 0
 push word ptr [bp-0x12]
 push word ptr [bp-0x14]
 fc NATIVE_CS,N_COPY
 add sp,0x14
 mov ax,[bp-0x10]
 or ax,[bp-0xe]
 jnz .Lmirror
 jmp .Lloop
.Lmirror:
 /* Turnaround words St and End-1 are not repeated. */
 push word ptr [bp-0xe]
 push word ptr [bp-0x10]
 mov ax,[bp-8]
 mov dx,[bp-6]
 add ax,1
 adc dx,0
 push dx
 push ax
 push word ptr [bp-2]
 push word ptr [bp-4]
 push word ptr [bp-0xa]
 push word ptr [bp-0xc]
 push word ptr [bp-0x12]
 push word ptr [bp-0x14]
 fc NATIVE_CS,N_COPY
 add sp,0x14
 /* Native REVERSE SECTION on the new sound: End..new End, every channel. */
 mov ax,[bp-0x14]
 mov [bp-0x24+S_SOUND],ax
 mov ax,[bp-0x12]
 mov [bp-0x24+S_SOUND+2],ax
 mov ax,[bp-0xc]
 mov [bp-0x24+S_START],ax
 mov ax,[bp-0xa]
 mov [bp-0x24+S_START+2],ax
 mov ax,[bp-0x28]
 mov [bp-0x24+S_END],ax
 mov ax,[bp-0x26]
 mov [bp-0x24+S_END+2],ax
 push ss
 lea ax,[bp-0x24]
 push ax
 fc NATIVE_CS,N_REVERSE
 add sp,4
.Lloop:
 /* Keep the source Start when it lies before End. */
 les bx,[bp-4]
 mov ax,es:[bx+H_START]
 mov dx,es:[bx+H_START+2]
 cmp dx,[bp-0xa]
 jb .Lstart_ok
 ja .Lstart_zero
 cmp ax,[bp-0xc]
 jb .Lstart_ok
.Lstart_zero:
 xor ax,ax
 xor dx,dx
.Lstart_ok:
 les bx,[bp-0x14]
 mov es:[bx+H_START],ax
 mov es:[bx+H_START+2],dx
 mov ax,[bp-0x28]
 mov dx,[bp-0x26]
 sub ax,[bp-8]
 sbb dx,[bp-6]
 mov es:[bx+H_LOOP_LENGTH],ax
 mov es:[bx+H_LOOP_LENGTH+2],dx
 mov byte ptr es:[bx+H_LOOP_ON],1
 /* The DSP loop code must follow every loop length change, as in the
    native LOOP FROM ST TO END; stale code would play the old period. */
 push 0
 push dx
 push ax
 fc LIB_CS,L_LOOP_CODE
 add sp,6
 les bx,[bp-0x14]
 mov es:[bx+H_LOOP_CODE],ax
 mov es:[bx+H_LOOP_CODE+2],dx
 mov ax,[bp-0x14]
 mov dx,[bp-0x12]
 les bx,[bp+6]
 mov es:[bx+S_RESULT],ax
 mov es:[bx+S_RESULT+2],dx
 xor ax,ax
 cwd
.Ldone:
 leave
 retf

pp_label:
 .ascii "PING-PONG "
 .byte 0x0c /* native arrow glyph, as in SECTION > NEW SOUND */
 .asciz " NEW SOUND"
code_end:

/* Static patch sites: segment, offset, length, expected, replacement.
   Every expected_n must match before any byte is written. */
.balign 2
.equ HOOK_COUNT, 6
hook_table:
.word NATIVE_CS, 0xef94, 3, expected_0-module_start, patch_0-module_start
.word NATIVE_CS, 0xed82, 15, expected_1-module_start, patch_1-module_start
.word NATIVE_CS, 0xed9d, 6, expected_2-module_start, patch_2-module_start
.word NATIVE_CS, 0xec15, 6, expected_3-module_start, patch_3-module_start
.word NATIVE_CS, 0xeca2, 5, expected_4-module_start, patch_4-module_start
.word NATIVE_CS, 0xefb0, 5, expected_5-module_start, patch_5-module_start
/* 0: Edit: maximum from TRIM/LOOP, 7 -> 8. The ZONE maximum (8, SLICE
   SOUND at CS:EF8E) stays native. */
expected_0:
.byte 0xb8,0x7,0x0
patch_0:
.byte 0xb8,0x8,0x0
/* 1: mode name: MOV BX,[type]; SHL BX,2; PUSH [BX+25DE]; PUSH [BX+25DC]. */
expected_1:
.byte 0x8b,0x1e,0x4c,0x8d,0xc1,0xe3,0x2,0xff,0xb7,0xde,0x25,0xff,0xb7,0xdc,0x25
patch_1:
.byte 0x9a
.word pp_edit_name-module_start, PINGPONG_CS
.byte 0x52,0x50
.fill 8,1,0x90
/* 2: window layout switch: MOV AX,[type]; CMP AX,8. */
expected_2:
.byte 0xa1,0x4c,0x8d,0x3d,0x8,0x0
patch_2:
.byte 0x9a
.word pp_layout_type-module_start, PINGPONG_CS
.fill 1,1,0x90
/* 3: DO IT switch: MOV AX,[type]; CMP AX,7. */
expected_3:
.byte 0xa1,0x4c,0x8d,0x3d,0x7,0x0
patch_3:
.byte 0x9a
.word pp_doit_type-module_start, PINGPONG_CS
.fill 1,1,0x90
/* 4: DO IT case 2: NOP; PUSH CS; CALL SECTION > NEW SOUND. */
expected_4:
.byte 0x90,0xe,0xe8,0x63,0x3d
patch_4:
.byte 0x9a
.word pp_section_new-module_start, PINGPONG_CS
.fill 0,1,0x90
/* 5: field switch after the Edit: field: MOV AX,[type]; DEC AX; DEC AX. */
expected_5:
.byte 0xa1,0x4c,0x8d,0x48,0x48
patch_5:
.byte 0x9a
.word pp_change_type-module_start, PINGPONG_CS
.fill 0,1,0x90
module_end:

.endif /* xl_ping_pong */
