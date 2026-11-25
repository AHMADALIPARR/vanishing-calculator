<?xml version="1.0" encoding="UTF-8"?>
<!-- xslt/canonicalize.xsl : Semantics-preserving structural
     canonicalization of vanish XML.
     Strips ignorable whitespace between elements and normalizes the
     text of <integer> elements (leading zeros and surrounding space
     are removed), so that two spellings of the same expression produce
     the same bytes. The AST is otherwise copied unchanged. -->
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="xml" indent="no" omit-xml-declaration="yes"/>
  <xsl:strip-space elements="*"/>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="integer">
    <integer>
      <xsl:value-of select="number(normalize-space(.))"/>
    </integer>
  </xsl:template>

  <xsl:template match="symbol">
    <symbol><xsl:value-of select="normalize-space(.)"/></symbol>
  </xsl:template>

</xsl:stylesheet>
