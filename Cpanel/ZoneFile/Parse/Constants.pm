package Cpanel::ZoneFile::Parse::Constants;

# cpanel - Cpanel/ZoneFile/Parse/Constants.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ZoneFile::Parse::Constants

=head1 SYNOPSIS

    my $is_ok = exists $Cpanel::ZoneFile::Parse::Constants::EXPECTED_STATUS{$status};

=head1 DESCRIPTION

This module contains common logic for parsing DNS zone files via
L<DNS::LDNS>.

=cut

#----------------------------------------------------------------------

BEGIN {

    # Bug in DNS::LDNS: “Subroutine DNS::LDNS::RData::compare redefined”.
    # “no warnings” doesn’t silence it, so we have to discard it.
    # cf. https://rt.cpan.org/Public/Bug/Display.html?id=134388
    local $SIG{'__WARN__'} = sub { };

    require DNS::LDNS;
}

#----------------------------------------------------------------------

# See implementation of ldns_zone_new_frm_fp_l in LDNS’s zone.c
# for notes on the interpretation of these status codes.
our %EXPECTED_STATUS = (
    DNS::LDNS::LDNS_STATUS_OK() => undef,

    # When LDNS finds a directive, e.g., $TTL:
    DNS::LDNS::LDNS_STATUS_SYNTAX_INCLUDE() => undef,
    DNS::LDNS::LDNS_STATUS_SYNTAX_ORIGIN()  => undef,
    DNS::LDNS::LDNS_STATUS_SYNTAX_TTL()     => undef,

    # When LDNS finds an empty line OR end of file:
    DNS::LDNS::LDNS_STATUS_SYNTAX_EMPTY() => undef,
);

1;
