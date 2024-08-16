package Cpanel::Server::Handlers::Httpd::CGI;

# cpanel - Cpanel/Server/Handlers/Httpd/CGI.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Httpd::CGI

=head1 SYNOPSIS

    Cpanel::Server::Handlers::Httpd::CGI::handle( %OPTS );

=head1 DESCRIPTION

This is cphttpd’s handler for CGI applications.

=cut

#----------------------------------------------------------------------

use Cpanel::FastSpawn::InOut ();

use constant _HTTP_PREFIX_HEADERS => (
    'accept',
    'accept-language',
    'cache-control',
    'cookie',
    'connection',
    'dnt',
    'host',
    'referer',
    'user-agent',
);

use constant _NON_PREFIX_HEADERS => (
    'content-length',
    'content-type',
);

# referenced from tests
use constant _ENV_FROM_CALLER => (
    'GATEWAY_INTERFACE',
    'REMOTE_ADDR',
    'REMOTE_PORT',
    'REQUEST_METHOD',
    'REQUEST_URI',
    'SERVER_ADDR',
    'SERVER_PORT',
    'SERVER_PROTOCOL',
    'SERVER_SOFTWARE',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 handle( %OPTS )

This serves up a CGI application in a subprocess. The necessary environment
variables are set in the subprocess to satisfy a generic CGI application.

%OPTS are:

=over

=item * C<server_obj> - An instance of L<Cpanel::Server>.

=item * C<setuid> - The name of the user to run the process as.

=item * C<script_name> - The value to set as the SCRIPT_NAME environment
variable. From this value and C<server_obj>’s document the PATH_INFO
environment variable will also be deduced and (if appropriate) set.

=item * C<script_filename> - The path of the CGI script to run.
This value is also set as the SCRIPT_FILENAME environment variable.

=back

=head3 Environment

This expects a number of environment variables to be set already.

=head3 Security

It would be ideal to restrict the setuid here to the child process only
because this would allow reuse of the HTTP connection via HTTP/1.1 keep-alive.
This would, however, entail doing all of the I/O between the child process
and the remote client (including TLS) as root. Because the security risk of
that scenario outweighs the potential gain from use of HTTP/1.1 keep-alive, we
disable HTTP keep-alive (i.e., send C<Connection: close> as part of the
response headers), set the C<server_obj>’s “last request” flag to on, and
make both the parent and the child run as the C<setuid> user.

=cut

sub handle {
    my (%OPTS) = @_;

    my @missing = grep { !defined $ENV{$_} } _ENV_FROM_CALLER();
    warn "Missing environment from caller: @missing" if @missing;

    # These we require:
    @missing = grep { !defined $ENV{$_} } ('HOST');
    die "Missing environment from caller: @missing" if @missing;

    # A sanity-check backup to logic in the main Httpd.pm.
    if ( -1 != index $OPTS{'script_filename'}, '..' ) {
        die "Invalid “script_filename” ($OPTS{'script_filename'})";
    }

    # $server_obj->memorized_chdir( $opts{'docroot'} );
    $OPTS{'server_obj'}->switchuser_or_reset_connection( $OPTS{'setuid'} );

    # Can we use cpanel::cpsrvd::cgiHandler here so we do not have to maintain
    # two of these?

    my $hdrs_hr = $OPTS{'server_obj'}->request()->get_headers();

    my @copy = (
        ( map { [ 'HTTP_' => $_ ] } _HTTP_PREFIX_HEADERS() ),
        ( map { [ q<>     => $_ ] } _NON_PREFIX_HEADERS() ),
    );

    my ( @env_keys, @env_values );

    for my $this_copy (@copy) {
        my ( $pfx, $hdr ) = @$this_copy;

        my $val = $hdrs_hr->{$hdr} // next;

        my $env_name = $pfx . ( $hdr =~ tr<a-z-><A-Z_>r );

        push @env_keys,   $env_name;
        push @env_values, $val;
    }

    local @ENV{@env_keys} = @env_values;

    local $ENV{'SERVER_ADMIN'} = "administrator\@$ENV{'HOST'}";

    local $ENV{'SCRIPT_NAME'} = $OPTS{'script_name'};

    # get_document() returns the path with a leading “.”, so we need to
    # strip that out before deducing PATH_INFO.
    my $doc       = substr( $OPTS{'server_obj'}->request()->get_document(), 1 );
    my $path_info = substr( $doc,                                           length $OPTS{'script_name'} );

    local $ENV{'PATH_INFO'} = $path_info if length $path_info;

    local $ENV{'SCRIPT_FILENAME'} = $OPTS{'script_filename'};

    # We patch Mailman to look for this environment variable when it creates
    # the session cookie: if CPANEL is set, then it prefixes the cookie’s
    # Path with “/3rdparty”. That’s great for Mailman sessions that run
    # inside of cPanel but fatal for plain CGI sessions.
    #
    delete $ENV{'CPANEL'};

    my $pid = Cpanel::FastSpawn::InOut::inout( my $cgi_wtr, my $cgi_rdr, $OPTS{'script_filename'} );

    # FastSpawn blocks the parent process while the child does exec().
    # If the exec() fails, then the child process ends right away,
    # so let’s check for that.
    if ( $pid == waitpid $pid, 1 ) {
        require Cpanel::ChildErrorStringifier;

        my $cstr = Cpanel::ChildErrorStringifier->new( $?, $OPTS{'script_filename'} );
        $cstr->die_if_error();

        die "Process $pid ended prematurely (but in success??)!";
    }

    $OPTS{'server_obj'}->get_handler('SubProcess')->handler(
        'subprocess_name'         => $OPTS{'script_filename'},
        'subprocess_pid_to_reap'  => $pid,
        'subprocess_read_handle'  => $cgi_rdr,
        'subprocess_write_handle' => $cgi_wtr,
    );

    return;
}

1;
