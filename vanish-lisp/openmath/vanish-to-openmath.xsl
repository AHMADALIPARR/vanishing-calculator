<?xml version="1.0" encoding="UTF-8"?>
<!--
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
-->
<!-- openmath/vanish-to-openmath.xsl : Vanish XML to OpenMath.
     The reverse of openmath-to-vanish.xsl. The <vanish> root becomes
     the vanish1 vanishes application around the expression; sub, add,
     mul and pow become the arith1 operators; symbol becomes OMV and
     integer becomes OMI. -->
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="xml" indent="no" omit-xml-declaration="yes"/>

  <xsl:template match="vanish">
    <OMOBJ>
      <OMA>
        <OMS cd="vanish1" name="vanishes"/>
        <xsl:apply-templates select="expr/*[1]"/>
      </OMA>
    </OMOBJ>
  </xsl:template>

  <xsl:template match="sub">
    <OMA>
      <OMS cd="arith1" name="minus"/>
      <xsl:apply-templates select="expr[1]/*[1]"/>
      <xsl:apply-templates select="expr[2]/*[1]"/>
    </OMA>
  </xsl:template>

  <xsl:template match="add">
    <OMA>
      <OMS cd="arith1" name="plus"/>
      <xsl:apply-templates select="expr[1]/*[1]"/>
      <xsl:apply-templates select="expr[2]/*[1]"/>
    </OMA>
  </xsl:template>

  <xsl:template match="mul">
    <OMA>
      <OMS cd="arith1" name="times"/>
      <xsl:apply-templates select="expr[1]/*[1]"/>
      <xsl:apply-templates select="expr[2]/*[1]"/>
    </OMA>
  </xsl:template>

  <xsl:template match="pow">
    <OMA>
      <OMS cd="arith1" name="power"/>
      <xsl:apply-templates select="expr[1]/*[1]"/>
      <xsl:apply-templates select="expr[2]/*[1]"/>
    </OMA>
  </xsl:template>

  <xsl:template match="symbol">
    <OMV name="{normalize-space(.)}"/>
  </xsl:template>

  <xsl:template match="integer">
    <OMI><xsl:value-of select="normalize-space(.)"/></OMI>
  </xsl:template>

</xsl:stylesheet>
