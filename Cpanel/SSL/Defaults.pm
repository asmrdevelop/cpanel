package Cpanel::SSL::Defaults;

# cpanel - Cpanel/SSL/Defaults.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $ALL_PROTOS_ORDERED = [qw/SSLv2 SSLv3 TLSv1 TLSv1.1 TLSv1.2/];
our $ALL_PROTOS         = { map { $_ => 1 } @$ALL_PROTOS_ORDERED };

our $BANNED_PROTOS = [qw/SSLv2 SSLv3 TLSv1 TLSv1.1/];

sub all_protos_ordered {
    return $ALL_PROTOS_ORDERED;
}

our $_EA4_PROTOS;

sub ea4_all_protos {
    require Perl::Phase;
    Perl::Phase::assert_is_run_time();
    if ( !$_EA4_PROTOS ) {
        $_EA4_PROTOS = { %{$ALL_PROTOS} };
        if ( my $tls13 = ea4_has_tls13() ) {
            $_EA4_PROTOS->{$tls13} = 1;
        }
    }

    return $_EA4_PROTOS;
}

sub ea4_has_tls13 {
    require Cpanel::OS;
    return "TLSv1.3" if -x Cpanel::OS::ea4_modern_openssl();
    return;
}

# This is the Mozilla Server Side TLS 5.0 recommended "intermediate" config:
#  https://ssl-config.mozilla.org/#server=apache&server-version=2.4&config=intermediate&openssl-version=1.0.1e
# and:
#  https://wiki.mozilla.org/Security/Server_Side_TLS
# TLSv1.3 ciphers are excluded because it is not yet supported here. This
# setting is designed to be PCI compliant.  All the ciphers in this list
# require TLS 1.2, so users wanting to enable older TLS versions will need to
# configure a different set of cipher suites as well.
#
# Note that since cPanel does not support non-RSA certificates, the ECDSA
# options will not be used until we support that type of certificate.  They're
# left in so they'll automatically be used when we do.  Similar comments apply
# to ChaCha20.
sub default_cipher_list {
    return join(
        ':', qw(
          ECDHE-ECDSA-AES128-GCM-SHA256
          ECDHE-RSA-AES128-GCM-SHA256
          ECDHE-ECDSA-AES256-GCM-SHA384
          ECDHE-RSA-AES256-GCM-SHA384
          ECDHE-ECDSA-CHACHA20-POLY1305
          ECDHE-RSA-CHACHA20-POLY1305
          DHE-RSA-AES128-GCM-SHA256
          DHE-RSA-AES256-GCM-SHA384
        )
    );
}

=head1 NAME

Cpanel::SSL::Defaults

=head2 format_protocol_list($protos, $format)

Format a list of TLS protocols in the arrayref $protos as specified by the
hashref $format.

$protos should contain a list of desired protocols from the hash $ALL_PROTOS.

$format can contain the following keys:

=over 4

=item B<type>

This is C<positive> if the format should be a list of supported protocols, and
C<negative> if the format should be a list of excluded protocols.

=item B<delimiter>

This is a string representing the delimiter between protocols, such as a space
or colon.

=item B<negation>

This is the character indicating the negation if I<type> is C<negative>, such as
an exclamation point.

=item B<all>

If the I<type> is C<negative>, use this string instead of "SSLv23" as the first
item in the list.  This is needed for Exim, where this should be an empty string.

=item B<separator>

Some servers use an underscore instead of a dot in C<TLSv1.1> and C<TLSv1.2>.
For those servers, you can set this parameter to an underscore.

=back

For a list like the following, use C<<type => 'positive', delimiter => ' '>>:

  TLSv1 TLSv1.1 TLSv1.2

For a list like the following, use
C<<type => 'negative', delimiter => ':', negation => '!'>>:

  SSLv23:!SSLv2:!SSLv3

=cut

sub format_protocol_list {
    my ( $protos, $format ) = @_;
    my $all = $format->{all} // 'SSLv23';

    return $all if @$protos == scalar keys %$ALL_PROTOS;

    $ALL_PROTOS->{$_} || die "Unknown protocol '$_'" for @$protos;

    my $proto_map = { map { $_ => 1 } @$protos };
    my $positive  = $format->{type} eq 'positive' ? 1 : 0;
    my @entries   = grep { ( $proto_map->{$_} // 0 ) == $positive } sort keys %$ALL_PROTOS;
    @entries = map { s/\./$format->{separator}/r } @entries if $format->{separator};
    my $delimiter = $format->{delimiter} . ( $positive ? '' : $format->{negation} );
    unshift @entries, $all unless $positive;
    return join( $delimiter, @entries );
}

sub default_ssl_min_protocol {
    return 'TLSv1.2';
}

sub default_protocol_list {
    my ($format) = @_;

    # Virtually nobody implements
    # TLS 1.1 without TLS 1.2, so supporting it independently is not worthwhile.
    # PCI DSS will completely forbid TLS 1.0 and earlier as of June 2018, so
    # this setting is PCI compliant.
    return format_protocol_list( [qw/TLSv1.2/], $format );
}

=head2 has_banned_TLS_protocols($protocol_str)

Takes a single TLS protocol string argument.

The string should use underscore separators and be syntactically similar to, "SSLv23:!SSLv2:!SSLv3:!TLSv1:!TLSv1_1".

Returns an array of banned TLS protocols that the string enables.

Returns an empty array if there are no banned protocols.

=cut

sub has_banned_TLS_protocols {
    my ($protocol_str) = @_;

    return () if !$protocol_str;

    require Cpanel::SSL::Protocols;
    my $tls_versions;
    {
        local $@;
        $tls_versions = eval { Cpanel::SSL::Protocols::interpret_version_string($protocol_str) };
        if ( my $excep = $@ ) {
            require Cpanel::Debug;
            Cpanel::Debug::log_info($excep);

            # if we can't interpret the TLS string, we will assume it is using all banned protocols.
            return @{$BANNED_PROTOS};
        }
    }

    return grep { $tls_versions->{$_} } @{$BANNED_PROTOS};
}

sub banned_protos {
    return $BANNED_PROTOS;
}

1;
