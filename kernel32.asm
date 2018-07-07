; ==================================================================
; MikeOS32 -- The unofficial Mike Operating System 32 bit protected mode kernel
; Copyright (C) 2006 - 2012 MikeOS Developers -- see doc/LICENSE.TXT
;
; This is loaded from the drive, as KERNEL32.BIN.
; First we have the system call vectors, which start at a static point
; for programs to use. Following that is the main kernel code and
; then additional system call code is included.
; ==================================================================

use32
START_ADDRESS equ 100000h
DISK_BUFFER equ START_ADDRESS+80000h
LOAD_ADDRESS EQU 400000h
RESERVED_TRACK EQU 36
DEFINE MikeOS32_VER '4.4'               ; OS version number
DEFINE MikeOS32_API_VER 16              ; API version for programs to check

org START_ADDRESS
; ------------------------------------------------------------------
; OS CALL VECTORS -- Static locations for system call vectors
; Note: these cannot be moved, or it'll break the calls!
; The comments show exact locations of instructions in this section,
; and are used in programs/mikedev.inc so that an external program can
; use a MikeOS32 system call without having to know its exact position
; in the kernel source code...
os_call_vectors:
  jmp os_main                           ; 100000h -- Called from bootloader
align 8
  jmp os_print_string                   ; 100008h
align 8
  jmp os_move_cursor                    ; 100010h
align 8
  jmp os_clear_screen                   ; 100018h
align 8
  jmp os_print_horiz_line               ; 100020h
align 8
  jmp os_print_newline                  ; 100028h
align 8
  jmp os_wait_for_key                   ; 100030h
align 8
  jmp os_check_for_key                  ; 100038h
align 8
  jmp os_int_to_string                  ; 100040h
align 8
  jmp os_speaker_tone                   ; 100048h
align 8
  jmp os_speaker_off                    ; 100050h
align 8
  jmp os_load_file                      ; 100058h
align 8
  jmp os_pause                          ; 100060h
align 8
  jmp os_fatal_error                    ; 100068h
align 8
  jmp os_draw_background                ; 100070h
align 8
  jmp os_string_length                  ; 100078h
align 8
  jmp os_string_uppercase               ; 100080h
align 8
  jmp os_string_lowercase               ; 100088h
align 8
  jmp os_input_string                   ; 100090h
align 8
  jmp os_string_copy                    ; 100098h
align 8
  jmp os_dialog_box                     ; 1000A0h
align 8
  jmp os_string_join                    ; 1000A8h
align 8
  jmp os_get_file_list                  ; 1000B0h
align 8
  jmp os_string_compare                 ; 1000B8h
align 8
  jmp os_string_chomp                   ; 1000C0h
align 8
  jmp os_string_strip                   ; 1000C8h
align 8
  jmp os_string_truncate                ; 1000D0h
align 8
  jmp os_bcd_to_int                     ; 1000D8h
align 8
  jmp os_get_time_string                ; 1000E0h
align 8
  jmp os_get_api_version                ; 1000E8h
align 8
  jmp os_file_selector                  ; 1000F0h
align 8
  jmp os_get_date_string                ; 1000F8h
align 8
  jmp os_send_via_serial                ; 100100h
align 8
  jmp os_get_via_serial                 ; 100108h
align 8
  jmp os_find_char_in_string            ; 100110h
align 8
  jmp os_get_cursor_pos                 ; 100118h
align 8
  jmp os_print_space                    ; 100120h
align 8
  jmp os_dump_string                    ; 100128h
align 8
  jmp os_print_digit                    ; 100130h
align 8
  jmp os_print_1hex                     ; 100138h
align 8
  jmp os_print_2hex                     ; 100140h
align 8
  jmp os_print_4hex                     ; 100148h
align 8
  jmp os_long_int_to_string             ; 100150h
align 8
  jmp os_long_int_negate                ; 100158h
align 8
  jmp os_set_time_fmt                   ; 100160h
align 8
  jmp os_set_date_fmt                   ; 100168h
align 8
  jmp os_show_cursor                    ; 100170h
align 8
  jmp os_hide_cursor                    ; 100178h
align 8
  jmp os_dump_registers                 ; 100180h
align 8
  jmp os_string_strincmp                ; 100188h
align 8
  jmp os_write_file                     ; 100190h
align 8
  jmp os_file_exists                    ; 100198h
align 8
  jmp os_create_file                    ; 1001A0h
align 8
  jmp os_remove_file                    ; 1001A8h
align 8
  jmp os_rename_file                    ; 1001B0h
align 8
  jmp os_get_file_size                  ; 1001B8h
