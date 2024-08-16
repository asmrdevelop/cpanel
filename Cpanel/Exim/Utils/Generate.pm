package Cpanel::Exim::Utils::Generate;

# cpanel - Cpanel/Exim/Utils/Generate.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::TimeHiRes ();

our $last_msg_id;
my $base          = 62;    # used to account for case-insensitive filesystems, where this needs to be 36.
my $base62_chars  = $base == 62 ? join( '', 0 .. 9, 'A' .. 'Z', 'a' .. 'z' ) : join( '', 0 .. 9, 'A' .. 'Z' );
my $id_resolution = $base == 62 ? 500                                        : 1000;

# Generates a msgid in exim's format: http://www.exim.org/exim-html-current/doc/html/spec_html/ch03.html
sub get_msg_id {
    my ( $sec, $usec, $pid ) = @_;
    if ( !defined $usec && $sec ) { $usec = ( Cpanel::TimeHiRes::gettimeofday() )[1]; }
    elsif ( !defined $sec ) { ( $sec, $usec ) = Cpanel::TimeHiRes::gettimeofday(); }
    $pid = $$ if !defined $pid;
    return $last_msg_id = exim_base62($sec) . '-00000' . exim_base62($pid) . '-' . substr( exim_base62( $usec / $id_resolution ), -2, 2 ) . '00';
}

sub exim_base62 {
    my ($n) = @_;
    use integer;
    my $base62 = '';
    for ( 0 .. 5 ) {
        $base62 .= substr( $base62_chars, $n % $base, 1 );
        $n /= $base;
    }
    return scalar reverse $base62;
}

1;
