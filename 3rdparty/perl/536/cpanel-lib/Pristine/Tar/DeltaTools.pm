#!/usr/bin/perl
# Wrappers around delta computing programs
# the following naming is used:
#  - try_* : tries to run the command
#            and returns the return code
#  - do_*  : runs the command and fails if it failed

package Pristine::Tar::DeltaTools;

use Pristine::Tar;
use warnings;
use strict;

use constant XDELTA3_BIN => '/usr/local/cpanel/3rdparty/bin/xdelta3';

use Exporter q{import};
our @EXPORT = qw(try_xdelta_patch do_xdelta_patch try_xdelta_diff do_xdelta_diff
  try_xdelta3_patch do_xdelta3_patch try_xdelta3_diff do_xdelta3_diff);

#
# xdelta
#

sub try_xdelta_patch {
    return 22; # We don't do xdelta at this point.
}

sub do_xdelta_patch {
  die "xdelta patch failed!" if (try_xdelta_patch(@_) != 0);
}

sub try_xdelta_diff {
    return 23;
}

sub do_xdelta_diff {
  die "xdelta delta failed!" if (try_xdelta_diff(@_) != 0);
}

#
# xdelta3
#

sub try_xdelta3_patch {
  my ($fromfile, $diff, $tofile) = @_;
  return try_doit( XDELTA3_BIN, "decode", "-f", "-D", "-s",
    $fromfile, $diff, $tofile) >> 8;
}

sub do_xdelta3_patch {
  die "xdelta3 decode failed!" if (try_xdelta3_patch(@_) != 0);
}

sub try_xdelta3_diff {
  my ($fromfile, $tofile, $diff) = @_;
  return try_doit( XDELTA3_BIN, "encode", "-0", "-f", "-D", "-s",
    $fromfile, $tofile, $diff) >> 8;
}

sub do_xdelta3_diff {
  die "xdelta3 encode failed!" if (try_xdelta3_diff(@_) != 0);
}

1;