align 8
  jmp os_input_dialog                   ; 1001C0h
align 8
  jmp os_list_dialog                    ; 1001C8h
align 8
  jmp os_string_reverse                 ; 1001D0h
align 8
  jmp os_string_to_int                  ; 1001D8h
align 8
  jmp os_draw_block                     ; 1001E0h
align 8
  jmp os_get_random                     ; 1001E8h
align 8
  jmp os_string_charchange              ; 1001F0h
align 8
  jmp os_serial_port_enable             ; 1001F8h
align 8
  jmp os_sint_to_string                 ; 100200h
align 8
  jmp os_string_parse                   ; 100208h
align 8
  jmp os_run_basic                      ; 100210h
align 8
  jmp os_port_byte_out                  ; 100218h
align 8
  jmp os_port_byte_in                   ; 100220h
align 8
  jmp os_string_tokenize                ; 100228h
; ------------------------------------------------------------------
; START OF MAIN KERNEL CODE
align 8
os_main:

  mov esp, LOAD_ADDRESS
  cld                                   ; The default direction for string operations

;  cmp dl, 0
;  je no_change
  mov [bootdev], dl                     ; Save boot device number
  mov ah, 8                             ; Get drive parameters
  int 13h
  and ecx, 3Fh                          ; Maximum sector number
  mov [SecsPerTrack], ecx               ; Sector numbers start at 1
  movzx edx, dh                         ; Maximum head number
  add edx, 1                            ; Head numbers start at 0 - add 1 for total
  mov [Sides], edx
no_change:
  mov eax, 1003h                        ; Set text output with certain attributes
  mov ebx, 0                            ; to be bright, and not blinking
  int 10h
  call os_seed_random                   ; Seed random number generator
                                        ; Let's see if there's a file called AUTORUN.BIN and execute
                                        ; it if so, before going to the program launcher menu
  mov eax, autorun_bin_file_name
  call os_file_exists
  jc no_autorun_bin                     ; Skip next three lines if AUTORUN.BIN doesn't exist
  mov ecx, LOAD_ADDRESS                 ; Otherwise load the program into RAM...
  call os_load_file
  jmp execute_bin_program               ; ...and move on to the executing part
                                        ; Or perhaps there's an AUTORUN.BAS file?
no_autorun_bin:
  mov eax, autorun_bas_file_name
  call os_file_exists
  jc option_screen                      ; Skip next section if AUTORUN.BAS doesn't exist
  mov ecx, LOAD_ADDRESS                 ; Otherwise load the program into RAM
  call os_load_file
  call os_clear_screen
  mov eax, LOAD_ADDRESS
  call os_run_basic                     ; Run the kernel's BASIC interpreter
  jmp app_selector                      ; And go to the app selector menu when BASIC ends
                                        ; Now we display a dialog box offering the user a choice of
                                        ; a menu-driven program selector, or a command-line interface
option_screen:
  mov eax, os_init_msg                  ; Set up the welcome screen
  mov ebx, os_version_msg
  mov ecx, 10011111b                    ; Colour: white text on light blue
  call os_draw_background
  mov eax, dialog_string_1              ; Ask if user wants app selector or command-line
  mov ebx, dialog_string_2
  mov ecx, dialog_string_3
  mov edx, 1                            ; We want a two-option dialog box (OK or Cancel)
  call os_dialog_box
  cmp eax, 1                            ; If OK (option 0) chosen, start app selector
  jne near app_selector
  call os_clear_screen                  ; Otherwise clean screen and start the CLI
  call os_command_line
  jmp option_screen                     ; Offer menu/CLI choice after CLI has exited
                                        ; Data for the above code...
os_init_msg db 'Welcome to MikeOS32', 0
os_version_msg db 'Version ', MikeOS32_VER, 0
dialog_string_1 db 'Thanks for trying out MikeOS32!', 0
dialog_string_2 db 'Please select an interface: OK for the', 0
dialog_string_3 db 'program menu, Cancel for command line.', 0
app_selector:
  mov eax, os_init_msg                  ; Draw main screen layout
  mov ebx, os_version_msg
  mov ecx, 10011111b                    ; Colour: white text on light blue
  call os_draw_background
  call os_file_selector                 ; Get user to select a file, and store
                                        ; the resulting string location in EAX
                                        ; (other registers are undetermined)
  jc option_screen                      ; Return to the CLI/menu choice screen if Esc pressed
  mov esi, eax                          ; Did the user try to run 'KERNEL.BIN'?
  mov edi, kern_file_name
  call os_string_compare
  jc no_kernel_execute                  ; Show an error message if so
                                        ; Next, we need to check that the program we're attempting to run is
                                        ; valid -- in other words, that it has a .BIN extension
  push esi                              ; Save filename temporarily
  mov ebx, esi
  mov eax, esi
  call os_string_length
  mov esi, ebx
  add esi, eax                          ; ESI now points to end of filename...
  dec esi
  dec esi
  dec esi                               ; ...and now to start of extension!
  mov edi, bin_ext
  mov ecx, 3
  rep cmpsb                             ; Are final 3 chars 'BIN'?
  jne not_bin_extension                 ; If not, it might be a '.BAS'
  pop esi                               ; Restore filename
  mov eax, esi
  mov ecx, LOAD_ADDRESS                 ; Where to load the program file
  call os_load_file                     ; Load filename pointed to by AX
