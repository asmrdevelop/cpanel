package Cpanel::WebmailRedirect;

# cpanel - Cpanel/WebmailRedirect.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebmailRedirect - Context-agnostic Webmail-redirect logic

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel           ();
use Cpanel::Carp     ();
use Cpanel::CGI::URL ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $redirect_hr = create_webmail_session( $USERNAME, $API_CALLER_CR, %OPTS )

Creates a Webmail session for the given $USERNAME, which may be the name of
a cPanel user or a mail user (e.g., C<hal@example.com>).

(NB: C<$Cpanel::user> B<MUST> be set in order to call this function.)

$API_CALLER_CR is a coderef whose input/output must match
C<Cpanel::API::execute_or_die()>.

%OPTS are:

=over

=item * C<remote_hostname> - Optional, defaults to the API call response’s
C<hostname>. If this value is given, this function assumes that $USERNAME’s
mail is remotely hosted.

=item * C<return_url> - Optional, a URL to save in the new Webmail session
that will be the destination of a “Return to cPanel” link that Webmail
displays.

=item * C<password> - Optional, the remote user’s password. Used for when
authentication is needed.

=back

This returns a hash reference of:

=over

=item * C<url> - The URL to which to send the user.

=item * C<session> - The C<session> variable that the user should
submit with C<url>. This ideally should happen via HTTP C<POST> rather
than C<GET>.

=item * C<warning> - Either undef (if no problems happened) or a message
that indicates a warning about the redirection URL determination to give
to the caller. See below for more details.

=back

To determine the destination host, we apply the following logic:

=over

=item * If we’re logged in via a standard HTTP port, then the target
hostname is the C<webmail.> sibling subdomain to the C<HTTP_HOST>
environment variable. (If C<HTTP_HOST> is not a C<cpanel.> subdomain,
an exception is thrown.) There is no port in the new URL.

=item * If we’re logged in via a nonstandard HTTP port (e.g., 2083),
then the new URL will have the appropriate secured Webmail port number from
L<Cpanel::Services::Ports>.

If the user’s mail is local, then the URL’s
authority is just C<HTTP_HOST>.

If the user’s mail is remote, though,
then the URL authority is either:

=over

=item * $REMOTE_HOSTNAME, if C<HTTP_HOST> is the local hostname, or

=item * C<mail.$HTTP_HOST>, if C<HTTP_HOST> isn’t the local hostname

=back

=item * B<THEN,> once we’re through with all of that, if any of the following
happens:

=over

=item * The intended URL authority does NOT match either $REMOTE_HOSTNAME
(either as given or its default value) or the remote cPanel account’s IP
address. then

=item * An error prevents determination of that match.

=back

… then we throw away the authority section in the URL we have thus far
and revert to $REMOTE_HOSTNAME on the secured Webmail port from
L<Cpanel::Services::Ports>. A human-readable message about this problem
is given in the returned hash reference’s C<warning>.

=back

=cut

sub create_webmail_session ( $username, $api_caller_cr, %opts ) {

    # Verify.pm needs this:
    if ( !$Cpanel::user ) {
        die Cpanel::Carp::safe_longmess('$Cpanel::user is unset!');
    }

    my ( $login, $domain ) = split m<@>, $username, 2;

    my ( $fn, $args_hr ) = ( undef, {} );

    my $pw = $opts{'password'};

    if ($domain) {
        if ( length $pw ) {
            $fn = 'create_webmail_session_for_mail_user_check_password';
            @{$args_hr}{ 'login', 'domain', 'password' } = ( $login, $domain, $pw );
        }
        else {
            $fn = 'create_webmail_session_for_mail_user';
            @{$args_hr}{ 'login', 'domain' } = ( $login, $domain );
        }
    }
    elsif ( length $pw ) {
        die "“password” is for a mail user, not “$login”";
    }
    else {
        $fn = 'create_webmail_session_for_self';
    }

    $args_hr->{'return_url'} = $opts{'return_url'};

    my $result_data = $api_caller_cr->( 'Session', $fn, $args_hr )->data();

    my ( $target_hostname, $target_port );

    my $remote_hostname = $opts{'remote_hostname'};

    $remote_hostname ||= $result_data->{'hostname'};

    if ($remote_hostname) {
        ( $target_hostname, $target_port ) = _get_remote_authority();

        $target_hostname ||= $remote_hostname;
    }
    else {
        ( $target_hostname, $target_port ) = _get_local_authority();
    }

    my $warning;

    if ( $remote_hostname && $remote_hostname ne $target_hostname ) {
        ( $target_hostname, $warning ) = _verify_target_hostname(
            $target_hostname,
            $remote_hostname,
        );

        if ( $remote_hostname eq $target_hostname ) {
            $target_port = _webmails_port();
        }
    }

    my $url = "https://$target_hostname";
    $url .= ":$target_port" if $target_port;

    $url .= "$result_data->{'token'}/login/";

    return {
        url     => $url,
        session => $result_data->{'session'},
        warning => $warning,
    };
}

sub _verify_target_hostname ( $intended, $fallback ) {
    require Cpanel::WebmailRedirect::Verify;

    my $warning = Cpanel::WebmailRedirect::Verify::find_problem( $intended, $fallback );

    return ( ( $warning ? $fallback : $intended ), $warning );
}

#----------------------------------------------------------------------

#=head2 ($hostname, $port) = get_local_authority()
#
#This returns the hostname and port to use when redirecting from the current
#session to a locally-hosted Webmail session. This queries the environment
#to determine the current session’s HTTP hostname and TCP port.
#
#=cut

sub _get_local_authority() {
    my ( undef, $local_hostname ) = _get_cgi_port_and_local_hostname();

    return _standard_port_authority() if _is_standard_port();

    return ( $local_hostname, _webmails_port() );
}

#=head2 ($hostname, $port) = get_remote_authority()
#
#Like C<get_local_authority()> but for a remotely-hosted Webmail session.
#Also unlike C<get_local_authority()>, this function’s C<$hostname> return
#may be empty, in which case the remote host’s hostname should be used.
#
#=cut

sub _get_remote_authority() {
    my ( undef, $local_hostname ) = _get_cgi_port_and_local_hostname();

    return _standard_port_authority() if _is_standard_port();

    my ($target_hostname);

    if ( _gethostname() ne $local_hostname ) {
        require Cpanel::Validate::IP;

        if ( !Cpanel::Validate::IP::is_valid_ip($local_hostname) ) {
            $target_hostname = "mail.$local_hostname";
        }
    }

    return ( $target_hostname, _webmails_port() );
}

sub _webmails_port() {
    require Cpanel::Services::Ports;
    no warnings 'once';

    return $Cpanel::Services::Ports::SERVICE{'webmails'};
}

sub _get_cgi_port_and_local_hostname() {
    my @lack = grep { !$ENV{$_} } qw( SERVER_PORT  HTTP_HOST );
    die "Lack %ENV: [@lack]" if @lack;

    return @ENV{qw( SERVER_PORT  HTTP_HOST )};
}

sub _standard_port_authority() {
    my ( undef, $hostname ) = _get_cgi_port_and_local_hostname();

    if ( 0 != rindex( $hostname, 'cpanel.', 0 ) ) {
        die "Over standard port expect “cpanel.” service subdomain, not “$hostname”!";
    }

    substr( $hostname, 0, 6 ) = 'webmail';

    return ( $hostname, undef );
}

*_is_standard_port = *Cpanel::CGI::URL::port_is_well_known;

# mocked in tests
sub _gethostname {
    require Cpanel::Hostname;
    return Cpanel::Hostname::gethostname();
}

1;
