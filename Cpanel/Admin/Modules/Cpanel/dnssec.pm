
# cpanel - Cpanel/Admin/Modules/Cpanel/dnssec.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::dnssec;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::DNSSEC ();

# Error-handling for DNSSEC does not
# use the 'whitelist' pattern, and will require
# a larger refactor, so for now, we are just
# passing the exceptions in full.
use constant _actions__pass_exception => qw(
  ENABLE_DNSSEC
  DISABLE_DNSSEC
  FETCH_DS_RECORDS
  SET_NSEC3
  UNSET_NSEC3
  ACTIVATE_ZONE_KEY
  DEACTIVATE_ZONE_KEY
  ADD_ZONE_KEY
  REMOVE_ZONE_KEY
  IMPORT_ZONE_KEY
  EXPORT_ZONE_KEY
  EXPORT_ZONE_DNSKEY
);
use constant _actions => (
    _actions__pass_exception(),
);

sub ENABLE_DNSSEC {
    my ( $self, $nsec_config, $algo_config, $domains_ar ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');
    $self->_verify_domains($domains_ar);

    my $results_ar = Cpanel::DNSSEC::enable_dnssec_for_domains( $domains_ar, $nsec_config, $algo_config );

    return _convert_domain_rows_to_domains_grouped_by_success_fail( $results_ar, 'enabled' );

}

sub DISABLE_DNSSEC {
    my ( $self, $domains_ar ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');
    $self->_verify_domains($domains_ar);

    my %domains;
    my $results_ar = Cpanel::DNSSEC::disable_dnssec_for_domains($domains_ar);
    my $key        = 'disabled';
    my $ret        = _convert_domain_rows_to_domains_grouped_by_success_fail( $results_ar, $key );
    _make_success_key_true( $ret, $key );
    return $ret;
}

sub FETCH_DS_RECORDS {
    my ( $self, $domains_ar ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');

    $self->_verify_domains($domains_ar);

    my $results_ar = Cpanel::DNSSEC::fetch_ds_records_for_domains($domains_ar);
    return { map { $_->{'domain'} => $_->{'ds_records'} } @$results_ar };
}

sub SET_NSEC3 {
    my ( $self, $nsec_config, $domains_ar ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');

    $self->_verify_domains($domains_ar);

    my $key        = 'enabled';
    my $results_ar = Cpanel::DNSSEC::set_nsec3_for_domains( $domains_ar, $nsec_config );
    my $ret        = _convert_domain_rows_to_domains_grouped_by_success_fail( $results_ar, $key );
    _make_success_key_true( $ret, $key );
    return $ret;
}

sub UNSET_NSEC3 {
    my ( $self, $domains_ar ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');

    $self->_verify_domains($domains_ar);

    my $key        = 'disabled';
    my $results_ar = Cpanel::DNSSEC::unset_nsec3_for_domains($domains_ar);
    my $ret        = _convert_domain_rows_to_domains_grouped_by_success_fail( $results_ar, $key );
    _make_success_key_true( $ret, $key );
    return $ret;
}

sub ACTIVATE_ZONE_KEY {
    my ( $self, $domain, $key_id ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');

    $self->verify_that_cpuser_owns_domain($domain);

    return Cpanel::DNSSEC::activate_zone_key( $domain, $key_id );
}

sub DEACTIVATE_ZONE_KEY {
    my ( $self, $domain, $key_id ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');

    $self->verify_that_cpuser_owns_domain($domain);

    return Cpanel::DNSSEC::deactivate_zone_key( $domain, $key_id );
}

sub ADD_ZONE_KEY {
    my ( $self, $algo_config, $domain ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');

    $self->verify_that_cpuser_owns_domain($domain);

    return Cpanel::DNSSEC::add_zone_key( $domain, $algo_config );
}

sub REMOVE_ZONE_KEY {
    my ( $self, $domain, $key_id ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');
    $self->verify_that_cpuser_owns_domain($domain);

    return Cpanel::DNSSEC::remove_zone_key( $domain, $key_id );
}

sub IMPORT_ZONE_KEY {
    my ( $self, $domain, $key_data, $key_type ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');

    $self->verify_that_cpuser_owns_domain($domain);

    return Cpanel::DNSSEC::import_zone_key( $domain, $key_data, $key_type );
}

sub EXPORT_ZONE_KEY {
    my ( $self, $domain, $key_id ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');

    $self->verify_that_cpuser_owns_domain($domain);

    return Cpanel::DNSSEC::export_zone_key( $domain, $key_id );
}

sub EXPORT_ZONE_DNSKEY {
    my ( $self, $domain, $key_id ) = @_;
    $self->cpuser_has_feature_or_die('dnssec');

    $self->verify_that_cpuser_owns_domain($domain);

    return Cpanel::DNSSEC::export_zone_dnskey( $domain, $key_id );
}

sub _verify_domains {
    my ( $self, $domains_ar ) = @_;
    $self->verify_that_cpuser_owns_domain($_) for @$domains_ar;
    return 1;
}

sub _convert_domain_rows_to_domains_grouped_by_success_fail {
    my ( $results_ar, $success_key ) = @_;

    my %domains;

    foreach my $result_hr (@$results_ar) {
        my $domain = delete $result_hr->{'domain'};

        if ( $result_hr->{$success_key} ) {
            $domains{$success_key}{$domain} = $result_hr;
        }
        else {
            $domains{'failed'}{$domain} = $result_hr->{error};
        }
    }
    return \%domains;
}

sub _make_success_key_true {
    my ( $ret, $key ) = @_;

    # Some of these functions require the hashref to be a 1 instead of passing
    # along the underlying state.  This function transforms the result of
    # _convert_domain_rows_to_domains_grouped_by_success_fail for backwards compat.
    if ( $ret->{$key} ) {
        $ret->{$key}{$_} = 1 for ( keys %{ $ret->{$key} } );
    }
    return;
}

1;
