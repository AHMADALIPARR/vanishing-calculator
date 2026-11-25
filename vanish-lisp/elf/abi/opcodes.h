/* elf/abi/opcodes.h -- Shared opcode and section constants for the
 * VANISH-LISP ELF ABI. The writer, loader, linker and VM all include
 * this header, so the instruction set is defined exactly once. The
 * layout follows the NOVA-ELF pattern: a standard ELF64 container
 * holding custom sections, with Load(ELF(M)) = M verified by the
 * loader round-trip.
 *
 * Instruction encoding: 9 bytes each, little-endian.
 *   byte 0: opcode
 *   bytes 1-8: int64 operand (symbol-table index for PUSH_SYMBOL,
 *   integer value for PUSH_INT, zero otherwise).
 */
#ifndef VANISH_OPCODES_H
#define VANISH_OPCODES_H

#include <stdint.h>

#define VANISH_ABI_VERSION 1u
#define VANISH_INSTR_SIZE 9u

/* Opcodes. These numbers are the ABI; the XSLT lowering (xslt/lower.xsl),
 * the Lean model (lean/Vanish/Pipeline.lean) and the VM (vm/vanish-vm.c)
 * all use the same names in the same order. */
#define OP_PUSH_SYMBOL  0x01u
#define OP_PUSH_INT     0x02u
#define OP_DUP          0x03u
#define OP_ADD          0x04u
#define OP_SUB          0x05u
#define OP_MUL          0x06u
#define OP_POW          0x07u
#define OP_NORMALIZE    0x08u
#define OP_ASSERT_ZERO  0x09u
#define OP_VERIFY_PROOF 0x0Au
#define OP_HALT         0x0Bu

/* Section names. */
#define SEC_TEXT  ".vanish.text"
#define SEC_AST   ".vanish.ast"
#define SEC_PROOF ".vanish.proof"
#define SEC_SYM   ".vanish.sym"
#define SEC_HASH  ".vanish.hash"
#define SEC_NOTE  ".note.vanish"
#define SEC_SHSTR ".shstrtab"

/* .note.vanish: name "vanish", type NT_VANISH_ABI, descriptor holds the
 * ABI version (u32), zero flags (u32) and eight reserved zero bytes. */
#define NOTE_NAME "vanish"
#define NT_VANISH_ABI 1u
#define NOTE_DESC_SIZE 16u

/* Opcode name, for traces and dumps. Returns "UNKNOWN" for other values. */
static inline const char *vanish_op_name(uint8_t op) {
  switch (op) {
    case OP_PUSH_SYMBOL:  return "PUSH_SYMBOL";
    case OP_PUSH_INT:     return "PUSH_INT";
    case OP_DUP:          return "DUP";
    case OP_ADD:          return "ADD";
    case OP_SUB:          return "SUB";
    case OP_MUL:          return "MUL";
    case OP_POW:          return "POW";
    case OP_NORMALIZE:    return "NORMALIZE";
    case OP_ASSERT_ZERO:  return "ASSERT_ZERO";
    case OP_VERIFY_PROOF: return "VERIFY_PROOF";
    case OP_HALT:         return "HALT";
    default:              return "UNKNOWN";
  }
}

#endif /* VANISH_OPCODES_H */
