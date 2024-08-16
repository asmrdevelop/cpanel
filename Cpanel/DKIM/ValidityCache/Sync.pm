package Cpanel::DKIM::ValidityCache::Sync;

# cpanel - Cpanel/DKIM/ValidityCache/Sync.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DKIM::ValidityCache::Sync

=head1 SYNOPSIS

    my $result_hr = sync_domains( \@domains );

=head1 DESCRIPTION

This module implements validity cache updates for cPanel & WHM
processes.

=cut

#----------------------------------------------------------------------

use Cpanel::DKIM::ValidityCache::Write ();
use Cpanel::DnsUtils::MailRecords      ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $hr = sync_domains( \@DOMAINS )

Updates the DKIM validity cache for @DOMAINS.

The return is a hashref whose keys are the @DOMAINS and the values are
one of:

=over

=item * C<set> - Domain was not marked valid in the cache, but the DKIM
validity check passed, so the cache now marks the domain as valid.

=item * C<unset> - The opposite of C<set>: the domain was marked valid,
but the domain failed its validity check and so is no longer marked valid
in the cache.

=item * C<valid> - Domain was marked valid, and the DKIM validity check
passed, so no change was needed.

=item * C<invalid> - The opposite of C<valid>: domain was not marked
valid and also failed the DKIM validity check, so no change was needed.

=back

Note that F<scripts/refresh-dkim-validity-cache> also implements this
functionality but as a script, and with several different options.
It might be ideal to refactor it to use this logic, but it would also
significantly complicate this function.

=cut

sub sync_domains {
    my ($domains_ar) = @_;

    my %result;

    my $result_ar = Cpanel::DnsUtils::MailRecords::validate_dkim_records_for_domains($domains_ar);
    for my $ridx ( 0 .. $#$result_ar ) {
        my $res_hr         = $result_ar->[$ridx];
        my $secured_domain = $domains_ar->[$ridx];

        my $is_valid = $res_hr->{'state'} eq 'VALID';
        my $fn       = $is_valid ? 'set' : 'unset';

        my $resp_str;

        local $@;
        my $updated_yn = eval { Cpanel::DKIM::ValidityCache::Write->$fn($secured_domain) } // do {
            warn;
            next;
        };

        if ($updated_yn) {
            $resp_str = $fn;
        }
        elsif ($is_valid) {
            $resp_str = 'valid';
        }
        else {
            $resp_str = 'invalid';
        }

        $result{$secured_domain} = $resp_str;
    }

    return \%result;
}

1;
