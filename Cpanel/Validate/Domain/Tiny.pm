package Cpanel::Validate::Domain::Tiny;

# cpanel - Cpanel/Validate/Domain/Tiny.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug        ();
use Cpanel::Validate::IP ();

sub domain_meets_basic_requirements {
    my ( $domainname, $quiet ) = @_;
    return wantarray ? ( 0, 'invalid domain name specified' ) : 0 unless defined $domainname;

    # IP addresses are not valid domain names.
    if (
        $domainname =~ tr{:0-9}{} &&    # It cannot be an ip address if it does not have a digit or a : in it
        $domainname !~ tr{g-z}{}  &&    # It cannot be an ip address if has non-hex characters
        Cpanel::Validate::IP::is_valid_ip($domainname)
    ) {
        Cpanel::Debug::log_warn( $domainname . ' is an IP address, not a domain name' ) if !$quiet;
        return wantarray ? ( 0, 'argument is an IP address, not a domain name' ) : 0;
    }

    # check max domainname length
    if ( length($domainname) > 254 ) {
        Cpanel::Debug::log_warn( $domainname . ' domain name exceeds 254 characters' ) if !$quiet;
        return wantarray ? ( 0, 'domain name exceeds 254 characters' ) : 0;
    }

    # Check tld ending
    # TODO: Use PublicSuffix for this.
    elsif ($domainname !~ m/[.][a-z0-9]+$/i
        && $domainname !~ m/[.]xn--[a-z0-9-]+$/i ) {
        Cpanel::Debug::log_warn( $domainname . ' domain name must have a valid TLD label' ) if !$quiet;
        return wantarray ? ( 0, 'domain name must have a valid TLD label' ) : 0;
    }

    if ( index( $domainname, '.' ) == -1 ) {
        Cpanel::Debug::log_warn("invalid domain name $domainname") if !$quiet;
        return wantarray ? ( 0, "invalid domain name $domainname" ) : 0;
    }

    return wantarray ? ( 1, 'ok' ) : 1;
}
#
sub validdomainname {
    my ( $domainname, $quiet ) = @_;

    my ( $status, $msg ) = domain_meets_basic_requirements( $domainname, $quiet );
    return wantarray ? ( $status, $msg ) : $status if !$status;

  LABELS_LOOP:
    foreach my $label ( split( /\./, $domainname ) ) {

        if (
               length($label) < 64
            && length($label) > 0
            && (
                #
                # Note: assigning regexes into variables
                # makes perl unable to optimize them in advance
                #
                #Checks whether a given $domainname is a valid domain name per RFC 1035.
                # As long as the label starts with letters/digits
                # and ends with letters/digits, you can have '-'
                # in domain labels.

                $label =~ m{
                            \A
                            [a-z0-9]
                            [a-z0-9-]*
                            [a-z0-9]
                            \z
                        }xmsi
                ||

                # single char domain labels are OK.
                $label =~ m{
                            \A
                            [a-z0-9]
                            \z
                        }xmsi
            )
        ) {
            next LABELS_LOOP;
        }

        Cpanel::Debug::log_warn("domain name element $label does not conform to requirements") if !$quiet;
        return wantarray ? ( 0, "domain name element $label does not conform to requirements" ) : 0;
    }
    return wantarray ? ( 1, $domainname ) : 1;
}

1;
