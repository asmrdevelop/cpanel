package Cpanel::BandwidthDB::State;

# cpanel - Cpanel/BandwidthDB/State.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Server::Type::Profile::Roles ();
use Cpanel::BandwidthDB::Constants       ();

=encoding utf-8

=head1 NAME

Cpanel::BandwidthDB::State - Information about what the bandwidth db is tracking.

=head1 SYNOPSIS

    use Cpanel::Bandwidth::State ();

    my @all_enabled_protocols = Cpanel::BandwidthDB::State::get_enabled_protocols();

=cut

my %PROTOCOL_TO_ROLE_MAP = (
    ftp  => 'FTP',
    http => 'WebServer',
    imap => 'MailReceive',
    pop3 => 'MailReceive',
    smtp => 'MailSend',
);

my $_has_enabled_protocols = 0;
my @_enabled_protocols;

=head2 get_enabled_protocols()

Returns an ordered list of protocols that are enabled with the
current server role profile.

=cut

sub get_enabled_protocols {
    return @_enabled_protocols if $_has_enabled_protocols;

    @_enabled_protocols     = grep { Cpanel::Server::Type::Profile::Roles::is_role_enabled( $PROTOCOL_TO_ROLE_MAP{$_} ) } @Cpanel::BandwidthDB::Constants::PROTOCOLS;
    $_has_enabled_protocols = 1;
    return @_enabled_protocols;
}

sub _clear_cache {
    undef @_enabled_protocols;
    $_has_enabled_protocols = 0;
    return;
}
1;
