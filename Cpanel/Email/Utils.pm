package Cpanel::Email::Utils;

# cpanel - Cpanel/Email/Utils.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::StringFunc::Trim         ();
use Cpanel::StringFunc::UnquoteMeta  ();
use Cpanel::Validate::EmailRFC       ();
use Cpanel::Validate::EmailLocalPart ();

#This function was extracted from Cpanel::API::Email.
#What it does is .. below ..
#
sub get_forwarders_from_string {
    my ($forwarder_csv) = @_;

    if ( $forwarder_csv !~ tr{a-zA-Z0-9}{}c ) {

        # Short circuit on an alphanumeric string
        return wantarray ? ($forwarder_csv) : [$forwarder_csv];
    }

    # to leave \, as \, uncomment this:
    # $forwarder_csv =~ s{\\,}{\\\\,}g;
    my @forwarders =
        ( index( $forwarder_csv, ',' ) == -1 || $forwarder_csv =~ /^[\s"]*\:(?:fail|defer|blackhole|include)\:/ )
      ? ($forwarder_csv)
      : split( /(?<![\\]),/, $forwarder_csv );

    for my $forward (@forwarders) {
        $forward = Cpanel::StringFunc::Trim::ws_trim($forward);
        if ( index( $forward, q{"} ) == 0 ) {
            $forward =~ s{^"}{}g;
            $forward =~ s{"$}{}g;
            $forward = Cpanel::StringFunc::Trim::ws_trim($forward);
        }

        $forward = Cpanel::StringFunc::UnquoteMeta::unquotemeta($forward);
    }

    return wantarray ? @forwarders : \@forwarders;
}

sub normalize_forwarder_quoting {
    my ($addy) = @_;

    #strip leading/trailing quotes
    if ( index( $addy, q{"} ) > -1 ) {
        $addy =~ s/\A"+//s;
        $addy =~ s/"+\z//s;
    }

    #If it's not an email address, assume that it's meant to be a
    #shell command, and quote it.
    if (   !Cpanel::Validate::EmailRFC::is_valid($addy)
        && !Cpanel::Validate::EmailLocalPart::is_valid($addy) ) {    # email address
        $addy =~ s{([",])}{\\$1}g if $addy =~ tr{",}{};
        substr( $addy, 0, 0, '"' );
        $addy .= '"';
    }

    return $addy;
}

1;
