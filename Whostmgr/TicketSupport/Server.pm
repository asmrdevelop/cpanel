
# cpanel - Whostmgr/TicketSupport/Server.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::TicketSupport::Server;

use strict;
use warnings;
use Cpanel::Validate::Hostname ();
use Cpanel::Config::Sources    ();

our $_tickets_hostname;    # in-memory cache
our $_account_hostname;    # in-memory cache

=head1 NAME

Whostmgr::TicketSupport::Server

=head1 DESCRIPTION

This module provides a central location for managing the hostname used for
redirects and API queries to the cPanel ticket and Manage2 account systems.
This is useful for development and testing purposes.

Note: As of this writing, the hostnames for tickets and accounts are still
being kept separate from one another in order to permit a future split of
the two systems if desired.

=head1 CONFIGURATION FILE

The following configuration files are obsolete and will not work anymore:

=over

=item * /var/cpanel/tickets_hostname

=item * /var/cpanel/account_hostname

=back

Instead of using these, please use the normal /etc/cpsources.conf file to
configure TICKETS_SERVER_URL. This value will take effect both for
the "tickets" and "account" server. (They are the same server.)

=head2 Important note about SSL certificates

If you're customizing either or both of these servers, you're probably modifying
them to point to something that lacks a valid SSL certificate.

To disable SSL hostname verification for ticket system API queries, first create
B</var/cpanel/oauth2/cpanel.conf> if it doesn't already exist, and then add the
following line to it:

  ssl_arg_verify_hostname=0

=head1 FUNCTIONS

=head2 tickets_hostname()

Returns the currently configured ticket system hostname. On normal servers,
this will always be tickets.cpanel.net. It will only change if you've customized
it for development or testing purposes. (See CONFIGURATION FILE section above.)

=cut

sub tickets_hostname {
    if ( !$_tickets_hostname ) {
        my $url = Cpanel::Config::Sources::get_source('TICKETS_SERVER_URL');
        ($_tickets_hostname) = $url =~ m{^https?://([^/]+)};
    }

    $_tickets_hostname ||= 'tickets.cpanel.net';

    return $_tickets_hostname;
}

=head2 make_tickets_url(URI)

Given ticket system URI (e.g., /review/login.cgi), return a full URL
using the currently-configured ticket system hostname, as provided
by tickets_hostname().

=cut

sub make_tickets_url {
    my ($uri) = @_;
    $uri = '/' . $uri if '/' ne substr( $uri, 0, 1 );
    return 'https://' . tickets_hostname() . $uri;
}

=head2 account_hostname()

Returns the currently configured account system hostname. On normal servers,
this will always be account.cpanel.net. It will only change if you've customized
it for development or testing purposes. (See CONFIGURATION FILE section above.)

When a custom URL is specified for testing purposes, it comes from the same
TICKETS_SERVER_URL setting that is used for the tickets hostname. No hostname
distinction between 'tickets' and 'account' is needed in this case.

=cut

sub account_hostname {
    if ( !$_account_hostname ) {
        my $url = Cpanel::Config::Sources::get_source('TICKETS_SERVER_URL');
        ($_account_hostname) = $url =~ m{^https?://([^/]+)};
    }

    $_account_hostname ||= 'account.cpanel.net';

    return $_account_hostname;
}

=head2 make_account_url(URI)

Given an account system URI (e.g., /foo), return a full URL using
the currently-configured account system hostname, as provided by
account_hostname().

=cut

sub make_account_url {
    my ($uri) = @_;
    $uri = '/' . $uri if '/' ne substr( $uri, 0, 1 );
    return 'https://' . account_hostname() . $uri;
}

# Not part of this module's public interface
#
# _get_hostname_from_file(FILE)
#
# Given a filename, FILE, read the contents, and return the hostname
# from the file if it's a valid hostname. If the file doesn't exist
# or doesn't contain a valid hostname, undef will be returned.
sub _get_hostname_from_file {
    my ($file) = @_;

    my $hostname;

    open my $fh, '<', $file or die "$file: $!";
    chomp( $hostname = <$fh> );
    close $fh;

    # If the file contains something invalid, we don't want to die and break all the interfaces that
    # rely on this. Instead, just treat it as if the file didn't exist.
    if ( !Cpanel::Validate::Hostname::is_valid($hostname) ) {
        return undef;
    }

    return $hostname;
}

1;
