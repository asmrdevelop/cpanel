#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/emailauth.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::emailauth;

=encoding utf-8

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Exception             ();
use Cpanel::BinCheck              ();
use Cpanel::DnsUtils::MailRecords ();
use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::emailauth - An admin module that handles additional email authentication tasks such as DKIM & SPF

=head1 SYNOPSIS

    use Cpanel::AdminBin::Call ();

    Cpanel::AdminBin::Call::call( 'Cpanel', 'emailauth', 'ENABLE_DKIM', {'domain' => $domain} );

=head1 DESCRIPTION

AdminBin scripts are compiled into binaries which are called by a user from user-space to perform privileged actions
for that user. This AdminBin script performs additional SSL actions for a user.

NOTE: Please put all new email authentication related AdminBin functions in this module.

=cut

use constant _actions => (
    'INSTALL_SPF_RECORDS',
    'INSTALL_DKIM_PRIVATE_KEYS',
    'ENSURE_DKIM_KEYS_EXIST',
    'ENABLE_DKIM',
    'DISABLE_DKIM',
    'FETCH_DKIM_PRIVATE_KEYS',
    'GET_MAIL_HELO_IPS',
    'UPDATE_DKIM_VALIDITY_CACHE_FOR_DOMAINS',
);

#----------------------------------------------------------------------

=head2 INSTALL_SPF_RECORDS

This method is a thin wrapper around Cpanel::DnsUtils::MailRecords::install_spf_records_for_user
that passes the adminbin caller as the user parameter.

See Cpanel::DnsUtils::MailRecords::install_spf_records_for_user for details

=cut

sub INSTALL_SPF_RECORDS {
    my ( $self, $domain_to_rec_map ) = @_;

    $self->cpuser_has_feature_or_die('emailauth');
    die Cpanel::Exception::create( 'MissingParameter', 'A hashref of domains and records' ) if !$domain_to_rec_map;
    die Cpanel::Exception::create( 'InvalidParameter', 'A hashref of domains and records' ) if !ref $domain_to_rec_map || ref $domain_to_rec_map ne 'HASH' || !scalar keys %$domain_to_rec_map;
    die Cpanel::Exception::create( 'InvalidParameter', 'Empty records are not permitted' )  if grep { !length } values %$domain_to_rec_map;

    $self->_verify_domains( [ keys %$domain_to_rec_map ] );

    return Cpanel::DnsUtils::MailRecords::install_spf_records_for_user( $self->get_caller_username(), $domain_to_rec_map );
}

=head2 INSTALL_DKIM_PRIVATE_KEYS

This method is a thin wrapper around Cpanel::DnsUtils::MailRecords::install_dkim_private_keys_for_user
that passes the adminbin caller as the user parameter.

See Cpanel::DnsUtils::MailRecords::install_dkim_private_keys_for_user for details

=cut

sub INSTALL_DKIM_PRIVATE_KEYS {
    my ( $self, $domain_to_key_map ) = @_;
    $self->cpuser_has_feature_or_die('emailauth');

    die Cpanel::Exception::create( 'MissingParameter', 'A hashref of domains and keys' ) if !$domain_to_key_map;
    die Cpanel::Exception::create( 'InvalidParameter', 'A hashref of domains and keys' ) if !ref $domain_to_key_map || ref $domain_to_key_map ne 'HASH' || !scalar keys %$domain_to_key_map;
    die Cpanel::Exception::create( 'InvalidParameter', 'Empty keys are not permitted' )  if grep { !length } values %$domain_to_key_map;

    $self->_verify_domains( [ keys %$domain_to_key_map ] );

    return Cpanel::DnsUtils::MailRecords::install_dkim_private_keys_for_user( $self->get_caller_username(), $domain_to_key_map );
}

=head2 ENSURE_DKIM_KEYS_EXIST

This method is a thin wrapper around Cpanel::DnsUtils::MailRecords::ensure_dkim_keys_exist_for_user
that passes the adminbin caller as the user parameter.

See Cpanel::DnsUtils::MailRecords::ensure_dkim_keys_exist_for_user for details

=cut

