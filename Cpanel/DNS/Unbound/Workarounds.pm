package Cpanel::DNS::Unbound::Workarounds;

# cpanel - Cpanel/DNS/Unbound/Workarounds.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::DNS::Unbound                      ();
use Cpanel::DNS::Unbound::Workarounds::Config ();
use Socket                                    ();

use constant {
    _EAFNOSUPPORT => 97,
};

use constant _KNOWN_IPV6_SEND_ERRORS => (
    101,    # ENETUNREACH
    113,    # EHOSTUNREACH
    1,      # EPERM
);

=encoding utf-8

=head1 NAME

Cpanel::DNS::Unbound::Workarounds - Determine workarounds needed for a L<DNS::Unbound> object to function with the local system’s network and firewall.

=head1 SYNOPSIS

    use Cpanel::DNS::Unbound::Workarounds ();

    Cpanel::DNS::Unbound::Workarounds::set_up_dns_resolver_workarounds();

=head1 DESCRIPTION

Some networks or firewalls block or break DNS resolution is various ways.
This module
can determine and store the configuration flags needed to get
a working C<DNS::Unbound> object.

=head1 FUNCTIONS

=head2 determine_workaround_config_or_die()

This function
tries various combinations of L<DNS::Unbound> configuration options that are known
to workaround these types of breakages to determine which flags are needed to get
a working L<DNS::Unbound> object.

If no combination of configuration flags can be determined to get a working
L<DNS::Unbound> object on this system this function with die.

If the system can successfully determine the configuration flags needed to
get a working L<DNS::Unbound> object on this system it will return a hashref unbound
configurations keys and values in the following format:

  {
    'do-ip6' => 'no'
    'do-udp' => 'no',
    ...
  }

For information on the specific options that this can return, see
L<Cpanel::DNS::Unbound::Workarounds::Config>.

There is one additional option, C<do-ip6>=C<no>, that this returns if the
system cannot create IPv6 sockets. While this doesn’t appear to interfere
with libunbound’s functionality, as of version 1.9.3 libunbound creates
a fair bit of noise in its log in response to IPv6 socket creation failures.
To make life easier, then, on everyone who reads those logs, we tell
libunbound to forgo IPv6 if we know in advance that it’s going to fail.

Ideally we would also proactively detect states where the system can create
IPv6 sockets but can’t use them for DNS (e.g., L<sendto(2)> gives
ENETUNREACH) since libunbound does complain about these as well. But for now
we don’t have a good way to detect that state.

=cut

sub determine_workaround_config_or_die {

    my %opts;

    if ( !_can_send_ipv6_udp_packet() ) {
        $opts{'do-ip6'} = 'no';
    }

    # First try to see if the resolver works with no flags.
    return \%opts if _test_unbound_with_flags(%opts);

    my @config_key_values = Cpanel::DNS::Unbound::Workarounds::Config::ORDERED_WORKAROUNDS();

    while ( my ( $key, $value ) = splice @config_key_values, 0, 2 ) {
        next if $opts{$key};

        if ( _test_unbound_with_flags( %opts, $key => $value ) ) {
            $opts{$key} = $value;
            return \%opts;
        }

        $opts{$key} = $value if $key eq 'do-ip6';
    }

    # Nothing worked so return an empty set
    die "The system failed to find a configuration that allows libunbound to function.";

}

=head2 set_up_dns_resolver_workarounds()

This function will call C<determine_workaround_config_or_die()>
and update the flag files defined by C<Cpanel::DNS::Unbound::Workarounds::Config>
on disk so they can later be used by C<Cpanel::DNS::Unbound::Workarounds::Read::enable_workarounds_on_unbound_object>.

This function returns the same hashref as C<determine_workaround_config_or_die()>
with the notable exception that is C<determine_workaround_config_or_die()> throws
an exception, this function will return undef.

=cut

