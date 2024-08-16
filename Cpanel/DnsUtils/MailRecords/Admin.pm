package Cpanel::DnsUtils::MailRecords::Admin;

# cpanel - Cpanel/DnsUtils/MailRecords/Admin.pm    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::MailRecords::Admin

=head1 DESCRIPTION

This module contains ancillary logic for L<Cpanel::DnsUtils::MailRecords>
that requires administrator privileges.

=head1 FUNCTIONS

=head2 $helo_ips_hr = get_mail_helo_ips( \@DOMAINS )

Returns the outgoing public IP address and HELO for each member of
@DOMAINS. The return is a single hashref whose keys are the @DOMAINS
members and whose values are hashrefs:

=over

=item * C<public_ip>

=item * C<helo>

=back

This format is fairly tightly coupled to email deliverability validation.
It probably shouldn’t be used in other contexts.

=cut

sub get_mail_helo_ips {
    my ($domains_ar) = @_;

    require Cpanel::SMTP::HELO;
    require Cpanel::DIp::Mail;

    my $lookup_hr = Cpanel::DIp::Mail::get_public_mail_ips_for_domains($domains_ar);

    my $helo_obj = Cpanel::SMTP::HELO->load();

    for my $domain (@$domains_ar) {
        $lookup_hr->{$domain} = {
            public_ip => $lookup_hr->{$domain},
            helo      => $helo_obj->get_helo_for_domain($domain),
        };
    }

    return $lookup_hr;
}

1;
