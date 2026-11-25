/*
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
*/

/* elf/abi/elfio.c -- Minimal ELF64 container read/write. */
#include "elfio.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ELF_MAGIC0 0x7fu
#define ELF_MAGIC1 'E'
#define ELF_MAGIC2 'L'
#define ELF_MAGIC3 'F'
#define ELFCLASS64 2u
#define ELFDATA2LSB 1u
#define EV_CURRENT 1u
#define ET_REL 1u
#define EM_X86_64 62u
#define SHT_NULL 0u
#define SHT_PROGBITS 1u
#define SHT_STRTAB 3u
#define SHT_NOTE 7u

static uint16_t rd16(const uint8_t *p) {
  return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}
static uint32_t rd32(const uint8_t *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
         ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static uint64_t rd64(const uint8_t *p) {
  return (uint64_t)rd32(p) | ((uint64_t)rd32(p + 4) << 32);
}
static void wr16(uint8_t *p, uint16_t v) {
  p[0] = (uint8_t)(v & 0xffu);
  p[1] = (uint8_t)((v >> 8) & 0xffu);
}
static void wr32(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)(v & 0xffu);
  p[1] = (uint8_t)((v >> 8) & 0xffu);
  p[2] = (uint8_t)((v >> 16) & 0xffu);
  p[3] = (uint8_t)((v >> 24) & 0xffu);
}
static void wr64(uint8_t *p, uint64_t v) {
  wr32(p, (uint32_t)(v & 0xffffffffu));
  wr32(p + 4, (uint32_t)(v >> 32));
}

static uint8_t *read_all(const char *path, size_t *len_out, char *err, size_t errsz) {
  FILE *f = fopen(path, "rb");
  uint8_t *buf;
  size_t len, got;
  if (!f) {
    snprintf(err, errsz, "cannot open %s", path);
    return NULL;
  }
  fseek(f, 0, SEEK_END);
  len = (size_t)ftell(f);
  fseek(f, 0, SEEK_SET);
  buf = (uint8_t *)malloc(len ? len : 1);
  if (!buf) {
    snprintf(err, errsz, "out of memory");
    fclose(f);
    return NULL;
  }
  got = fread(buf, 1, len, f);
  fclose(f);
  if (got != len) {
    snprintf(err, errsz, "short read on %s", path);
    free(buf);
    return NULL;
  }
  *len_out = len;
  return buf;
}

int elf_read_file(const char *path, elf_file_t *out, char *err, size_t errsz) {
  uint8_t *buf;
  size_t len, i;
  uint64_t shoff;
  uint16_t shentsize, shnum, shstrndx;
  const uint8_t *shstr;
  size_t shstr_size = 0;

  memset(out, 0, sizeof(*out));
  buf = read_all(path, &len, err, errsz);
  if (!buf) return -1;
  if (len < 64 || buf[0] != ELF_MAGIC0 || buf[1] != ELF_MAGIC1 ||
      buf[2] != ELF_MAGIC2 || buf[3] != ELF_MAGIC3 ||
      buf[4] != ELFCLASS64 || buf[5] != ELFDATA2LSB || buf[6] != EV_CURRENT) {
    snprintf(err, errsz, "%s is not an ELF64 little-endian file", path);
    free(buf);
    return -1;
  }
  if (rd16(buf + 16) != ET_REL) {
    snprintf(err, errsz, "%s is not an ET_REL object", path);
    free(buf);
    return -1;
  }
  shoff = rd64(buf + 40);
  shentsize = rd16(buf + 58);
  shnum = rd16(buf + 60);
  shstrndx = rd16(buf + 62);
  if (shentsize != 64 || shnum == 0 || shoff + (uint64_t)shnum * 64 > len) {
    snprintf(err, errsz, "%s has a bad section header table", path);
    free(buf);
    return -1;
  }
  if (shstrndx >= shnum) {
    snprintf(err, errsz, "%s has a bad shstrndx", path);
    free(buf);
    return -1;
  }
  {
    const uint8_t *sh = buf + shoff + (size_t)shstrndx * 64;
    uint64_t off = rd64(sh + 24);
    shstr_size = (size_t)rd64(sh + 32);
    if (off + shstr_size > len) {
      snprintf(err, errsz, "%s has a bad string table", path);
      free(buf);
      return -1;
    }
    shstr = buf + off;
  }
  out->sections = (elf_section_t *)calloc(shnum, sizeof(elf_section_t));
  if (!out->sections) {
    snprintf(err, errsz, "out of memory");
    free(buf);
    return -1;
  }
  out->nsections = shnum;
  for (i = 0; i < shnum; i++) {
    const uint8_t *sh = buf + shoff + i * 64;
    uint32_t nameoff = rd32(sh);
    uint64_t off, size;
    elf_section_t *s = &out->sections[i];
    if (nameoff >= shstr_size) {
      snprintf(err, errsz, "%s has a bad section name offset", path);
      elf_free(out);
      free(buf);
      return -1;
    }
    s->name = strdup((const char *)(shstr + nameoff));
    s->type = rd32(sh + 4);
    s->flags = rd64(sh + 8);
    off = rd64(sh + 24);
    size = rd64(sh + 32);
    s->size = size;
    if (size > 0) {
      if (off + size > len) {
        snprintf(err, errsz, "%s has a section past end of file", path);
        elf_free(out);
        free(buf);
        return -1;
      }
      s->data = (uint8_t *)malloc(size);
      if (!s->data) {
        snprintf(err, errsz, "out of memory");
        elf_free(out);
        free(buf);
        return -1;
      }
      memcpy(s->data, buf + off, size);
    } else {
      s->data = NULL;
    }
  }
  free(buf);
  return 0;
}

