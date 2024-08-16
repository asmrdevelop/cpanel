package Cpanel::APICommon::EmailAuth;

# cpanel - Cpanel/APICommon/EmailAuth.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::APICommon::EmailAuth

=head1 SYNOPSIS

    $results_ar = validate_current_dkims( \@DOMAINS )

=head1 DESCRIPTION

This module houses logic that’s common to the “EmailAuth” modules in
cPanel (UAPI) and WHM API v1.

=cut

#----------------------------------------------------------------------

use Cpanel::App ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $results_ar = validate_current_dkims( \@DOMAINS )

This implements “validate_current_dkims” in both cPanel (UAPI) and WHM API
v1.

See C<Cpanel::DnsUtils::MailRecords::validate_dkim_records_for_domains()>
for output; additionally, this adds to each item of the main array the
following:

=over

=item * C<validity_cache_update> - One of: C<set>, C<unset>, C<valid>,
C<invalid>, C<none>, C<error>. C<none> means that no change was needed,
and C<error> means that the individual domain’s update operation failed.

See L<Cpanel::DKIM::ValidityCache::Sync> for details of what the rest mean.

Really, the only ones users should see normally are C<none> and C<set>.

C<invalid> means that the admin process’s re-verification of DKIM validity
was negative, despite that the user’s verification was positive. C<error>
means some part of the admin process failed. Neither of those should normally
happen but probably will pop up in the wild.

C<valid> and C<unset> are theoretically possible but should be very
rare—particularly C<unset>.

=back

=cut

sub validate_current_dkims {
    my ($domains) = @_;

    require Cpanel::DnsUtils::MailRecords;
    require Cpanel::DKIM::ValidityCache;

    my $result_ar = Cpanel::DnsUtils::MailRecords::validate_dkim_records_for_domains($domains);

    my %update_cache_lookup;

    my %dkim_domain_to_secured;

    for my $res_hr (@$result_ar) {

        # “domain” is actually the DKIM record name,
        # e.g., default._domainkey.example.com
        my $secured_domain = $res_hr->{'domain'} =~ s<\A.+\._domainkey\.><>r;
        $dkim_domain_to_secured{ $res_hr->{'domain'} } = $secured_domain;

        next if $res_hr->{'state'} ne 'VALID';
        next if Cpanel::DKIM::ValidityCache->get($secured_domain);

        # At this point we know that DKIM is valid but that the cache
        # thinks it’s invalid. We’ll fire off an admin request to update
        # the cache for this domain.
        $update_cache_lookup{$secured_domain} = 1;
    }

    my $update_hr;
    if (%update_cache_lookup) {
        local $@;
        $update_hr = _get_dkim_update_hr( [ keys %update_cache_lookup ] );
    }

    $update_hr ||= {};

    for my $res_hr (@$result_ar) {
        my $update_status;

        my $secured_domain = $dkim_domain_to_secured{ $res_hr->{'domain'} };

        if ( exists $update_cache_lookup{$secured_domain} ) {
            $update_status = $update_hr->{$secured_domain} // 'error';
        }
        else {
            $update_status = 'none';
        }

        $res_hr->{'validity_cache_update'} = $update_status;
    }

    return $result_ar;
}

sub _get_dkim_update_hr {
    my ($valid_domains_ar) = @_;

    my $update_hr;

    local $@;

    if ( Cpanel::App::is_whm() ) {

        # In WHM we can set the validity cache directly
        # because we’ve already verified DKIM (as root).

        require Cpanel::DKIM::ValidityCache::Write;

        $update_hr = {};
        for my $domain (@$valid_domains_ar) {
            my $update_status;
            my $did_set;

            if ( eval { $did_set = Cpanel::DKIM::ValidityCache::Write->set($domain); 1 } ) {
                $update_status = $did_set ? 'set' : 'valid';
            }
            else {
                warn;
                $update_status = 'error';
            }

            $update_hr->{$domain} = $update_status;
        }
    }
    else {

        # In cPanel we have to fire an admin call that will itself
        # reverify the results (as root).

        require Cpanel::AdminBin::Call;

        warn if !eval { $update_hr = Cpanel::AdminBin::Call::call( 'Cpanel', 'emailauth', 'UPDATE_DKIM_VALIDITY_CACHE_FOR_DOMAINS', $valid_domains_ar ) };
    }

    return $update_hr;
}

1;
