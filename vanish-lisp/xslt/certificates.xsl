<?xml version="1.0" encoding="UTF-8"?>
<!--
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
-->
<!-- xslt/certificates.xsl : Emits the certificate XML for one compiled
     program: the target AST, the lowered program, the Lean certificate
     reference, and the SHA-256 digests of the AST and the program.
     The digests are supplied as parameters by the pipeline runner,
     which computes them with sha256sum over the exact artifact bytes;
     XSLT 1.0 has no hashing. The ast-hash is the digest of the AST
     XML, which becomes the .vanish.ast section bytes unchanged. The
     program-hash is the digest of the lowered program XML, the source
     the .vanish.text section is encoded from. The ELF writer
     recomputes both digests independently and refuses to write when
     they differ.
     Parameters: ast-uri, ast-hash, program-hash, lean-module,
     lean-theorem, generators, quotients, remainder. -->
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="xml" indent="no" omit-xml-declaration="yes"/>

  <xsl:param name="ast-uri"/>
  <xsl:param name="ast-hash"/>
  <xsl:param name="program-hash"/>
  <xsl:param name="lean-module">Vanish.Certificate</xsl:param>
  <xsl:param name="lean-theorem">cert_soundness</xsl:param>
  <xsl:param name="generators"/>
  <xsl:param name="quotients"/>
  <xsl:param name="remainder">0</xsl:param>

  <xsl:template match="/">
    <certificate>
      <target>
        <xsl:copy-of select="document($ast-uri)/*"/>
      </target>
      <program>
        <xsl:copy-of select="/program/instruction"/>
      </program>
      <lean>
        <module><xsl:value-of select="$lean-module"/></module>
        <theorem><xsl:value-of select="$lean-theorem"/></theorem>
      </lean>
      <witness>
        <generators><xsl:value-of select="$generators"/></generators>
        <quotients><xsl:value-of select="$quotients"/></quotients>
        <remainder><xsl:value-of select="$remainder"/></remainder>
      </witness>
      <hashes>
        <hash section=".vanish.ast" algorithm="sha256">
          <xsl:value-of select="$ast-hash"/>
        </hash>
        <hash section=".vanish.text" algorithm="sha256">
          <xsl:value-of select="$program-hash"/>
        </hash>
      </hashes>
    </certificate>
  </xsl:template>

</xsl:stylesheet>
