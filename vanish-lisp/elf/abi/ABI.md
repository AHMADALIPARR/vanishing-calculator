# VANISH-LISP ELF ABI

The compiled binary container for the VANISH-LISP stack is a standard
ELF64 little-endian relocatable object (ET_REL, EM_X86_64). It carries
the symbolic program, its AST, its proof certificate, its symbol
table and its integrity digests as custom sections. The layout follows
the NOVA-ELF pattern: a standard container holding custom sections,
with Load(ELF(M)) = M verified by the loader round-trip.

## Sections

| Section | Contents |
| :--- | :--- |
| `.vanish.text` | Stack-machine instructions, 9 bytes each |
| `.vanish.ast` | The canonical vanish XML AST, exact bytes |
| `.vanish.proof` | The certificate XML, exact bytes |
| `.vanish.sym` | Symbol table, NUL-separated names in first-use order |
| `.vanish.hash` | SHA-256 digests, one `"<hex>  <section>"` line per section |
| `.note.vanish` | ABI version and metadata (ELF note, name `vanish`, type 1) |
| `.shstrtab` | Section-name string table |

## Instruction encoding

Each instruction is 9 bytes: one opcode byte followed by an int64
little-endian operand. PUSH_SYMBOL carries a symbol-table index.
PUSH_INT carries the integer value. All other instructions carry zero.

| Opcode | Value | Operand |
| :--- | :--- | :--- |
| PUSH_SYMBOL | 0x01 | symbol-table index |
| PUSH_INT | 0x02 | integer value |
| DUP | 0x03 | 0 |
| ADD | 0x04 | 0 |
| SUB | 0x05 | 0 |
| MUL | 0x06 | 0 |
| POW | 0x07 | 0 |
| NORMALIZE | 0x08 | 0 |
| ASSERT_ZERO | 0x09 | 0 |
| VERIFY_PROOF | 0x0A | 0 |
| HALT | 0x0B | 0 |

## Integrity

`.vanish.hash` holds the SHA-256 digest of `.vanish.text`,
`.vanish.ast`, `.vanish.proof` and `.vanish.sym`. The writer
recomputes the digests and refuses to seal a certificate whose hashes
disagree with the artifacts. The loader and the VM recompute the
digests on every load and refuse to run when any digest disagrees.
The `.note.vanish` descriptor holds the ABI version (u32), zero flags
(u32) and eight reserved zero bytes; the loader rejects any other
version.

## Linking

The linker concatenates two modules: the first module's trailing
HALT is dropped so execution continues into the second module, the
symbol tables are unioned with the second module's PUSH_SYMBOL
operands remapped, the AST and proof sections are concatenated in
order, and the digests are recomputed. The linked `.vanish.ast`
holds the two AST documents in sequence.