sub set_up_dns_resolver_workarounds {
    my $flags_hr  = eval { determine_workaround_config_or_die() };
    my $had_error = $@;
    warn if $had_error;

    # If we fail we clear the flags so we do not
    # hide errors in UIs
    require Cpanel::DNS::Unbound::Workarounds::Write;
    Cpanel::DNS::Unbound::Workarounds::Write::sync_workaround_config_to_storage( $flags_hr // {} );

    return $flags_hr;
}

sub _test_unbound_with_flags {
    my (%flags) = @_;

    my $unbound = DNS::Unbound->new()->enable_threads();

    foreach my $flag ( keys %flags ) {
        $unbound->set_option( $flag => $flags{$flag} );
    }

    # Explictly pass in an unbound object that we
    # have configured to test the flags.
    my $cp_ub = Cpanel::DNS::Unbound->new( unbound => $unbound );

    # This is a cPanel-configured TXT RRSET whose return payload
    # should reliably exceed 512 bytes. You can verify this via:
    #
    #   dig +ignore +noedns _dns_over_512.cpanel.net TXT
    #
    my @ret = $cp_ub->recursive_query( '_dns_over_512.cpanel.net', 'TXT' );

    return scalar @ret ? 1 : 0;
}

# tested directly
sub _can_send_ipv6_udp_packet {
    my $fd;

    my $create_ok = socket( $fd, Socket::PF_INET6(), Socket::SOCK_DGRAM(), Socket::IPPROTO_UDP() );

    return 0 if $! == _EAFNOSUPPORT();

    if ( !$create_ok && $! ) {

        # Since we do not know what other possible errors could
        # happen we warn on unexpected failures
        warn "socket(PF_INET6, SOCK_STREAM): $!";
    }

    my $addr = Socket::pack_sockaddr_in6( 53, Socket::inet_pton( Socket::AF_INET6(), '::1' ) );

    my $send_ok = _send( $fd, 0, 0, $addr );

    return 1 if $send_ok;

    return 0 if grep { $! == $_ } _KNOWN_IPV6_SEND_ERRORS;

    if ($!) {

        # Since we do not know what other possible errors could
        # happen we warn on unexpected failures
        warn "send(SOCKET, 0, 0, ::1:53): $!";
    }

    # Since we did not get _ENETUNREACH we do not want to disable ipv6
    # as this is the only error we know of that proves ipv6 is disabled
    return 1;
}

sub _send (@args) {
    return &CORE::send(@args);    ## no critic qw(Ampersand)
}

#sub _notify_about_recursive_dns_problems {
# my ($flags_hr) = @_;

#
# This function expects to be passed the result from
# set_up_dns_resolver_workarounds or determine_workaround_config_or_die (if exceptions are trapped)
#
#
# if ( !$flags_hr || scalar keys %$flags_hr ) {
#    _notify_about_recursive_dns_problems($flags_hr);
# }

#
# TODO: This is intentionally not implemented at this time
# because we do not know how many people are affected and
# are concerned about the influx of notifications this could cause
# when we are already through the initial slow roll out period for v84
#
# The below is a placeholder for the suggested implementation
# which will be done at a time were we are not concerned
# about sending additional notificaitons.
#
# The system has detected a problem with the network or firewall configuration that prevents recursive dns resolution
# if ($flags_hr && scalar keys %$flags_hr) {
#
# The system was able to temporarily work around the problem by enabling the following work arounds: %{MAP flags to localized strings}
#
# These workarounds allow the system to work as expected, however not address the underlying network or firewall configuration.
#
# } else {
#
# The system attempted multiple workarounds, however dns resolution could not be accomplished.
#
# }
#
# It is important to resolve any firewall or network configuration issues that prevent recursive dns resolution in order for the system to perform reliability.
# The system will check again during daily maintenance and continue to report changes
#
# You can force a new check with
#
# whmapi1 set_up_dns_resolver_workarounds
#
# You can disable notifications here:
#
# WHM link
#

#    return;
#}

1;
