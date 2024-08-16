package Cpanel::IP::GreyList;

# cpanel - Cpanel/IP/GreyList.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# *** TODO
# *** Neighbors.pm, GreyList.pm, and cPanelMail.pm all create ip lists
# *** from different data sources. In the future it would be nice to
# *** reconcile all the differences and create a more modular interface
# *** However for now they are not combined as it would be memory expensive
# *** to load all the deps for each one in every place they are used
# ***
#

use strict;
use warnings;
use Cpanel::GreyList::Config ();
use Cpanel::Exception        ();
use Cpanel::GreyList::Client ();
use Cpanel::FileUtils::Write ();
use Cpanel::Logger           ();
use Cpanel::ConfigFiles      ();
use Cpanel::CPAN::Net::IP    ();
use Net::CIDR                ();    #Net::Whois::IANA uses this anyways
use Try::Tiny;

# get_trusted_netblocks_with_comments
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
# 208.74.120.0/21  # happy soft
#
# The data is returned as a hashref with the
# CIDRs as hash keys and the comments has values
sub get_trusted_netblocks_with_comments {
    my %ranges;

    my $trusted_hosts = Cpanel::GreyList::Config::is_enabled() && Cpanel::GreyList::Client->new()->read_trusted_hosts();

    if ($trusted_hosts) {
        foreach my $range ( @{$trusted_hosts} ) {
            my $comment = $range->{'comment'} // '';
            foreach my $cidr ( map { _canonical_range($_) } Net::CIDR::range2cidr( $range->{'host_ip'} ) ) {
                $ranges{$cidr} = $comment;
            }
        }
    }
    return \%ranges;
}

sub get_common_mail_providers_with_comments {
    my %ranges;

    if ( Cpanel::GreyList::Config::is_enabled() ) {
        my $client          = Cpanel::GreyList::Client->new();
        my $providers_in_db = $client->get_common_mail_providers();
        foreach my $provider ( keys %{$providers_in_db} ) {
            next if !$providers_in_db->{$provider}->{'is_trusted'};

            my $ips_for_provider = $client->list_entries_for_common_mail_provider($provider);
            foreach my $ip_range ( @{$ips_for_provider} ) {
                foreach my $cidr ( map { _canonical_range($_) } Net::CIDR::range2cidr( $ip_range->{'host_ip'} ) ) {
                    $ranges{$cidr} = $providers_in_db->{$provider}->{'display_name'};
                }
            }
        }
    }

    return \%ranges;
}

# Return the given CIDR or IP.  If it is IPv6, the address portion will be in
# RFC 5952 canonical format.
#
# This is necessary because Exim doesn't like it when we use a double-colon to
# replace only one zero block.
sub _canonical_range {
    my ($range) = @_;
    return $range unless $range =~ tr{:}{};
    my ( $addr, $bits ) = split m{/}, $range;
    $addr = Cpanel::CPAN::Net::IP::ip_compress_address( $addr, 6 );
    return $addr . ( defined $bits ? "/$bits" : '' );
}

sub update_trusted_netblocks {
    my $net_blocks = get_trusted_netblocks_with_comments();

    # http://www.exim.org/exim-html-current/doc/html/spec_html/ch-file_and_database_lookups.html
    # Keys that involve IPv6 addresses must be enclosed in quotes to prevent the first internal colon being interpreted as a key terminator.
    return Cpanel::FileUtils::Write::overwrite( $Cpanel::ConfigFiles::GREYLIST_TRUSTED_NETBLOCKS_FILE, join( "\n", map { ( m{:} ? qq{"$_"} : $_ ) . " # $net_blocks->{$_}" } sort keys %{$net_blocks} ), 0644 );
}

sub update_common_mail_providers {
    my $net_blocks = get_common_mail_providers_with_comments();

    # http://www.exim.org/exim-html-current/doc/html/spec_html/ch-file_and_database_lookups.html
    # Keys that involve IPv6 addresses must be enclosed in quotes to prevent the first internal colon being interpreted as a key terminator.
    return Cpanel::FileUtils::Write::overwrite( $Cpanel::ConfigFiles::GREYLIST_COMMON_MAIL_PROVIDERS_FILE, join( "\n", map { ( m{:} ? qq{"$_"} : $_ ) . " # $net_blocks->{$_}" } sort keys %{$net_blocks} ), 0644 );
}

sub update_trusted_netblocks_or_log {
    my $state;

    try {
        $state = update_trusted_netblocks();
    }
    catch {
        my $err = "Failed to update trusted greylist netblocks because of an error: " . Cpanel::Exception::get_string($_);
        Cpanel::Logger->new()->warn($err);
        if ( !-e $Cpanel::ConfigFiles::GREYLIST_TRUSTED_NETBLOCKS_FILE ) {
            Cpanel::FileUtils::Write::overwrite( $Cpanel::ConfigFiles::GREYLIST_TRUSTED_NETBLOCKS_FILE, "# $err", 0644 );    # Writen a file to ensure that exim does not fail because the file does not exist
        }

    };

    return $state;
}

sub update_common_mail_providers_or_log {
    my $state;
    try {
        $state = update_common_mail_providers();
    }
    catch {
        my $err = "Failed to update greylist common mail provider netblocks because of an error: " . Cpanel::Exception::get_string($_);
        Cpanel::Logger->new()->warn($err);
        if ( !-e $Cpanel::ConfigFiles::GREYLIST_COMMON_MAIL_PROVIDERS_FILE ) {
            Cpanel::FileUtils::Write::overwrite( $Cpanel::ConfigFiles::GREYLIST_COMMON_MAIL_PROVIDERS_FILE, "# $err", 0644 );    # Writen a file to ensure that exim does not fail because the file does not exist
        }

    };

    return $state;
}

1;
