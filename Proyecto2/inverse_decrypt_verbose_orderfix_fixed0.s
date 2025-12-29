.include "constants_new.s"

.equ INPUT_ROW_MAJOR, 0  // 1: interpret hex strings as row-major matrix rows; 0: linear/column-major

.section .data
    msg_last_key: .asciz "Ingrese la última clave (ronda 10): "
        lenMsgLastKey = . - msg_last_key
    key_err_msg: .asciz "Error: Valor de clave incorrecto\n"
        lenKeyErr = . - key_err_msg
    newline: .asciz "\n"
    msg_inverse_title: .asciz " EXPANSIÓN INVERSA DE CLAVES"
        lenMsgInvTitle = . - msg_inverse_title
    msg_round_key: .asciz "\nClave Ronda "
        lenMsgRoundKey = . - msg_round_key
    msg_colon: .asciz ":\n"
    msg_original_key: .asciz "CLAVE ORIGINAL (Ronda 0) "
        lenMsgOriginal = . - msg_original_key
    msg_ciphertext: .asciz "\nIngrese el texto cifrado (32 hex / 16 bytes): "
        lenMsgCipher = . - msg_ciphertext
    msg_cipher_state: .asciz "\nCIPHERTEXT cargado (hex 4x4):\n"
        lenMsgCipherState = . - msg_cipher_state
    msg_plain_title: .asciz "\nPLAINTEXT (hex 4x4):\n"
        lenMsgPlainTitle = . - msg_plain_title
    msg_state_title: .asciz "\nESTADO (hex 4x4):\n"
        lenMsgStateTitle = . - msg_state_title
    msg_round_hdr: .asciz "\n--- RONDA "
        lenMsgRoundHdr = . - msg_round_hdr
    msg_after_isr: .asciz " despues InvShiftRows\n"
        lenMsgAfterISR = . - msg_after_isr
    msg_after_isb: .asciz " despues InvSubBytes\n"
        lenMsgAfterISB = . - msg_after_isb
    msg_after_ark: .asciz " despues AddRoundKey\n"
        lenMsgAfterARK = . - msg_after_ark
    msg_after_imc: .asciz " despues InvMixColumns\n"
        lenMsgAfterIMC = . - msg_after_imc

.section .bss
    lastKey: .space 16, 0          // Última clave (ronda 10)
    expandedKeys: .space 176, 0    // Todas las subclaves (11 claves de 16 bytes)
    buffer: .space 256, 0
    tempWord: .space 4, 0
    cipherState: .space 16, 0      // Estado (ciphertext) 16 bytes

.macro print fd, buffer, len
    mov x0, \fd
    ldr x1, =\buffer
    mov x2, \len
    mov x8, #64
    svc #0
.endm

.macro read fd, buffer, len
    mov x0, \fd
    ldr x1, =\buffer
    mov x2, \len
    mov x8, #63
    svc #0
.endm

.section .text

// Función para convertir clave hexadecimal
.type convertHexKey, %function
.global convertHexKey
convertHexKey:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    mov x29, sp
    read 0, buffer, 33
    ldr x1, =buffer
    ldr x2, =lastKey
    mov x3, #0
    mov x11, #0
convert_hex_loop:
    cmp x3, #16
    b.ge convert_hex_done
skip_non_hex:
    ldrb w4, [x1, x11]
    cmp w4, #0
    b.eq convert_hex_done
    cmp w4, #10
    b.eq convert_hex_done
    bl is_hex_char
    cmp w0, #1
    b.eq process_hex_pair
    add x11, x11, #1
    b skip_non_hex
process_hex_pair:
    ldrb w4, [x1, x11]
    add x11, x11, #1
    bl hex_char_to_nibble
    lsl w5, w0, #4
    ldrb w4, [x1, x11]
    add x11, x11, #1
    bl hex_char_to_nibble
    orr w5, w5, w0
    strb w5, [x2, x3]
    add x3, x3, #1
    b convert_hex_loop
