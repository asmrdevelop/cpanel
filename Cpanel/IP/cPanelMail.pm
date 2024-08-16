package Cpanel::IP::cPanelMail;

# cpanel - Cpanel/IP/cPanelMail.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# *** TODO
# *** Neighbors.pm, GreyList.pm, and cPanelMail.pm all create ip lists
# *** from different data sources. In the future it would be nice to
# *** reconcile all the differences and create a more modular interface
# *** However for now they are not combined as it would be memory expensive
# *** to load all the deps for each one in every place they are used
# ***
#
use strict;
use Cpanel::Net::Whois::IP::Cached ();
use Cpanel::Exception              ();
use Cpanel::IP::Match              ();
use Cpanel::FileUtils::Write       ();
use Cpanel::ConfigFiles            ();
use Cpanel::Logger                 ();
use Cpanel::SocketIP               ();

use Try::Tiny;

our $MAIL_HOST = 'mail.cpanel.net';

# get_netblocks
#
# This function takes no input as it will fetch the list
# of IP addresses bound to the server it is run on.
# It returns a list of all the assigned netblocks
# that the IP addresses for this server is currently assigned.
#
# For example if the server has the IP addresses
# 208.74.121.51 and 208.74.125.87, this function
# will return the CIDR range from the whois entry:
#
# 208.74.120.0/21
sub get_netblocks {
    my @ranges;

    my @ips = Cpanel::SocketIP::_resolveIpAddress($MAIL_HOST);
  EACHIPS:
    foreach my $public_ip (@ips) {
        foreach my $range (@ranges) {
            if ( Cpanel::IP::Match::ip_is_in_range( $public_ip, $range ) ) {
                next EACHIPS;
            }
        }

        my $whois_response = Cpanel::Net::Whois::IP::Cached->new()->lookup_address($public_ip) or next;

        # The cidr attribute is an array
        my $cidr_ar = $whois_response->get('cidr');

        next if !$cidr_ar || 'ARRAY' ne ref $cidr_ar || !scalar @{$cidr_ar};

        push @ranges, @{$cidr_ar};
    }

    return @ranges;
}

sub update_cpanel_mail_netblocks {
    my @net_blocks = get_netblocks();

    # http://www.exim.org/exim-html-current/doc/html/spec_html/ch-file_and_database_lookups.html
    # Keys that involve IPv6 addresses must be enclosed in quotes to prevent the first internal colon being interpreted as a key terminator.
    return Cpanel::FileUtils::Write::overwrite( $Cpanel::ConfigFiles::CPANEL_MAIL_NETBLOCKS_FILE, join( "\n", map { m{:} ? qq{"$_"} : $_ } sort @net_blocks ), 0644 );
}

sub update_cpanel_mail_netblocks_or_log {
    my $state;
    try {
        $state = update_cpanel_mail_netblocks();
    }
    catch {
        my $err = "Failed to update neighbor netblocks because of an error: " . Cpanel::Exception::get_string($_);
        Cpanel::Logger->new()->warn($err);
        if ( !-e $Cpanel::ConfigFiles::CPANEL_MAIL_NETBLOCKS_FILE ) {
            Cpanel::FileUtils::Write::overwrite( $Cpanel::ConfigFiles::CPANEL_MAIL_NETBLOCKS_FILE, "# $err", 0644 );    # Writen a file to ensure that exim does not fail because the file does not exist
        }

    };
    return $state;

}

1;
