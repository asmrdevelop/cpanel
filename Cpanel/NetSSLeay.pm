package Cpanel::NetSSLeay;

# cpanel - Cpanel/NetSSLeay.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Net::SSLeay ();

use Cpanel::Exception                ();
use Cpanel::NetSSLeay::ErrorHandling ();

#for debugging and testing
our $_CALL_LOG;

my %_code_lookup_cache;

sub do {    ## no critic qw(Subroutines::RequireArgUnpacking)
            # $func = $_[0]
            # @args = $_[1.. $#_]

    if ( Net::SSLeay::ERR_peek_error() ) {
        while ( my $code = Net::SSLeay::ERR_get_error() ) {
            my $str = Net::SSLeay::ERR_error_string($code);
            warn "Net::SSLeay error left in queue from previous call: “$str” ($code)";
        }
    }

    local $!;

    push @$_CALL_LOG, \@_ if $_CALL_LOG;

    my $cr = ( $_code_lookup_cache{ $_[0] } ||= Net::SSLeay->can( $_[0] ) ) or do {
        die "Net::SSLeay::$_[0] doesn’t exist!";    #programmer error
    };

    my $resp = wantarray ? [ $cr->( @_[ 1 .. $#_ ] ) ] : $cr->( @_[ 1 .. $#_ ] );

    my $errno = $!;

    if ( my @codes = Cpanel::NetSSLeay::ErrorHandling::get_error_codes() ) {
        die Cpanel::Exception::create(
            'NetSSLeay',
            [
                function    => $_[0],
                arguments   => [ @_[ 1 .. $#_ ] ],
                error_codes => \@codes,
                errno       => $errno,
                return      => $resp,
            ],
        );
    }

    return wantarray ? @$resp : $resp;
}

sub _clear_sub_cache {    # for testing
    %_code_lookup_cache = ();
    return;
}

1;
