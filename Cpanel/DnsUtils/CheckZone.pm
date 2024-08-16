package Cpanel::DnsUtils::CheckZone;

# cpanel - Cpanel/DnsUtils/CheckZone.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::CheckZone

=head1 SYNOPSIS

    my $errs_ar = Cpanel::DnsUtils::CheckZone::check_zone(
        'beagle.com',
        $beagle_com_zone_text,
    );

    for my $err_ar (@$errs_ar) {
        print "Line $err_ar->[0]: $err_ar->[1]\n";
    }

… or, if you want an exception on invalidity:

    Cpanel::DnsUtils::CheckZone::assert_validity(
        'beagle.com',
        $beagle_com_zone_text,
    );

=head1 DESCRIPTION

This module looks for errors in a BIND zone file and reports them.

=cut

#----------------------------------------------------------------------

use Cpanel::Binaries            ();
use Cpanel::SafeRun::Object     ();
use Cpanel::IOCallbackWriteLine ();

# stubbed in tests
our $_NAMED_CHECKZONE_PATH;

#----------------------------------------------------------------------

=head2 $zone_errors_hr = check_zone( $ZONE_NAME, $ZONE_TEXT )

B<IMPORTANT:> This can output non-UTF-8 sequences. If you’ll be serializing
this response as JSON, you B<MUST> encode it such that it’ll be valid UTF-8.
(e.g., base64, an extra UTF-8 encode, etc.)

Checks given zones for errors.

$ZONE_NAME is a DNS zone name; $ZONE_TEXT is that zone’s content as
an RFC-1035 zone master file.

Returns an arrayref, one item per error. Each error is represented as
another arrayref:

=over

=item * The line number (1-indexed) of the reported error in $ZONE_TEXT.

=item * A text description of the error. (Can include arbitrary,
non-UTF-8 octet sequences!)

=back

See L<Cpanel::DNSLib::Zone> for an older implementation of similar logic.

=cut

sub check_zone ( $zone_name, $zone_text ) {
    my @errs;

    $_NAMED_CHECKZONE_PATH ||= Cpanel::Binaries::path('named-checkzone');

    my $run = Cpanel::SafeRun::Object->new(
        program => $_NAMED_CHECKZONE_PATH,
        args    => [ '--', $zone_name, '/dev/stdin' ],
        stdin   => $zone_text,
        stderr  => Cpanel::IOCallbackWriteLine->new(
            sub ($line) {
                warn "$_NAMED_CHECKZONE_PATH: $line";
            },
        ),
        stdout => Cpanel::IOCallbackWriteLine->new(
            sub ($line) {
                if ( $line =~ /:([0-9]+):(.*)/ ) {
                    return if ( $1 eq '' );

                    push @errs, [ $1 => $2 ];

                    $errs[-1][1] =~ s/^\s*//g;
                }
            },
        ),
    );

    $run->die_if_error() if $run->signal_code();

    return \@errs;
}

=head2 assert_validity( $ZONE_NAME, $ZONE_TEXT )

Like C<check_zone()> but throws a L<Cpanel::Exception::DNS::InvalidZoneFile>
instance if there are any validity errors.

Returns nothing on success.

=cut

sub assert_validity ( $zone_name, $zone_text ) {
    my $errs_ar = check_zone( $zone_name, $zone_text );

    if (@$errs_ar) {
        $_->[0]-- for @$errs_ar;

        require Cpanel::Exception;
        die Cpanel::Exception::create( 'DNS::InvalidZoneFile', [ by_line => $errs_ar ] );
    }

    return;
}

1;
