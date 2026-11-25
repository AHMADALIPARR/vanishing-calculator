/* elf/abi/elfio.h -- Minimal ELF64 container read/write for the
 * VANISH-LISP ABI. Only the parts the writer, loader, linker and VM
 * need: section headers, section names, section bytes. All integers
 * are read and written little-endian, explicitly. */
#ifndef VANISH_ELFIO_H
#define VANISH_ELFIO_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
  char *name;        /* section name (owned) */
  uint32_t type;     /* SHT_* */
  uint64_t flags;    /* SHF_* */
  uint8_t *data;     /* section bytes (owned) */
  uint64_t size;     /* section size */
} elf_section_t;

typedef struct {
  elf_section_t *sections; /* section 0 is the null section */
  size_t nsections;
} elf_file_t;

/* Read an ELF64 little-endian file. Returns 0 on success, -1 on
 * failure with a message in err (errsz bytes). */
int elf_read_file(const char *path, elf_file_t *out, char *err, size_t errsz);

/* Write an ELF64 little-endian relocatable object (ET_REL, EM_X86_64)
 * holding the given sections. A .shstrtab is built from the names.
 * Returns 0 on success, -1 on failure with a message in err. */
int elf_write_file(const char *path, const elf_section_t *sections,
                   size_t nsections, char *err, size_t errsz);

/* Find a section by name, or NULL. */
const elf_section_t *elf_find(const elf_file_t *f, const char *name);

void elf_free(elf_file_t *f);

#endif /* VANISH_ELFIO_H */