sub ENSURE_DKIM_KEYS_EXIST {
    my ( $self, $domains_ar ) = @_;
    $self->_validate_feature_and_arrayref_of_domains($domains_ar);
    return Cpanel::DnsUtils::MailRecords::ensure_dkim_keys_exist_for_user( $self->get_caller_username(), $domains_ar );
}

=head2 ENABLE_DKIM

This method is a thin wrapper around Cpanel::DnsUtils::MailRecords::enable_dkim_for_user
that passes the adminbin caller as the user parameter.

See Cpanel::DnsUtils::MailRecords::enable_dkim_for_user for details

=cut

sub ENABLE_DKIM {
    my ( $self, $domains_ar ) = @_;
    $self->_validate_feature_and_arrayref_of_domains($domains_ar);
    return Cpanel::DnsUtils::MailRecords::enable_dkim_for_user( $self->get_caller_username(), $domains_ar );
}

=head2 DISABLE_DKIM

This method is a thin wrapper around Cpanel::DnsUtils::MailRecords::disable_dkim_for_user
that passes the adminbin caller as the user parameter.

See Cpanel::DnsUtils::MailRecords::disable_dkim_for_user for details

=cut

sub DISABLE_DKIM {
    my ( $self, $domains_ar ) = @_;
    $self->_validate_feature_and_arrayref_of_domains($domains_ar);
    return Cpanel::DnsUtils::MailRecords::disable_dkim_for_user( $self->get_caller_username(), $domains_ar );
}

=head2 FETCH_DKIM_PRIVATE_KEYS

This method is a thin wrapper around Cpanel::DnsUtils::MailRecords::fetch_dkim_private_keys.

See Cpanel::DnsUtils::MailRecords::fetch_dkim_private_keys for details

=cut

sub FETCH_DKIM_PRIVATE_KEYS {
    my ( $self, $domains_ar ) = @_;
    $self->_validate_feature_and_arrayref_of_domains($domains_ar);
    return Cpanel::DnsUtils::MailRecords::fetch_dkim_private_keys($domains_ar);
}

=head2 GET_MAIL_HELO_IPS

This method is a thin wrapper around Cpanel::DnsUtils::MailRecords::Admin::get_mail_helo_ips().

See that function for details.

=cut

sub GET_MAIL_HELO_IPS {
    my ( $self, $domains_ar ) = @_;
    $self->_validate_feature_and_arrayref_of_domains($domains_ar);
    require Cpanel::DnsUtils::MailRecords::Admin;
    return Cpanel::DnsUtils::MailRecords::Admin::get_mail_helo_ips($domains_ar);
}

#----------------------------------------------------------------------

=head2 $hr = UPDATE_DKIM_VALIDITY_CACHE_FOR_DOMAINS( \@DOMAINS )

A wrapper around L<Cpanel::DKIM::ValidityCache::Sync>’s C<sync_domains()>
function. Inputs and outputs are identical; this just adds access
verification for the given @DOMAINS.

=cut

sub UPDATE_DKIM_VALIDITY_CACHE_FOR_DOMAINS {
    my ( $self, $domains_ar ) = @_;

    $self->_validate_feature_and_arrayref_of_domains($domains_ar);

    require Cpanel::DKIM::ValidityCache::Sync;
    return Cpanel::DKIM::ValidityCache::Sync::sync_domains($domains_ar);
}

#----------------------------------------------------------------------

sub _validate_feature_and_arrayref_of_domains {
    my ( $self, $domains_ar ) = @_;
    $self->cpuser_has_feature_or_die('emailauth');

    die Cpanel::Exception::create( 'MissingParameter', 'An arrayref of domains' ) if !$domains_ar;
    die Cpanel::Exception::create( 'InvalidParameter', 'An arrayref of domains' ) if !ref $domains_ar || ref $domains_ar ne 'ARRAY' || !@$domains_ar;
    $self->_verify_domains($domains_ar);

    return 1;
}

sub _verify_domains {
    my ( $self, $domains_ar ) = @_;
    $self->verify_that_cpuser_owns_domain($_) for @$domains_ar;
    return 1;
}

1;