const elf_section_t *elf_find(const elf_file_t *f, const char *name) {
  size_t i;
  for (i = 0; i < f->nsections; i++) {
    if (strcmp(f->sections[i].name, name) == 0) return &f->sections[i];
  }
  return NULL;
}

void elf_free(elf_file_t *f) {
  size_t i;
  if (!f) return;
  for (i = 0; i < f->nsections; i++) {
    free(f->sections[i].name);
    free(f->sections[i].data);
  }
  free(f->sections);
  f->sections = NULL;
  f->nsections = 0;
}

int elf_write_file(const char *path, const elf_section_t *sections,
                   size_t nsections, char *err, size_t errsz) {
  /* Layout: header, section data (8-aligned), section headers.
   * The caller passes the real sections; the writer adds the null
   * section and .shstrtab. */
  size_t total = nsections + 2; /* null + shstrtab */
  uint8_t *shstr = NULL;
  size_t shstr_size = 1, i;
  uint32_t *name_offs = NULL;
  uint64_t *data_offs = NULL;
  uint64_t pos, shoff;
  FILE *f = NULL;
  uint8_t hdr[64];
  int rc = -1;

  name_offs = (uint32_t *)calloc(total, sizeof(uint32_t));
  data_offs = (uint64_t *)calloc(total, sizeof(uint64_t));
  if (!name_offs || !data_offs) {
    snprintf(err, errsz, "out of memory");
    goto done;
  }
  /* Build .shstrtab: "\0" + names + ".shstrtab\0". Index 1 is .shstrtab
   * itself, index 2.. are the caller sections in order. */
  for (i = 0; i < nsections; i++) shstr_size += strlen(sections[i].name) + 1;
  shstr_size += strlen(".shstrtab") + 1;
  shstr = (uint8_t *)calloc(shstr_size, 1);
  if (!shstr) {
    snprintf(err, errsz, "out of memory");
    goto done;
  }
  {
    size_t p = 1;
    memcpy(shstr + p, ".shstrtab", 10);
    name_offs[1] = 1;
    p += 11;
    for (i = 0; i < nsections; i++) {
      size_t l = strlen(sections[i].name);
      memcpy(shstr + p, sections[i].name, l);
      name_offs[2 + i] = (uint32_t)p;
      p += l + 1;
    }
  }
  pos = 64;
  for (i = 0; i < nsections; i++) {
    if (pos % 8) pos += 8 - (pos % 8);
    data_offs[2 + i] = pos;
    pos += sections[i].size;
  }
  if (pos % 8) pos += 8 - (pos % 8);
  data_offs[1] = pos;
  pos += shstr_size;
  if (pos % 8) pos += 8 - (pos % 8);
  shoff = pos;

  f = fopen(path, "wb");
  if (!f) {
    snprintf(err, errsz, "cannot open %s for writing", path);
    goto done;
  }
  memset(hdr, 0, sizeof(hdr));
  hdr[0] = ELF_MAGIC0; hdr[1] = ELF_MAGIC1; hdr[2] = ELF_MAGIC2; hdr[3] = ELF_MAGIC3;
  hdr[4] = ELFCLASS64; hdr[5] = ELFDATA2LSB; hdr[6] = EV_CURRENT;
  wr16(hdr + 16, ET_REL);
  wr16(hdr + 18, EM_X86_64);
  wr32(hdr + 20, EV_CURRENT);
  wr64(hdr + 40, shoff);
  wr16(hdr + 52, 64); /* ehsize */
  wr16(hdr + 58, 64); /* shentsize */
  wr16(hdr + 60, (uint16_t)total);
  wr16(hdr + 62, 1); /* shstrndx */
  if (fwrite(hdr, 1, 64, f) != 64) goto write_fail;
  for (i = 0; i < nsections; i++) {
    uint64_t want = data_offs[2 + i];
    long here = ftell(f);
    if (here < 0 || (uint64_t)here > want) goto write_fail;
    while ((uint64_t)here < want) {
      if (fputc(0, f) == EOF) goto write_fail;
      here++;
    }
    if (sections[i].size > 0 &&
        fwrite(sections[i].data, 1, sections[i].size, f) != sections[i].size) {
      goto write_fail;
    }
  }
  {
    long here = ftell(f);
    if (here < 0 || (uint64_t)here > data_offs[1]) goto write_fail;
    while ((uint64_t)here < data_offs[1]) {
      if (fputc(0, f) == EOF) goto write_fail;
      here++;
    }
    if (fwrite(shstr, 1, shstr_size, f) != shstr_size) goto write_fail;
    here = ftell(f);
    if (here < 0 || (uint64_t)here > shoff) goto write_fail;
    while ((uint64_t)here < shoff) {
      if (fputc(0, f) == EOF) goto write_fail;
      here++;
    }
  }
  for (i = 0; i < total; i++) {
    uint8_t sh[64];
    memset(sh, 0, sizeof(sh));
    if (i == 0) {
      /* null section header */
    } else if (i == 1) {
      wr32(sh, name_offs[1]);
      wr32(sh + 4, SHT_STRTAB);
      wr64(sh + 24, data_offs[1]);
      wr64(sh + 32, shstr_size);
    } else {
      const elf_section_t *s = &sections[i - 2];
      wr32(sh, name_offs[i]);
      wr32(sh + 4, s->type);
      wr64(sh + 8, s->flags);
      wr64(sh + 24, data_offs[i]);
      wr64(sh + 32, s->size);
    }
    if (fwrite(sh, 1, 64, f) != 64) goto write_fail;
  }
  rc = 0;
  goto done;
write_fail:
  snprintf(err, errsz, "write failed on %s", path);
done:
  if (f) fclose(f);
  free(shstr);
  free(name_offs);
  free(data_offs);
  return rc;
}
