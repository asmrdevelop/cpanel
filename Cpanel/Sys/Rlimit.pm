package Cpanel::Sys::Rlimit;

# cpanel - Cpanel/Sys/Rlimit.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::OSSys::Bits ();
use Cpanel::Pack        ();
use Cpanel::Syscall     ();

my $SYS_getrlimit;
my $SYS_setrlimit;

# Constants see GETRLIMIT(2)
our $RLIM_INFINITY;    # denotes no limit on a resource
our %RLIMITS = (
    'CPU'    => 0,    # CPU time limit in seconds.
    'DATA'   => 2,    # The maximum size of the process's data segment
    'CORE'   => 4,    # Maximum size of a core file
    'RSS'    => 5,    # Specifies the limit (in pages) of the process's resident set
    'NPROC'  => 6,    # The maximum number of processes
    'NOFILE' => 7,    # The maximum number of file descriptors
    'AS'     => 9,    # The maximum size of the process's virtual memory

    # cf. man 2 getrlimit
    'FSIZE'      => 1,
    'STACK'      => 3,
    'MEMLOCK'    => 8,
    'LOCKS'      => 10,
    'SIGPENDING' => 11,
    'MSGQUEUE'   => 12,
    'NICE'       => 13,
    'RTPRIO'     => 14,
    'RTTIME'     => 15,
);

# End Constants see GETRLIMIT(2)

BEGIN {
    $RLIM_INFINITY = $Cpanel::OSSys::Bits::MAX_NATIVE_UNSIGNED;
}

our $PACK_TEMPLATE = 'L!L!';
our @TEMPLATE      = (
    rlim_cur => 'L!',    # unsigned long
    rlim_max => 'L!',    # unsigned long
);

#      struct rlimit {
#           rlim_t rlim_cur;  /* Soft limit */
#           rlim_t rlim_max;  /* Hard limit (ceiling for rlim_cur) */
#      };

###########################################################################
#
# Method:
#   getrlimit
#
# Description:
#   Returns the result from the getrlimit syscall
#
# Parameters:
#   $rlimit - The name or numeric equivlant of a resource as defined by the getrlimit(2) documentation
#
# Exceptions:
#   dies on failure from system call
#
# Returns:
#   a array (matches BSD::Resource)
#   (
#      $rlim_cur
#      $rlim_max
#   )
# see getrlimit(2) for more information;
#
sub getrlimit {
    my ($rlimit) = @_;
    local $!;

    die "getrlimit requires an rlimit constant" if !defined $rlimit;
    my $buffer = pack( $PACK_TEMPLATE, 0 );

    my $rlimit_num = _rlimit_to_num($rlimit);

    Cpanel::Syscall::syscall( 'getrlimit', $rlimit_num, $buffer );

    my $getrlimit_hr = Cpanel::Pack->new( \@TEMPLATE )->unpack_to_hashref($buffer);
    return ( $getrlimit_hr->{'rlim_cur'}, $getrlimit_hr->{'rlim_max'} );
}

###########################################################################
#
# Method:
#   setrlimit
#
# Description:
#   Returns the result from the getrlimit syscall
#
# Parameters:
#   $rlimit - an rlimit constant or number (see above for $RLIM_* or the getrlimit(2) man page)
#   $soft   - a soft limit - The soft limit is the value that the kernel enforces for the
#          corresponding resource
#   $hard   - a hard limit -  The hard limit acts as a ceiling for the
#          soft limit
#
# Exceptions:
#   dies on failure from system call
#
# see setrlimit(2) for more information;
#
sub setrlimit {
    my ( $rlimit, $soft, $hard ) = @_;
    local $!;

    die "setrlimit requires an rlimit constant" if !defined $rlimit;
    die "setrlimit requires a soft limit"       if !defined $soft;
    die "setrlimit requires a hard limit"       if !defined $hard;

    my $buffer = pack( $PACK_TEMPLATE, $soft, $hard );

    my $rlimit_num = _rlimit_to_num($rlimit);
    Cpanel::Syscall::syscall( 'setrlimit', $rlimit_num, $buffer );

    return 1;
}

sub _rlimit_to_num {
    my ($rlimit) = @_;

    if ( length($rlimit) && $rlimit !~ tr<0-9><>c ) {
        return $rlimit;
    }
    elsif ( exists $RLIMITS{$rlimit} ) {
        return $RLIMITS{$rlimit};
    }

    die "Unknown RLIMIT: $rlimit";

}

1;
