package Whostmgr::API::1::Analytics;

# cpanel - Whostmgr/API/1/Analytics.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Analytics::UiIncludes ();
use Cpanel::Locale                ();

use Whostmgr::API::1::Utils ();

use constant NEEDS_ROLE => {
    participate_in_analytics => undef,
};

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Analytics - WHM API functions to manage server participation
in browser-based data gathering.

NOTE: Analytics UI includes are disabled by default and are strictly opt-in only.

=head1 SUBROUTINES

=over 4

=item participate_in_analytics()

Enable or disable server participation in browser based data gathering for web
analytics. This function takes a single parameter, enabled. 1 enables
participation, and 0 disables.

This function has no returns.

=cut

sub participate_in_analytics {
    my ( $args, $metadata ) = @_;

    my $enabled = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'enabled' );

    my ( $status, $reason );
    if ( $enabled eq '1' ) {
        $status = Cpanel::Analytics::UiIncludes::enable();
        $reason = _locale()->maketext("The system could not enable [asis,cPanel] Web Analytics for the server.") unless $status;
    }
    elsif ( $enabled eq '0' ) {
        $status = Cpanel::Analytics::UiIncludes::disable();
        $reason = _locale()->maketext("The system could not disable [asis,cPanel] Web Analytics for the server.") unless $status;
    }
    else {
        $status = 0;
        $reason = _locale()->maketext("The enabled value must be 0 or 1.");
    }

    unless ($status) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $reason;
        return;
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

my $locale;

sub _locale {
    return $locale if $locale;

    return $locale = Cpanel::Locale->get_handle();
}

=back

=cut

1;
