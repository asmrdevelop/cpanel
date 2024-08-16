package Cpanel::Config::Constants::Perl;

# cpanel - Cpanel/Config/Constants/Perl.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $ABRT   = 6;
our $ALRM   = 14;
our $BUS    = 7;
our $CHLD   = 17;
our $CLD    = 17;
our $CONT   = 18;
our $FPE    = 8;
our $HUP    = 1;
our $ILL    = 4;
our $INT    = 2;
our $IO     = 29;
our $IOT    = 6;
our $KILL   = 9;
our $NUM32  = 32;
our $NUM33  = 33;
our $NUM35  = 35;
our $NUM36  = 36;
our $NUM37  = 37;
our $NUM38  = 38;
our $NUM39  = 39;
our $NUM40  = 40;
our $NUM41  = 41;
our $NUM42  = 42;
our $NUM43  = 43;
our $NUM44  = 44;
our $NUM45  = 45;
our $NUM46  = 46;
our $NUM47  = 47;
our $NUM48  = 48;
our $NUM49  = 49;
our $NUM50  = 50;
our $NUM51  = 51;
our $NUM52  = 52;
our $NUM53  = 53;
our $NUM54  = 54;
our $NUM55  = 55;
our $NUM56  = 56;
our $NUM57  = 57;
our $NUM58  = 58;
our $NUM59  = 59;
our $NUM60  = 60;
our $NUM61  = 61;
our $NUM62  = 62;
our $NUM63  = 63;
our $PIPE   = 13;
our $POLL   = 29;
our $PROF   = 27;
our $PWR    = 30;
our $QUIT   = 3;
our $RTMAX  = 64;
our $RTMIN  = 34;
our $SEGV   = 11;
our $STKFLT = 16;
our $STOP   = 19;
our $SYS    = 31;
our $TERM   = 15;
our $TRAP   = 5;
our $TSTP   = 20;
our $TTIN   = 21;
our $TTOU   = 22;
our $UNUSED = 31;
our $URG    = 23;
our $USR1   = 10;
our $USR2   = 12;
our $VTALRM = 26;
our $WINCH  = 28;
our $XCPU   = 24;
our $XFSZ   = 25;
our $ZERO   = 0;

our %SIGNAL_NAME = qw(
  0    ZERO
  1    HUP
  10    USR1
  11    SEGV
  12    USR2
  13    PIPE
  14    ALRM
  15    TERM
  16    STKFLT
  17    CHLD
  18    CONT
  19    STOP
  2    INT
  20    TSTP
  21    TTIN
  22    TTOU
  23    URG
  24    XCPU
  25    XFSZ
  26    VTALRM
  27    PROF
  28    WINCH
  29    IO
  3    QUIT
  30    PWR
  31    SYS
  32    NUM32
  33    NUM33
  34    RTMIN
  35    NUM35
  36    NUM36
  37    NUM37
  38    NUM38
  39    NUM39
  4    ILL
  40    NUM40
  41    NUM41
  42    NUM42
  43    NUM43
  44    NUM44
  45    NUM45
  46    NUM46
  47    NUM47
  48    NUM48
  49    NUM49
  5    TRAP
  50    NUM50
  51    NUM51
  52    NUM52
  53    NUM53
  54    NUM54
  55    NUM55
  56    NUM56
  57    NUM57
  58    NUM58
  59    NUM59
  6    ABRT
  60    NUM60
  61    NUM61
  62    NUM62
  63    NUM63
  64    RTMAX
  7    BUS
  8    FPE
  9    KILL
);

1;
