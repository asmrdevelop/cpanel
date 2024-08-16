package Cpanel::Validate::DB::Host;

# cpanel - Cpanel/Validate/DB/Host.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Validate:DB::Host - Validation functions for database hosts.

=head1 SYNOPSIS

    use Cpanel::Validate:DB::Host;

    my $result = Cpanel::Validate::DB::Host::mysql_host($host)

=cut

use Cpanel::Encoder::URI ();
use Cpanel::Validate::IP ();

our $mysql_ip_netmask_regex = '^(?:\d{1,3}\.){3}\d{1,3}\/(?:(?:255|0)\.){3}0$';
our $mysql_ip_regex         = '^(?:(?:(?:[%_\d]{1,3}\.){3}[%_\d]{1,3})|(?:(?:[%_\d]{1,3}\.){0,3}\%))$';
our $mysql_host_regex       = '^(?:\%\.)?(?:[a-zA-Z\d\-%_]+\.)*(?:[a-zA-Z%\d]+)$';

=head2 mysql_host($host)

Returns a hashref of with the following keys:

status: 0 or 1 depending on if the host is valid
message: If status is 0 this is the reason the host is invalid

=cut

sub mysql_host {
    my ($host)        = @_;
    my $host_is_valid = 0;
    my $invalid_msg   = 'The host is not valid.';
    my $test_host     = Cpanel::Encoder::URI::uri_decode_str($host);

    if ( Cpanel::Validate::IP::is_valid_ipv6($host) ) {
        require Cpanel::CPAN::Net::IP;
        $invalid_msg = 'The IPv6 address must be in canonical compressed format.';
        if ( $host eq Cpanel::CPAN::Net::IP::ip_compress_address( $host, 6 ) ) {
            $host_is_valid = 1;
        }
    }
    elsif ( 0 <= index $host, '/' ) {

        # / means it's a network/netmask and should not have wildcards
        $invalid_msg = 'The IP address/netmask is not valid.';
        if ( $host =~ m/$mysql_ip_netmask_regex/o ) {
            $host_is_valid = 1;
        }
    }
    elsif ( $host =~ m/^(?:[%_\d]{1,3}\.)*[%_\d]{1,3}$/ ) {

        # looks basically like an IP address or a raw %
        $invalid_msg = 'The IP address is not valid.';
        if ( $host =~ m/$mysql_ip_regex/o ) {
            $host_is_valid = 1;
        }
    }
    elsif ( $test_host =~ m/$mysql_host_regex/o ) {

        # MySQL limits the hostnames to 60 characters.
        if ( length $test_host > 60 ) {
            $host_is_valid = 0;
            $invalid_msg   = 'The hostname must be no longer than 60 characters.';
        }
        else {
            # looks like a hostname
            $host_is_valid = 1;
        }
    }

    if ( !$host_is_valid ) {
        return { 'status' => 0, 'message' => $invalid_msg };
    }

    return { 'status' => 1 };
}

1;
