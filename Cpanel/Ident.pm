package Cpanel::Ident;

# cpanel - Cpanel/Ident.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $TESTING_FLAGS = 0;    # FOR TESTING
our $USE_NETLINK   = 1;    # FOR TESTING
our $USE_PROC      = 2;    # FOR TESTING

# netlink will return this value as the uid even when no match was found
use constant NOTFOUND => 0xff_ff_ff_ff;

sub identify_local_connection {
    my ( $source_address, $source_port, $dest_address, $dest_port ) = @_;

    if ( !defined($source_port) || !defined($dest_port) ) {
        die 'Need source and destination ports!';
    }

    my $netlink_failed;

    # Try netlink first as its so much faster
    if ( !$TESTING_FLAGS || $TESTING_FLAGS == $USE_NETLINK ) {
        require Cpanel::Linux::Netlink;    # hide from exim but not perlcc - not eval quoted
        my $response;

        #Prevent eval {} from polluting global namespace.
        #Ordinarily Try::Tiny would suit this purpose, but since
        #this module is called from within Exim we want to minimize
        #memory usage.
        local $@;

        eval {
            $response = Cpanel::Linux::Netlink::connection_lookup(
                $source_address, $source_port,
                $dest_address,   $dest_port,
            );
        };

        # If netlink clearly failed, fall back to /proc/net/tcp
        if ($@) {
            $netlink_failed = 1;

            #netlink shouldn’t fail, so warn() when it does.
            warn;
        }

        # If we got a response, and it looks like the response from netlink is meaningful, return the uid from that response
        elsif ($response
            && ref $response
            && $response->{'idiag_dport'}
            && defined( $response->{'idiag_uid'} )
            && $response->{'idiag_uid'} != NOTFOUND() ) {
            return $response->{'idiag_uid'};
        }
    }

    if ( $netlink_failed || $TESTING_FLAGS == $USE_PROC ) {
        require Cpanel::Linux::Proc::Net::Tcp;    # hide from exim but not perlcc - not eval quoted
        my $uid = Cpanel::Linux::Proc::Net::Tcp::connection_lookup( $source_address, $source_port, $dest_address, $dest_port );
        return $uid if defined $uid;
    }

    return;
}

1;