convert_hex_done:
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
    .size convertHexKey, (. - convertHexKey)

is_hex_char:
    cmp w4, #'0'
    b.lt not_hex
    cmp w4, #'9'
    b.le is_hex
    orr w4, w4, #0x20
    cmp w4, #'a'
    b.lt not_hex
    cmp w4, #'f'
    b.le is_hex
not_hex:
    mov w0, #0
    ret
is_hex:
    mov w0, #1
    ret

hex_char_to_nibble:
    cmp w4, #'0'
    b.lt hex_error
    cmp w4, #'9'
    b.le hex_digit
    orr w4, w4, #0x20
    cmp w4, #'a'
    b.lt hex_error
    cmp w4, #'f'
    b.gt hex_error
    sub w0, w4, #'a'
    add w0, w0, #10
    ret
hex_digit:
    sub w0, w4, #'0'
    ret
hex_error:
    print 1, key_err_msg, lenKeyErr
    mov w0, #0
    ret

.type print_hex_byte, %function
print_hex_byte:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    and w1, w0, #0xF0
    lsr w1, w1, #4
    and w2, w0, #0x0F
    cmp w1, #10
    b.lt high_digit
    add w1, w1, #'A' - 10
    b high_done
high_digit:
    add w1, w1, #'0'
high_done:
    cmp w2, #10
    b.lt low_digit
    add w2, w2, #'A' - 10
    b low_done
low_digit:
    add w2, w2, #'0'