execute_bin_program:
  call os_clear_screen                  ; Clear screen before running
  mov eax, 0                            ; Clear all registers
  mov ebx, 0
  mov ecx, 0
  mov edx, 0
  mov esi, 0
  mov edi, 0
  call LOAD_ADDRESS                     ; Call the external program code,
                                        ; (program must end with 'ret')
  call os_clear_screen                  ; When finished, clear screen
  jmp app_selector                      ; and go back to the program list
no_kernel_execute:                      ; Warn about trying to executing kernel!
  mov eax, kerndlg_string_1
  mov ebx, kerndlg_string_2
  mov ecx, kerndlg_string_3
  mov edx, 0                            ; One button for dialog box
  call os_dialog_box
  jmp app_selector                      ; Start over again...
not_bin_extension:
  pop esi                               ; We pushed during the .BIN extension check
  push esi                              ; Save it again in case of error...
  mov ebx, esi
  mov eax, esi
  call os_string_length
  mov esi, ebx
  add esi, eax                          ; ESI now points to end of filename...
  dec esi
  dec esi
  dec esi                               ; ...and now to start of extension!
  mov edi, bas_ext
  mov ecx, 3
  rep cmpsb                             ; Are final 3 chars 'BAS'?
  jne not_bas_extension                 ; If not, error out
  pop esi
  mov eax, esi
  mov ecx, LOAD_ADDRESS                 ; Where to load the program file
  call os_load_file                     ; Load filename pointed to by EAX
  call os_clear_screen                  ; Clear screen before running
  mov eax, LOAD_ADDRESS
  mov esi, 0                            ; No params to pass
  call os_run_basic                     ; And run our BASIC interpreter on the code!
  mov esi, basic_finished_msg
  call os_print_string
  call os_wait_for_key
  call os_clear_screen
  jmp app_selector                      ; and go back to the program list
not_bas_extension:
  pop esi
  mov eax, ext_string_1
  mov ebx, ext_string_2
  mov ecx, 0
  mov edx, 0                            ; One button for dialog box
  call os_dialog_box
  jmp app_selector                      ; Start over again...
                                        ; And now data for the above code...
kern_file_name db 'KERNEL32.BIN', 0
autorun_bin_file_name db 'AUTORUN.BIN', 0
autorun_bas_file_name db 'AUTORUN.BAS', 0
bin_ext db 'BIN'
bas_ext db 'BAS'
kerndlg_string_1 db 'Cannot load and execute MikeOS32 kernel!', 0
kerndlg_string_2 db 'KERNEL.BIN is the core of MikeOS32, and', 0
kerndlg_string_3 db 'is not a normal program.', 0
ext_string_1 db 'Invalid filename extension! You can', 0
ext_string_2 db 'only execute .BIN or .BAS programs.', 0
basic_finished_msg db '>>> BASIC program finished -- press a key', 0
; ------------------------------------------------------------------
; SYSTEM VARIABLES -- Settings for programs and system calls
                                        ; Time and date formatting
fmt_12_24 db 0                          ; Non-zero = 24-hr format
fmt_date: db 0, '/', 0, 0               ; 0, 1, 2 = M/D/Y, D/M/Y or Y/M/D
                                        ; Bit 7 = use name for months
                                        ; If bit 7 = 0, second byte = separator character

; ------------------------------------------------------------------
; FEATURES -- Code to pull into the kernel
include "features32/cli32.asm"
include "features32/disk32.asm"
include "features32/keyboard32.asm"
include "features32/math32.asm"
include "features32/misc32.asm"
include "features32/ports32.asm"
include "features32/screen32.asm"
include "features32/sound32.asm"
include "features32/string32.asm"
include "features32/basic32.asm"
; ==================================================================
; END OF KERNEL
; ==================================================================

