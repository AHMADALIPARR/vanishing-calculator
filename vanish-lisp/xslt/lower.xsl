<?xml version="1.0" encoding="UTF-8"?>
<!-- xslt/lower.xsl : Declarative compiler lowering: vanish XML to the
     stack-machine program.
     The root template and the symbol and sub templates are as supplied.
     DECISION (2026-11-24): the supplied example program was the minimal
     illustration, ending in ASSERT_ZERO and HALT. The completed lowering
     emits the full trailing sequence NORMALIZE, ASSERT_ZERO, VERIFY_PROOF,
     HALT, matching the ELF proposal's instruction list, so that the Lean
     verification step has something to verify and the VM's VERIFY_PROOF
     has a certificate to check. The add, mul, pow and integer templates
     are the completion of the same lowering. -->
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="xml" indent="no" omit-xml-declaration="yes"/>

  <xsl:template match="/">
    <program>
      <xsl:apply-templates/>
      <instruction opcode="NORMALIZE"/>
      <instruction opcode="ASSERT_ZERO"/>
      <instruction opcode="VERIFY_PROOF"/>
      <instruction opcode="HALT"/>
    </program>
  </xsl:template>

  <xsl:template match="vanish|expr">
    <xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="symbol">
    <instruction opcode="PUSH_SYMBOL">
      <xsl:value-of select="."/>
    </instruction>
  </xsl:template>

  <xsl:template match="integer">
    <instruction opcode="PUSH_INT">
      <xsl:value-of select="."/>
    </instruction>
  </xsl:template>

  <xsl:template match="sub">
    <xsl:apply-templates/>
    <instruction opcode="SUB"/>
  </xsl:template>

  <xsl:template match="add">
    <xsl:apply-templates/>
    <instruction opcode="ADD"/>
  </xsl:template>

  <xsl:template match="mul">
    <xsl:apply-templates/>
    <instruction opcode="MUL"/>
  </xsl:template>

  <xsl:template match="pow">
    <xsl:apply-templates/>
    <instruction opcode="POW"/>
  </xsl:template>

</xsl:stylesheet>
