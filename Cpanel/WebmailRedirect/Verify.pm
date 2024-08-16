package Cpanel::WebmailRedirect::Verify;

# cpanel - Cpanel/WebmailRedirect/Verify.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel            ();
use Cpanel::Carp      ();
use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $problem = find_problem($INTENDED, $FALLBACK)

Checks whether $INTENDED is a safe hostname to use to reach the same
server as $FALLBACK. If it is, undef is returned; if not, or if the system
failed to complete the check, a human-readable description of the problem
is returned.

Note that currently this only checks DNS. We could expand this later to
check TCP and even TLS.

=cut

sub find_problem ( $intended, $fallback ) {
    my $warning;

    # Sanity check
    if ( !$Cpanel::user ) {
        die Cpanel::Carp::safe_longmess('$Cpanel::user is unset!');
    }

    # NB: Informal testing suggests that for most purposes
    # two gethostbyname() calls in series are faster than parallel
    # queries via Net::DNS::Resolver or AnyEvent::DNS.
    #
    if ( my $fallback_addr = _gethostbyname($fallback) ) {
        if ( my $intended_addr = _gethostbyname($intended) ) {

            # If the intended name’s IP address matches that of the
            # fallback hostname, then the intended hostname is OK.
            # If not, though, we have to discover the remote user’s
            # IP address; we can use the intended name if and only if
            # it matches the remote user’s IP address.
            if ( $fallback_addr ne $intended_addr ) {
                require Cpanel::LinkedNode::Worker::User;
                require Cpanel::LinkedNode::Worker::cPanel;

                my $alias_token_ar = Cpanel::LinkedNode::Worker::User::get_alias_and_token('Mail') or do {

                    # sanity check
                    die "No “Mail” worker set up for “$Cpanel::user”?!?";
                };

                my $result = Cpanel::LinkedNode::Worker::cPanel::call_uapi_from_anywhere(
                    username     => $Cpanel::user,
                    worker_alias => $alias_token_ar->[0],
                    token        => $alias_token_ar->[1],
                    module       => 'StatsBar',
                    function     => 'get_stats',
                    arguments    => {
                        display => 'dedicatedip|sharedip',
                    },
                );

                require Socket;
                $intended_addr = Socket::inet_ntoa($intended_addr);
                $fallback_addr = Socket::inet_ntoa($fallback_addr);

                if ( my $err = $result->errors_as_string() ) {
                    $warning = locale()->maketext( '“[_1]” ([_2]) does not match “[_3]” ([_4]), and “[_5]” on “[_3]” failed: [_6]', $intended, $intended_addr, $fallback, $fallback_addr, 'StatsBar::get_stats', $err );
                }
                else {
                    my $remote_ip_addr = $result->data()->[0]{'value'};

                    if ( $remote_ip_addr ne $intended_addr ) {
                        $warning = locale()->maketext( '“[_1]” ([_2]) does not match “[_3]” ([_4]), and “[_3]” reports that “[_5]”’s [asis,IPv4] address is “[_6]”.', $intended, $intended_addr, $fallback, $fallback_addr, $Cpanel::user, $remote_ip_addr );
                    }
                }
            }
        }
        else {

            # Let’s assume that this is a problem with the domain’s
            # configuration. Thus, unlike when the “fallback” name
            # doesn’t resolve, we share this error with the user.
            $warning = locale()->maketext( 'The host name “[_1]” does not resolve to any [asis,IPv4] addresses.', $intended );
        }
    }
    else {

        # This is a problem on the administrative end, so we don’t
        # expose the error directly.
        my $err = Cpanel::Exception->create_raw("“$fallback” did not resolve to an IPv4 address.");
        warn $err->get_string();

        $warning = locale()->maketext( 'Verification of “[_1]” failed. ([_2])', $intended, 'XID ' . $err->id() );
    }

    return $warning;
}

sub _gethostbyname ($name) {
    return gethostbyname $name;
}

1;
