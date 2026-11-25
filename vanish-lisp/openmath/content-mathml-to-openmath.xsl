<?xml version="1.0" encoding="UTF-8"?>
<!--
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
-->
<!-- openmath/content-mathml-to-openmath.xsl : Content MathML to OpenMath.
     apply/eq becomes relation1 eq; minus, plus, times and power become
     the arith1 operators; unary minus becomes arith1 unary_minus; ci
     becomes OMV and cn becomes OMI, or OMF when the number carries
     type="real". -->
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="xml" indent="no" omit-xml-declaration="yes"/>

  <xsl:template match="math">
    <OMOBJ>
      <xsl:apply-templates select="*[1]"/>
    </OMOBJ>
  </xsl:template>

  <xsl:template match="apply[eq]">
    <OMA>
      <OMS cd="relation1" name="eq"/>
      <xsl:apply-templates select="*[2]"/>
      <xsl:apply-templates select="*[3]"/>
    </OMA>
  </xsl:template>

  <xsl:template match="apply[minus]">
    <OMA>
      <OMS cd="arith1" name="minus"/>
      <xsl:apply-templates select="*[2]"/>
      <xsl:apply-templates select="*[3]"/>
    </OMA>
  </xsl:template>

  <xsl:template match="apply[plus]">
    <OMA>
      <OMS cd="arith1" name="plus"/>
      <xsl:apply-templates select="*[2]"/>
      <xsl:apply-templates select="*[3]"/>
    </OMA>
  </xsl:template>

  <xsl:template match="apply[times]">
    <OMA>
      <OMS cd="arith1" name="times"/>
      <xsl:apply-templates select="*[2]"/>
      <xsl:apply-templates select="*[3]"/>
    </OMA>
  </xsl:template>

  <xsl:template match="apply[power]">
    <OMA>
      <OMS cd="arith1" name="power"/>
      <xsl:apply-templates select="*[2]"/>
      <xsl:apply-templates select="*[3]"/>
    </OMA>
  </xsl:template>

  <xsl:template match="apply[minus and count(*) = 2]">
    <OMA>
      <OMS cd="arith1" name="unary_minus"/>
      <xsl:apply-templates select="*[2]"/>
    </OMA>
  </xsl:template>

  <xsl:template match="ci">
    <OMV name="{normalize-space(.)}"/>
  </xsl:template>

  <xsl:template match="cn[@type='real']">
    <OMF><xsl:value-of select="normalize-space(.)"/></OMF>
  </xsl:template>

  <xsl:template match="cn">
    <OMI><xsl:value-of select="normalize-space(.)"/></OMI>
  </xsl:template>

</xsl:stylesheet>
