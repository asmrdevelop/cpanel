package Cpanel::SSL::Auto::Run::HandleVhost::ProviderDCV;

# cpanel - Cpanel/SSL/Auto/Run/HandleVhost/ProviderDCV.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::HandleVhost::ProviderDCV

=head1 DESCRIPTION

This module implements the logic to run the AutoSSL provider’s
C<get_vhost_dcv_errors()> method. This is nontrivial
because of wildcard reduction.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::SSL::Auto::ProviderDCV ();
use Cpanel::SSL::Auto::Wildcard    ();
use Cpanel::Set                    ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 do_provider_dcv( $PROVIDER_OBJ, $VH_REPORT, $DCV_RESULT )

Runs the provider module’s C<get_vhost_dcv_errors()> method,
wrapping it in the appropriate logic to implement wildcard reduction.

Inputs are:

=over

=item * a L<Cpanel::SSL::Auto::Provider> instance

=item * a L<Cpanel::SSL::Auto::Run::Vhost> instance

=item * a L<Cpanel::SSL::Auto::Run::DCVResult> instance

=back

Updates $DCV_RESULT and logs to $PROVIDER_OBJ as appropriate.
Returns nothing.

=cut

sub do_provider_dcv ( $provider_obj, $vh_report, $run_dcv ) {    ## no critic qw(ManyArgs) - mis-parse

    # NB: This avoids reattempts at the same wildcard across
    # multiple vhosts because a previously-failed wildcard won’t
    # show up in the return from this function.
    my $domain_dcv_hr = $run_dcv->get_domain_success_methods();

    my @sorted_eligible_domains = $provider_obj->SORT_VHOST_FQDNS(
        $vh_report->get_username(),
        $vh_report->eligible_domains(),
    );

    # A lookup of reducer wildcards that passed local DCV.
    my %reducer_lookup = map { $_ => 1 } Cpanel::Set::difference(
        [ keys %$domain_dcv_hr ],
        \@sorted_eligible_domains,
    );

    my @max_reduced_dcv_ok_domains = _wildcard_reduce_and_filter_local_dcv(
        \@sorted_eligible_domains,
        [ keys %reducer_lookup ],
        $domain_dcv_hr,
    );

    if (%reducer_lookup) {

        # The reducer domains, in SORT_VHOST_FQDNS() order.
        my @sorted_reducers = Cpanel::Set::intersection(
            \@max_reduced_dcv_ok_domains,
            [ keys %reducer_lookup ],
        );

        $provider_obj->log( info => locale()->maketext( 'Trying [quant,_1,wildcard domain,wildcard domains] ([list_and,_2]) to maximize coverage …', 0 + @sorted_reducers, \@sorted_reducers ) );
    }

    my $provider_dcv = Cpanel::SSL::Auto::ProviderDCV->new(
        $provider_obj,
        $vh_report->get_username(),
        { %{$domain_dcv_hr}{@max_reduced_dcv_ok_domains} },
        \@max_reduced_dcv_ok_domains,
    );

    $provider_obj->get_vhost_dcv_errors($provider_dcv);

    my ( @failed_or_skipped_domains, @failed_reducers );

    for my $domain (@max_reduced_dcv_ok_domains) {
        next if $provider_dcv->get_domain_success_method($domain);

        push @failed_or_skipped_domains, $domain;

        if ( $provider_dcv->get_domain_failures($domain) ) {

            # Whether or not $domain is actually a reducer, this is fine.
            if ( delete $reducer_lookup{$domain} ) {
                push @failed_reducers, $domain;
            }
        }

        _copy_non_success_into_run_dcv( $domain, $provider_dcv, $run_dcv );
    }

    if (@failed_reducers) {
        $provider_obj->log( info => locale()->maketext( 'Retrying [asis,DCV] without the failed wildcard [numerate,_1,domain,domains] …', 0 + @failed_reducers ) );

        # Apply the reducers that didn’t just fail.
        # Note that %reducer_lookup at this point contains
        # exclusively DCV-passed domains.
        my @reduced_domains = _wildcard_reduce_and_filter_local_dcv(
            \@sorted_eligible_domains,
            [ keys %reducer_lookup ],
            $domain_dcv_hr,
        );

        # All eligible domains that didn’t just fail DCV, sorted.
        # No wildcard reductions are applied.
        my @sorted_retry_domains = Cpanel::Set::difference(
            \@reduced_domains,
            \@failed_or_skipped_domains,
        );

        my $provider_dcv = Cpanel::SSL::Auto::ProviderDCV->new(
            $provider_obj,
            $vh_report->get_username(),
            { %{$domain_dcv_hr}{@sorted_retry_domains} },
            \@sorted_retry_domains,
        );

        # Now retry, with any failed wildcards removed.
        $provider_obj->get_vhost_dcv_errors($provider_dcv);

        for my $domain (@sorted_retry_domains) {
            next if $provider_dcv->get_domain_success_method($domain);

            _copy_non_success_into_run_dcv( $domain, $provider_dcv, $run_dcv );
        }
    }

    return;
}

sub _wildcard_reduce_and_filter_local_dcv ( $sorted_eligible_ar, $wildcards_ar, $domain_dcv_hr ) {    ## no critic qw(ManyArgs) - mis-parse

    # First determine the domain reductions. For this use the full
    # list of eligible domains rather than just the ones that passed
    # local DCV; the reason for this is to secure domains that failed
    # local DCV but whose wildcard reducers passed.
    my @reduced_domains = Cpanel::SSL::Auto::Wildcard::reduce_domains_by_wildcards( $sorted_eligible_ar, @$wildcards_ar );

    # Don’t provider-DCV domains that already failed local DCV.
    @reduced_domains = grep { $domain_dcv_hr->{$_} } @reduced_domains;

    return @reduced_domains;
}

sub _copy_non_success_into_run_dcv ( $domain, $provider_dcv, $run_dcv ) {
    if ( my $failures_ar = $provider_dcv->get_domain_failures($domain) ) {

        # $main_dcv is a Cpanel::SSL::Auto::Run::DCVResult
        my $all_errs = join( ' ', @$failures_ar );

        $run_dcv->add_master( $domain, $all_errs );
    }
    else {

        # Happens if, e.g., the domain exceeds the provider’s
        # domains-per-certificate limit.
        $run_dcv->add_master( $domain, 'DCV omitted.' );
    }

    return;
}

1;
