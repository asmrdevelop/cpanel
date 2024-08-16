package Cpanel::DnsUtils::AskDnsAdmin::Backend;

# cpanel - Cpanel/DnsUtils/AskDnsAdmin/Backend.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::AskDnsAdmin::Backend

=head1 DESCRIPTION

This module implements common logic for dnsadmin clients.

=cut

#----------------------------------------------------------------------

use Cpanel::Context            ();
use Cpanel::Config::LoadCpConf ();

use constant {
    ARG_LOCAL_ONLY  => 'localonly',
    ARG_REMOTE_ONLY => 'skipself',
    ARG_CORRELATIVE => 'correlative',

    SOCKET_PATH => '/var/cpanel/dnsadmin/sock',

    MAX_TIME_TO_TRY_TO_CONNECT_TO_DNSADMIN => 25,
    CONNECT_INTERVAL                       => 0.1,
    MAX_CONNECT_RETRIES                    => 1,
};

#----------------------------------------------------------------------

=head1 CONSTANTS

=over

=item * C<ARG_LOCAL_ONLY>, C<ARG_REMOTE_ONLY>, C<ARG_CORRELATIVE> - dnsadmin
arguments that indicate the request type.

=item * C<SOCKET_PATH> - The path to dnsadmin’s socket.

=item * C<MAX_TIME_TO_TRY_TO_CONNECT_TO_DNSADMIN> - i.e., after initiating
a restart (NB: The first few seconds of this will be during the
C<SERVICE_RESTART_DELAY> and thus futile.)

=item * C<CONNECT_INTERVAL> - The interval between connection attempts
after a restart.

=item * C<MAX_CONNECT_RETRIES> - The number of times to attempt a
restart/reconnect before giving up.

=back

=head1 FUNCTIONS

=head2 $str = get_url_path_and_query( $QUESTION, @ARGS )

$QUESTION is, e.g., C<GETZONES>. @ARGS are the arguments
that the $QUESTION needs.

=cut

sub get_url_path_and_query ( $question, @args ) {
    my $url = "/dnsadmin/$question";

    if (@args) {
        $url .= '?' . _encode_args_for_form(@args);
    }

    return $url;
}

#----------------------------------------------------------------------

=head2 @pairs = get_headers()

Returns a list of 2-member arrays that represent the HTTP headers
to send with the dnsadmin request. These headers derive from the process’s
environment (i.e., %ENV).

=cut

sub get_headers () {
    Cpanel::Context::must_be_list();

    my @headers;

    for my $var (qw(REMOTE_USER REMOTE_ADDR)) {
        next if !$ENV{$var};
        next if $ENV{$var} =~ tr/\n\r\f//;
        push @headers, [ "X-cP-$var", $ENV{$var} ];
    }

    return @headers;
}

#----------------------------------------------------------------------

=head2 restart_service()

Restarts dnsadmin. Returns nothing.

=cut

sub restart_service () {
    local ( $@, $! );

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::schedule_task(
        ['CpServicesTasks'],
        5,
        "restartsrv dnsadmin",
    );

    return;
}

#----------------------------------------------------------------------

sub get_dnsadminapp_path () {
    my $dns_admin_path;

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    if ( length $cpconf->{'dnsadminapp'} ) {
        if ( index( $cpconf->{'dnsadminapp'}, '/' ) != 0 ) {
            warn("Invalid “dnsadminapp” path ($cpconf->{'dnsadminapp'}) in cpanel.config: must start with “/”.");
        }
        elsif ( !-x $cpconf->{'dnsadminapp'} ) {
            my $err_part = $! ? " ($!)" : q<>;

            warn("cpanel.config “dnsadminapp” ($cpconf->{'dnsadminapp'}) is not executable$err_part.");
        }
        else {
            $dns_admin_path = $cpconf->{'dnsadminapp'};
        }
    }

    return $dns_admin_path;
}

#----------------------------------------------------------------------

sub _encode_args_for_form (@args) {

    local ( $@, $! );
    require Cpanel::Encoder::URI;

    return 'args=' . join( ',', map { Cpanel::Encoder::URI::uri_encode_str($_) } @args );
}

1;
