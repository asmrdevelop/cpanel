package Cpanel::CountryCodes;

# cpanel - Cpanel/CountryCodes.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::CountryCodes - Provide a list of all known country codes.

=head1 SYNOPSIS

    use Cpanel::CountryCodes ();

    my %_countries_lookup = map { $_ => undef } @{ Cpanel::CountryCodes::COUNTRY_CODES() };

=head1 DESCRIPTION

This module is generally used for validating that a country code exists.

It should not be confused with Cpanel::CountryCodes::IPS which
is used to provide a list of known ips in a specifed country code.
Cpanel::CountryCodes::IPS should not be expected to be complete
list of country codes as we may not have data for each one.

=cut

#Copied from CPAN Locale::Country::all_country_codes('alpha-2')
#Locale::Codes v3.25
my @_countries = qw(
  AD
  AE
  AF
  AG
  AI
  AL
  AM
  AO
  AQ
  AR
  AS
  AT
  AU
  AW
  AX
  AZ
  BA
  BB
  BD
  BE
  BF
  BG
  BH
  BI
  BJ
  BL
  BM
  BN
  BO
  BQ
  BR
  BS
  BT
  BV
  BW
  BY
  BZ
  CA
  CC
  CD
  CF
  CG
  CH
  CI
  CK
  CL
  CM
  CN
  CO
  CR
  CU
  CV
  CW
  CX
  CY
  CZ
  DE
  DJ
  DK
  DM
  DO
  DZ
  EC
  EE
  EG
  EH
  ER
  ES
  ET
  FI
  FJ
  FK
  FM
  FO
  FR
  GA
  GB
  GD
  GE
  GF
  GG
  GH
  GI
  GL
  GM
  GN
  GP
  GQ
  GR
  GS
  GT
  GU
  GW
  GY
  HK
  HM
  HN
  HR
  HT
  HU
  ID
  IE
  IL
  IM
  IN
  IO
  IQ
  IR
  IS
  IT
  JE
  JM
  JO
  JP
  KE
  KG
  KH
  KI
  KM
  KN
  KP
  KR
  KW
  KY
  KZ
  LA
  LB
  LC
  LI
  LK
  LR
  LS
  LT
  LU
  LV
  LY
  MA
  MC
  MD
  ME
  MF
  MG
  MH
  MK
  ML
  MM
  MN
  MO
  MP
  MQ
  MR
  MS
  MT
  MU
  MV
  MW
  MX
  MY
  MZ
  NA
  NC
  NE
  NF
  NG
  NI
  NL
  NO
  NP
  NR
  NU
  NZ
  OM
  PA
  PE
  PF
  PG
  PH
  PK
  PL
  PM
  PN
  PR
  PS
  PT
  PW
  PY
  QA
  RE
  RO
  RS
  RU
  RW
  SA
  SB
  SC
  SD
  SE
  SG
  SH
  SI
  SJ
  SK
  SL
  SM
  SN
  SO
  SR
  SS
  ST
  SV
  SX
  SY
  SZ
  TC
  TD
  TF
  TG
  TH
  TJ
  TK
  TL
  TM
  TN
  TO
  TR
  TT
  TV
  TW
  TZ
  UA
  UG
  UM
  US
  UY
  UZ
  VA
  VC
  VE
  VG
  VI
  VN
  VU
  WF
  WS
  YE
  YT
  ZA
  ZM
  ZW
);

sub COUNTRY_CODES {
    return [@_countries];
}
