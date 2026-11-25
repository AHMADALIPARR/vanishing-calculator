<?xml version="1.0" encoding="UTF-8"?>
<!--
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
-->
<!-- openmath/openmath-to-vanish.xsl : OpenMath to vanish XML.
     The OpenMath-to-Lisp mapping is the spec: OMA application, OMS
     operator, OMV variable, OMI integer. The vanish fragment is the
     polynomial core: arith1 minus/plus/times/power and the vanish1
     vanishes wrapper. OMF, OMBIND, OMBVAR, OMATTR and OMR have no
     counterpart in the vanish grammar, so they are reported with
     xsl:message and dropped rather than silently mistranslated. -->
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="xml" indent="no" omit-xml-declaration="yes"/>

  <xsl:template match="OMOBJ">
    <vanish>
      <expr>
        <xsl:apply-templates select="*[1]"/>
      </expr>
    </vanish>
  </xsl:template>

  <!-- The vanishes wrapper contributes the <vanish> root; its argument
       is the expression. -->
  <xsl:template match="OMA[OMS[@cd='vanish1' and @name='vanishes']]">
    <xsl:apply-templates select="*[2]"/>
  </xsl:template>

  <!-- An equation eq(e, 0) is the vanishing assertion for e: convert
       the left-hand side as the expression. -->
  <xsl:template match="OMA[OMS[@cd='relation1' and @name='eq']]">
    <xsl:message>openmath-to-vanish: equation read as a vanishing assertion; converting the left-hand side</xsl:message>
    <xsl:apply-templates select="*[2]"/>
  </xsl:template>

  <!-- Any other application has no vanish-grammar counterpart: report
       it and drop it instead of letting the built-in templates emit
       malformed output. -->
  <xsl:template match="OMA">
    <xsl:message>
      <xsl:text>openmath-to-vanish: unsupported application </xsl:text>
      <xsl:value-of select="OMS/@cd"/>
      <xsl:text>/</xsl:text>
      <xsl:value-of select="OMS/@name"/>
      <xsl:text>; dropped</xsl:text>
    </xsl:message>
  </xsl:template>

  <xsl:template match="OMA[OMS[@cd='arith1' and @name='minus']]">
    <sub>
      <expr><xsl:apply-templates select="*[2]"/></expr>
      <expr><xsl:apply-templates select="*[3]"/></expr>
    </sub>
  </xsl:template>

  <xsl:template match="OMA[OMS[@cd='arith1' and @name='plus']]">
    <add>
      <expr><xsl:apply-templates select="*[2]"/></expr>
      <expr><xsl:apply-templates select="*[3]"/></expr>
    </add>
  </xsl:template>

  <xsl:template match="OMA[OMS[@cd='arith1' and @name='times']]">
    <mul>
      <expr><xsl:apply-templates select="*[2]"/></expr>
      <expr><xsl:apply-templates select="*[3]"/></expr>
    </mul>
  </xsl:template>

  <xsl:template match="OMA[OMS[@cd='arith1' and @name='power']]">
    <pow>
      <expr><xsl:apply-templates select="*[2]"/></expr>
      <expr><xsl:apply-templates select="*[3]"/></expr>
    </pow>
  </xsl:template>

  <xsl:template match="OMA[OMS[@cd='arith1' and @name='unary_minus']]">
    <sub>
      <expr><integer>0</integer></expr>
      <expr><xsl:apply-templates select="*[2]"/></expr>
    </sub>
  </xsl:template>

  <xsl:template match="OMV">
    <symbol><xsl:value-of select="@name"/></symbol>
  </xsl:template>

  <xsl:template match="OMI">
    <integer><xsl:value-of select="normalize-space(.)"/></integer>
  </xsl:template>

  <xsl:template match="OMF|OMBIND|OMBVAR|OMATTR|OMR">
    <xsl:message>
      <xsl:text>openmath-to-vanish: no vanish-grammar counterpart for </xsl:text>
      <xsl:value-of select="name()"/>
      <xsl:text>; dropped</xsl:text>
    </xsl:message>
  </xsl:template>

</xsl:stylesheet>