low_done:
    sub sp, sp, #16
    strb w1, [sp]
    strb w2, [sp, #1]
    mov w3, #' '
    strb w3, [sp, #2]
    mov x0, #1
    mov x1, sp
    mov x2, #3
    mov x8, #64
    svc #0
    add sp, sp, #16
    ldp x29, x30, [sp], #16
    ret
    .size print_hex_byte, (. - print_hex_byte)

.type printRoundNumber, %function
printRoundNumber:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #16
    cmp w0, #10
    b.lt single_digit
    mov w1, #'1'
    strb w1, [sp, #0]
    mov w1, #'0'
    strb w1, [sp, #1]
    mov x0, #1
    mov x1, sp
    mov x2, #2
    mov x8, #64
    svc #0
    b print_done
single_digit:
    add w0, w0, #'0'
    strb w0, [sp]
    mov x0, #1
    mov x1, sp
    mov x2, #1
    mov x8, #64
    svc #0
print_done:
    add sp, sp, #16
    ldp x29, x30, [sp], #16
    ret
    .size printRoundNumber, (. - printRoundNumber)

// Función para imprimir una clave (formato 4x4)
.type printKey, %function
printKey:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]
    mov x19, x0
    mov x20, #0
print_row_loop:
    cmp x20, #4
    b.ge print_key_done
    mov x21, #0
print_col_loop:
    cmp x21, #4
    b.ge print_row_end
    mov x2, #4
    mul x2, x21, x2
    add x2, x2, x20
    ldrb w0, [x19, x2]
    bl print_hex_byte
    add x21, x21, #1
    b print_col_loop
print_row_end:
    print 1, newline, 1
    add x20, x20, #1
    b print_row_loop
print_key_done:
    print 1, newline, 1
    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret
    .size printKey, (. - printKey)

// Remap 16 bytes in-place if input was provided row-major (rows concatenated)
// State internal is column-major (index = col*4 + row)
.type RemapRowMajorToColMajor, %function
.global RemapRowMajorToColMajor
RemapRowMajorToColMajor:
    // x0 = state (16 bytes)
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    // temp on stack [sp,#16..#31]
    // copy state -> temp
    mov x1, #0
1:
    cmp x1, #16
    b.ge 2f
    ldrb w2, [x0, x1]
    strb w2, [sp, #16]
    add x3, sp, #16
    strb w2, [x3, x1]
    add x1, x1, #1
    b 1b
2:
    // write back with mapping: temp[row*4 + col] -> state[col*4 + row]
    mov x1, #0            // row
3:
    cmp x1, #4
    b.ge 5f
    mov x4, #0            // col
4:
    cmp x4, #4
    b.ge 6f
    // src_i = row*4 + col
    mov x5, x1
    lsl x5, x5, #2
    add x5, x5, x4
    add x6, sp, #16
    ldrb w2, [x6, x5]
    // dst_i = col*4 + row
    mov x7, x4
    lsl x7, x7, #2
    add x7, x7, x1
    strb w2, [x0, x7]
    add x4, x4, #1
    b 4b
6:
    add x1, x1, #1
    b 3b
5:
    ldp x29, x30, [sp], #32
    ret
.size RemapRowMajorToColMajor, (. - RemapRowMajorToColMajor)


// RotWord: rotación hacia la izquierda
.type rotWord, %function
rotWord:
    ldrb w1, [x0, #0]
    ldrb w2, [x0, #1]
    ldrb w3, [x0, #2]
    ldrb w4, [x0, #3]
    strb w2, [x0, #0]
    strb w3, [x0, #1]
    strb w4, [x0, #2]
    strb w1, [x0, #3]
    ret
    .size rotWord, (. - rotWord)

// SubWord: aplicar S-box a cada byte
.type subWord, %function
subWord:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]
    mov x19, x0
    ldr x20, =Sbox
    mov x1, #0
subword_loop:
    cmp x1, #4
    b.ge subword_done
    ldrb w2, [x19, x1]
    uxtw x2, w2
    ldrb w3, [x20, x2]
    strb w3, [x19, x1]
    add x1, x1, #1
    b subword_loop
subword_done:
    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret
    .size subWord, (. - subWord)

// Función principal: expansión inversa de claves
// El proceso inverso es:
// Para cada palabra i desde 43 hasta 4:
//   Si i mod Nk == 0:
//     W[i-Nk] = W[i] XOR SubWord(RotWord(W[i-1])) XOR Rcon[i/Nk - 1]
//   Sino:
//     W[i-Nk] = W[i] XOR W[i-1]
.type inverseKeyExpansion, %function
.global inverseKeyExpansion
inverseKeyExpansion:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]
    str x21, [sp, #32]
    str x22, [sp, #40]
    str x23, [sp, #48]
    str x24, [sp, #56]
    str x25, [sp, #64]
    str x26, [sp, #72]
    str x27, [sp, #80]
    str x28, [sp, #88]
    
    ldr x19, =lastKey        // Puntero a última clave
    ldr x20, =expandedKeys   // Puntero a claves expandidas
    ldr x21, =Rcon           // Puntero a Rcon
    
    // Copiar la última clave (ronda 10) a expandedKeys[160-175]
    mov x22, #0
copy_last_key:
    cmp x22, #16
    b.ge inverse_loop_init
    ldrb w23, [x19, x22]
    add x24, x22, #160       // Offset para ronda 10 (palabra 40-43)
    strb w23, [x20, x24]
    add x22, x22, #1
    b copy_last_key

inverse_loop_init:
    mov x22, #43             // Empezar desde la palabra 43

inverse_loop:
    cmp x22, #3
    b.le inverse_done
    
    // Dirección de W[i] actual
    mov x24, #4
    mul x23, x22, x24
    add x23, x20, x23        // x23 = dirección de W[i]
    
    // Verificar si i es múltiplo de 4
    and x26, x22, #3
    cbnz x26, not_multiple_inv
    
    // i es múltiplo de 4 (Nk): aplicar transformación compleja
    // W[i-4] = W[i] XOR SubWord(RotWord(W[i-1])) XOR Rcon[i/4 - 1]
    
    // Obtener W[i-1]
    sub x24, x22, #1
    mov x25, #4
    mul x24, x24, x25
    add x24, x20, x24        // x24 = dirección de W[i-1]
    
    // Copiar W[i-1] a tempWord
    ldr x27, =tempWord
    ldrb w0, [x24, #0]
    strb w0, [x27, #0]
    ldrb w0, [x24, #1]
    strb w0, [x27, #1]
    ldrb w0, [x24, #2]
    strb w0, [x27, #2]
    ldrb w0, [x24, #3]
    strb w0, [x27, #3]
    
    // Aplicar RotWord
    mov x0, x27
    bl rotWord
    
    // Aplicar SubWord
    mov x0, x27
    bl subWord
    
    // XOR con Rcon[i/4 - 1]
    lsr x25, x22, #2         // i / 4
    sub x25, x25, #1         // (i/4) - 1
    mov x24, #4
    mul x25, x25, x24
    add x25, x21, x25        // x25 = dirección de Rcon[i/4 - 1]
    
    ldrb w0, [x27, #0]
    ldrb w1, [x25, #0]
    eor w0, w0, w1
    strb w0, [x27, #0]
    
    // Ahora tempWord = SubWord(RotWord(W[i-1])) XOR Rcon
    // W[i-4] = W[i] XOR tempWord
    sub x24, x22, #4
    mov x25, #4
    mul x24, x24, x25
    add x24, x20, x24        // x24 = dirección de W[i-4]
    
    // W[i-4] = W[i] XOR tempWord
    ldrb w0, [x23, #0]
    ldrb w1, [x27, #0]
    eor w0, w0, w1
    strb w0, [x24, #0]
    
    ldrb w0, [x23, #1]
    ldrb w1, [x27, #1]
    eor w0, w0, w1
    strb w0, [x24, #1]
    
    ldrb w0, [x23, #2]
    ldrb w1, [x27, #2]
    eor w0, w0, w1
    strb w0, [x24, #2]
    
    ldrb w0, [x23, #3]
    ldrb w1, [x27, #3]
    eor w0, w0, w1
    strb w0, [x24, #3]
    
    b continue_inverse

not_multiple_inv:
    // i NO es múltiplo de 4: W[i-4] = W[i] XOR W[i-1]
    sub x24, x22, #4
    mov x25, #4
    mul x24, x24, x25
    add x24, x20, x24        // x24 = dirección de W[i-4]
    
    sub x25, x22, #1
    mov x26, #4
    mul x25, x25, x26
    add x25, x20, x25        // x25 = dirección de W[i-1]
    
    // W[i-4] = W[i] XOR W[i-1]
    ldrb w0, [x23, #0]
    ldrb w1, [x25, #0]
    eor w0, w0, w1
    strb w0, [x24, #0]
    
    ldrb w0, [x23, #1]
    ldrb w1, [x25, #1]
    eor w0, w0, w1
    strb w0, [x24, #1]
    
    ldrb w0, [x23, #2]
    ldrb w1, [x25, #2]
    eor w0, w0, w1
    strb w0, [x24, #2]
    
    ldrb w0, [x23, #3]
    ldrb w1, [x25, #3]
    eor w0, w0, w1
    strb w0, [x24, #3]

continue_inverse:
    sub x22, x22, #1
    b inverse_loop

inverse_done:
    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldr x21, [sp, #32]
    ldr x22, [sp, #40]
    ldr x23, [sp, #48]
    ldr x24, [sp, #56]
    ldr x25, [sp, #64]
    ldr x26, [sp, #72]
    ldr x27, [sp, #80]
    ldr x28, [sp, #88]
    ldp x29, x30, [sp], #96
    ret
    .size inverseKeyExpansion, (. - inverseKeyExpansion)

// Función para imprimir todas las claves expandidas
// =======================
// AES-128 DECRYPT HELPERS
// =======================

// Convierte 32 chars hex (con o sin espacios) a 16 bytes en destino.
// x0 = destino (16 bytes)
.type convertHexBlock16, %function
.global convertHexBlock16
convertHexBlock16:
    // x0 = dst (16 bytes)
    // Uses a fixed 32-byte frame to keep stack sane even with syscalls.
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [sp, #16]          // save dst (because read returns in x0)

    // leer hasta 64 chars (32 hex + espacios + '\n')
    read 0, buffer, 65

    ldr x2, [sp, #16]          // dst
    ldr x1, =buffer            // src
    mov x3, #0                 // dst_index 0..15
    mov x11, #0                // src_index

.Lc16_loop:
    // stop if already wrote 16 bytes
    cmp x3, #16
    b.ge .Lc16_done

    // c = src[x11]
    ldrb w4, [x1, x11]
    // if c == 0 or '\n' => done
    cbz w4, .Lc16_done
    cmp w4, #10
    b.eq .Lc16_done
    // skip spaces
    cmp w4, #' '
    b.eq .Lc16_skip

    // hi nibble
    mov w0, w4
    bl hex_char_to_nibble
    // if invalid => skip
    cmp w0, #0xFF
    b.eq .Lc16_skip

    lsl w5, w0, #4

    // advance and get lo char
    add x11, x11, #1
    ldrb w4, [x1, x11]
    cbz w4, .Lc16_done
    cmp w4, #10
    b.eq .Lc16_done
    // if space, keep skipping until a hex appears
.Lc16_seek_lo:
    cmp w4, #' '
    b.ne .Lc16_have_lo
    add x11, x11, #1
    ldrb w4, [x1, x11]
    cbz w4, .Lc16_done
    cmp w4, #10
    b.eq .Lc16_done
    b .Lc16_seek_lo

.Lc16_have_lo:
    mov w0, w4
    bl hex_char_to_nibble
    cmp w0, #0xFF
    b.eq .Lc16_skip            // invalid => skip this pair
    orr w5, w5, w0
    strb w5, [x2, x3]
    add x3, x3, #1

.Lc16_skip:
    add x11, x11, #1
    b .Lc16_loop

.Lc16_done:
    ldp x29, x30, [sp], #32
    ret

.size convertHexBlock16, (. - convertHexBlock16)

// AddRoundKey: state[i] ^= roundKey[i]
// x0 = state (16B), x1 = roundKey (16B)
.type AddRoundKey, %function
.global AddRoundKey
AddRoundKey:
    mov x2, #0
1:  cmp x2, #16
    b.ge 2f
    ldrb w3, [x0, x2]
    ldrb w4, [x1, x2]
    eor w3, w3, w4
    strb w3, [x0, x2]
    add x2, x2, #1
    b 1b
2:  ret
    .size AddRoundKey, (. - AddRoundKey)

// InvSubBytes: state[i] = InvSbox[state[i]]
// x0 = state (16B)
.type InvSubBytes, %function
.global InvSubBytes
InvSubBytes:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ldr x1, =InvSbox
    mov x2, #0
1:  cmp x2, #16
    b.ge 2f
    ldrb w3, [x0, x2]
    uxtw x3, w3
    ldrb w4, [x1, x3]
    strb w4, [x0, x2]
    add x2, x2, #1
    b 1b
2:  ldp x29, x30, [sp], #16
    ret
    .size InvSubBytes, (. - InvSubBytes)

// InvShiftRows (column-major):
// row0: no shift
// row1: shift right 1
// row2: shift right 2
// row3: shift right 3
// x0 = state
.type InvShiftRows, %function
.global InvShiftRows
InvShiftRows:
    // Row1 indices: 1,5,9,13 -> [13,1,5,9]
    ldrb w1, [x0, #1]
    ldrb w2, [x0, #5]
    ldrb w3, [x0, #9]
    ldrb w4, [x0, #13]
    strb w4, [x0, #1]
    strb w1, [x0, #5]
    strb w2, [x0, #9]
    strb w3, [x0, #13]

    // Row2 indices: 2,6,10,14 -> [10,14,2,6]
    ldrb w1, [x0, #2]
    ldrb w2, [x0, #6]
    ldrb w3, [x0, #10]
    ldrb w4, [x0, #14]
    strb w3, [x0, #2]
    strb w4, [x0, #6]
    strb w1, [x0, #10]
    strb w2, [x0, #14]

    // Row3 indices: 3,7,11,15 -> right3 == left1 => [7,11,15,3]
    ldrb w1, [x0, #3]
    ldrb w2, [x0, #7]
    ldrb w3, [x0, #11]
    ldrb w4, [x0, #15]
    strb w2, [x0, #3]
    strb w3, [x0, #7]
    strb w4, [x0, #11]
    strb w1, [x0, #15]
    ret
    .size InvShiftRows, (. - InvShiftRows)

// xtime: multiplica por 2 en GF(2^8) con polinomio 0x11B
// w0 = a (byte), devuelve w0
.type xtime, %function
xtime:
    and w1, w0, #0x80
    lsl w0, w0, #1
    and w0, w0, #0xFF
    cbz w1, 1f
    mov w2, #0x1B
    eor w0, w0, w2
1:  ret
    .size xtime, (. - xtime)

// Multiplicaciones por constantes usadas en InvMixColumns
// w0 = a, devuelve w0 = a * {09,0B,0D,0E} según w1
.type gf_mul_const, %function
gf_mul_const:
    // Guarda LR porque esta función llama a xtime (BL pisa x30)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    // guardar constante porque xtime pisa w1 y el valor original (a) porque xtime pisa w2
    mov w6, w1
    mov w7, w0
    // calcula a2,a4,a8
    bl xtime        // w0 = a2
    mov w3, w0
    mov w0, w3
    bl xtime        // w0 = a4
    mov w4, w0
    mov w0, w4
    bl xtime        // w0 = a8
    mov w5, w0

    // select
    cmp w6, #0x09
    b.eq 9f
    cmp w6, #0x0B
    b.eq 11f
    cmp w6, #0x0D
    b.eq 13f
    // 0x0E
14:
    eor w0, w5, w4     // a8 ^ a4
    eor w0, w0, w3     // ^ a2
    b 99f
9:
    eor w0, w5, w7     // a8 ^ a
    b 99f
11:
    eor w0, w5, w3     // a8 ^ a2
    eor w0, w0, w7     // ^ a
    b 99f
13:
    eor w0, w5, w4     // a8 ^ a4
    eor w0, w0, w7     // ^ a
    b 99f
99:
    ldp x29, x30, [sp], #16
    ret
    .size gf_mul_const, (. - gf_mul_const)

// InvMixColumns: opera columna por columna (4)
// x0 = state
.type InvMixColumns, %function
.global InvMixColumns
InvMixColumns:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    // Preserve callee-saved regs we clobber (x20-x27)
    stp x20, x21, [sp, #-16]!
    stp x22, x23, [sp, #-16]!
    stp x24, x25, [sp, #-16]!
    stp x26, x27, [sp, #-16]!
    mov x9, x0              // preservar puntero state (x0 se usa para args)
    mov x10, #0              // col = 0..3
col_loop:
    cmp x10, #4
    b.ge done
    // base = col*4
    lsl x11, x10, #2

    // s0..s3
    ldrb w20, [x9, x11]          // row0
    add x12, x11, #1
    ldrb w21, [x9, x12]          // row1
    add x13, x11, #2
    ldrb w22, [x9, x13]          // row2
    add x14, x11, #3
    ldrb w23, [x9, x14]          // row3

    // t0 = 0E*s0 ^ 0B*s1 ^ 0D*s2 ^ 09*s3
    mov w0, w20
     mov w1, #0x0E
     bl gf_mul_const
     mov w24, w0
    mov w0, w21
     mov w1, #0x0B
     bl gf_mul_const
     eor w24, w24, w0
    mov w0, w22
     mov w1, #0x0D
     bl gf_mul_const
     eor w24, w24, w0
    mov w0, w23
     mov w1, #0x09
     bl gf_mul_const
     eor w24, w24, w0

    // t1 = 09*s0 ^ 0E*s1 ^ 0B*s2 ^ 0D*s3
    mov w0, w20
     mov w1, #0x09
     bl gf_mul_const
     mov w25, w0
    mov w0, w21
     mov w1, #0x0E
     bl gf_mul_const
     eor w25, w25, w0
    mov w0, w22
     mov w1, #0x0B
     bl gf_mul_const
     eor w25, w25, w0
    mov w0, w23
     mov w1, #0x0D
     bl gf_mul_const
     eor w25, w25, w0

    // t2 = 0D*s0 ^ 09*s1 ^ 0E*s2 ^ 0B*s3
    mov w0, w20
     mov w1, #0x0D
     bl gf_mul_const
     mov w26, w0
    mov w0, w21
     mov w1, #0x09
     bl gf_mul_const
     eor w26, w26, w0
    mov w0, w22
     mov w1, #0x0E
     bl gf_mul_const
     eor w26, w26, w0
    mov w0, w23
     mov w1, #0x0B
     bl gf_mul_const
     eor w26, w26, w0

    // t3 = 0B*s0 ^ 0D*s1 ^ 09*s2 ^ 0E*s3
    mov w0, w20
     mov w1, #0x0B
     bl gf_mul_const
     mov w27, w0
    mov w0, w21
     mov w1, #0x0D
     bl gf_mul_const
     eor w27, w27, w0
    mov w0, w22
     mov w1, #0x09
     bl gf_mul_const
     eor w27, w27, w0
    mov w0, w23
     mov w1, #0x0E
     bl gf_mul_const
     eor w27, w27, w0

    // store back
    strb w24, [x9, x11]
    add x12, x11, #1
    strb w25, [x9, x12]
    add x13, x11, #2
    strb w26, [x9, x13]
    add x14, x11, #3
    strb w27, [x9, x14]

    add x10, x10, #1
    b col_loop
done:
    // Restore callee-saved regs
    ldp x26, x27, [sp], #16
    ldp x24, x25, [sp], #16
    ldp x22, x23, [sp], #16
    ldp x20, x21, [sp], #16
    ldp x29, x30, [sp], #16
    ret
    .size InvMixColumns, (. - InvMixColumns)

// AES-128 Decrypt (1 bloque)
// x0 = state (16B) con ciphertext en column-major
// x1 = expandedKeys (176B): round0 en offset0, ..., round10 en offset160
.type AES128_DecryptBlock, %function
.global AES128_DecryptBlock
AES128_DecryptBlock:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]
    mov x19, x0          // state
    mov x20, x1          // keys base

    // Ronda inicial (10): AddRoundKey con offset 160
    add x1, x20, #160
    mov x0, x19
    bl AddRoundKey
    // DEBUG: estado despues AddRoundKey (ronda 10)
    print 1, msg_round_hdr, lenMsgRoundHdr
    mov w0, #10
    bl printRoundNumber
    print 1, msg_after_ark, lenMsgAfterARK
    print 1, msg_state_title, lenMsgStateTitle
    mov x0, x19
    mov w22, w21
    bl printKey
    mov w21, w22

    // Rondas 9..1
    mov w21, #9
round_loop:
    cmp w21, #1
    b.lt final_round
    // DEBUG: inicio de ronda r
    print 1, msg_round_hdr, lenMsgRoundHdr
    mov w0, w21
    bl printRoundNumber

    mov x0, x19
    bl InvShiftRows
    // DEBUG: estado despues InvShiftRows
    print 1, msg_after_isr, lenMsgAfterISR
    print 1, msg_state_title, lenMsgStateTitle
    mov x0, x19
    mov w22, w21
    bl printKey
    mov w21, w22
    mov x0, x19
    bl InvSubBytes
    // DEBUG: estado despues InvSubBytes
    print 1, msg_after_isb, lenMsgAfterISB
    print 1, msg_state_title, lenMsgStateTitle
    mov x0, x19
    mov w22, w21
    bl printKey
    mov w21, w22

    // AddRoundKey con round r (offset r*16)
    mov x0, x19
    uxtw x2, w21
    lsl x2, x2, #4       // *16
    add x1, x20, x2
    bl AddRoundKey
    // DEBUG: estado despues AddRoundKey
    print 1, msg_after_ark, lenMsgAfterARK
    print 1, msg_state_title, lenMsgStateTitle
    mov x0, x19
    mov w22, w21
    bl printKey
    mov w21, w22

    mov x0, x19
    bl InvMixColumns
    // DEBUG: estado despues InvMixColumns
    print 1, msg_after_imc, lenMsgAfterIMC
    print 1, msg_state_title, lenMsgStateTitle
    mov x0, x19
    mov w22, w21
    bl printKey
    mov w21, w22

    sub w21, w21, #1
    b round_loop

final_round:
    // DEBUG: inicio de ronda 0
    print 1, msg_round_hdr, lenMsgRoundHdr
    mov w0, #0
    bl printRoundNumber
    mov x0, x19
    bl InvShiftRows
    // DEBUG: estado despues InvShiftRows
    print 1, msg_after_isr, lenMsgAfterISR
    print 1, msg_state_title, lenMsgStateTitle
    mov x0, x19
    mov w22, w21
    bl printKey
    mov w21, w22
    mov x0, x19
    bl InvSubBytes
    // DEBUG: estado despues InvSubBytes
    print 1, msg_after_isb, lenMsgAfterISB
    print 1, msg_state_title, lenMsgStateTitle
    mov x0, x19
    mov w22, w21
    bl printKey
    mov w21, w22
    mov x0, x19
    mov x1, x20          // round0
    bl AddRoundKey
    // DEBUG: estado despues AddRoundKey
    print 1, msg_after_ark, lenMsgAfterARK
    print 1, msg_state_title, lenMsgStateTitle
    mov x0, x19
    mov w22, w21
    bl printKey
    mov w21, w22

    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret
    .size AES128_DecryptBlock, (. - AES128_DecryptBlock)

.type printAllKeys, %function
printAllKeys:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]
    
    print 1, msg_inverse_title, lenMsgInvTitle
    
    ldr x19, =expandedKeys
    mov x20, #10
    
print_keys_loop:
    cmp x20, #0
    b.lt print_original
    
    print 1, msg_round_key, lenMsgRoundKey
    mov w0, w20
    bl printRoundNumber
    print 1, msg_colon, 2
    
    mov x21, #16
    mul x21, x20, x21
    add x0, x19, x21
    bl printKey
    
    sub x20, x20, #1
    b print_keys_loop

print_original:
    print 1, msg_original_key, lenMsgOriginal
    mov x0, x19
    bl printKey
    
    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret
    .size printAllKeys, (. - printAllKeys)

.type _start, %function
.global _start
_start:
    // 1) Leer última subclave (ronda 10) y generar todas las subclaves en expandedKeys
    print 1, msg_last_key, lenMsgLastKey
    bl convertHexKey
    bl inverseKeyExpansion
    bl printAllKeys

    // 2) Leer ciphertext (16 bytes hex) a cipherState
    print 1, msg_ciphertext, lenMsgCipher
    ldr x0, =cipherState
    bl convertHexBlock16


    // DEBUG: mostrar ciphertext como estado interno
    .if INPUT_ROW_MAJOR
        ldr x0, =cipherState
        bl RemapRowMajorToColMajor
    .endif
    print 1, msg_cipher_state, lenMsgCipherState
    ldr x0, =cipherState
    bl printKey
    // 3) Desencriptar (AES-128)
    ldr x0, =cipherState
    ldr x1, =expandedKeys
    bl AES128_DecryptBlock

    // 4) Imprimir plaintext (hex 4x4 column-major)
    print 1, msg_plain_title, lenMsgPlainTitle
    ldr x0, =cipherState
    bl printKey

    mov x0, #0
    mov x8, #93
    svc #0
    .size _start, (. - _start)
