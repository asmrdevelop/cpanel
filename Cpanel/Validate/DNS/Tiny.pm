package Cpanel::Validate::DNS::Tiny;

# cpanel - Cpanel/Validate/DNS/Tiny.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Validate::DNS::Tiny - A drop in counterpart for Cpanel::Validate::Domain::Tiny

=head1 SYNOPSIS

    use Cpanel::Validate::DNS::Tiny;

    my($is_valid,$message) = Cpanel::Validate::DNS::Tiny::valid_dns_name($domain, $quiet);

=head1 WARNING

This interface is intended to match Cpanel::Validate::Domain::Tiny so it can
be a drop in switch.

=head1 DESCRIPTION

This module is intended to be used where Cpanel::Validate::Domain::Tiny
is currently in use where we need to allow not only valid domains but
valid dns labels.  The most common use case is for DKIM and SPF record
name checks.  This module will permit underscores in dns labels whereas
Cpanel::Validate::Domain::Tiny will not

=cut

use Cpanel::Validate::Domain::Tiny ();
use Cpanel::Debug                  ();
#

=head2 valid_dns_name($domainname, $quiet)

Determine is a domainname is a valid dns label name.

=over 2

=item Input

=over 3

=item $domainname C<SCALAR>

    The domain name to check

=item $quiet C<SCALAR>

    If passed a true value then logging
    is suppressed.

=back

=item Output

=over 3

=item $is_valid C<SCALAR>

    Returns true if the domainname is a valid dns name.

=item $message C<SCALAR>

    Returns a message explaining why domainname is valid or invalid.

=back

=back

=cut

sub valid_dns_name {
    my ( $domainname, $quiet ) = @_;

    my ( $status, $msg ) = Cpanel::Validate::Domain::Tiny::domain_meets_basic_requirements( $domainname, $quiet );
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
                #
                # For DNS names we allow a underscore to proceed or terminate the
                # label

                $label =~ m{
                            \A
                            [a-z0-9_]
                            [a-z0-9-]*
                            [a-z0-9_]
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
