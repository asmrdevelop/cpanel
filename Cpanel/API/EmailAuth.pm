package Cpanel::API::EmailAuth;

# cpanel - Cpanel/API/EmailAuth.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AdminBin::Call            ();
use Cpanel::APICommon::EmailAuth      ();
use Cpanel::Args::CpanelUser::Domains ();

my @_adminbin_namespace = ( 'Cpanel', 'emailauth' );

=encoding utf-8

=head1 NAME

Cpanel::API::EmailAuth - API Functions related to EmailAuth

=head1 SYNOPSIS

    use Cpanel::API ();


=head1 DESCRIPTION

    API Functions related to EmailAuth

=head2 install_spf_records

Installs SPF records into the dns server for the given domains.

see bin/admin/Cpanel/emailauth for output

=cut

sub install_spf_records {
    my ( $args, $result ) = @_;
    return _do_admin_api_with_args(
        'INSTALL_SPF_RECORDS',
        [ Cpanel::Args::CpanelUser::Domains::validate_domain_value_pairs_or_die( $args, 'record' ) ],
        $result
    );
}

=head2 install_dkim_private_keys

Saves DKIM private keys, generates DKIM public keys from the private
keys.  This function does not update the DNS records.   If this server has dns authority you must call enable_dkim
to update the DNS records or the keys will be out of sync with DNS.  It is suggested to use a Batch UAPI call to
install_dkim_private_keys and enable_dkim when the server has_local_authority

see bin/admin/Cpanel/emailauth for output

=cut

sub install_dkim_private_keys {
    my ( $args, $result ) = @_;
    return _do_admin_api_with_args(
        'INSTALL_DKIM_PRIVATE_KEYS',
        [ Cpanel::Args::CpanelUser::Domains::validate_domain_value_pairs_or_die( $args, 'key' ) ],
        $result
    );
}

=head2 fetch_dkim_private_keys

Fetches the installed DKIM private keys in PEM format.

see bin/admin/Cpanel/emailauth for output

=cut

sub fetch_dkim_private_keys {
    my ( $args, $result ) = @_;
    return _call_emailauth_api(
        'FETCH_DKIM_PRIVATE_KEYS',
        $args,
        $result
    );
}

=head2 ensure_dkim_keys_exist

Generates DKIM keys for the given domains
as needed.  If the existing keys already
meet the server's security standards, they
are not replaced

see bin/admin/Cpanel/emailauth for output

=cut

sub ensure_dkim_keys_exist {
    my ( $args, $result ) = @_;
    return _call_emailauth_api(
        'ENSURE_DKIM_KEYS_EXIST',
        $args,
        $result
    );
}

=head2 enable_dkim

Installs DKIM records into the dns server for the given domains
as needed.

see bin/admin/Cpanel/emailauth for output

=cut

sub enable_dkim {
    my ( $args, $result ) = @_;
    return _call_emailauth_api(
        'ENABLE_DKIM',
        $args,
        $result
    );
}

=head2 disable_dkim

Removes DKIM records from the dns server for the given domains
as needed.

see bin/admin/Cpanel/emailauth for output

=cut

sub disable_dkim {
    my ( $args, $result ) = @_;
    return _call_emailauth_api(
        'DISABLE_DKIM',
        $args,
        $result
    );
}

=head2 validate_current_ptrs

Validates the PTR records from the dns server for the given domains
as needed. Also validates that the PTRs match the given domains’
SMTP HELO domain.

see Cpanel::DnsUtils::ReverseDns for output

=cut

sub validate_current_ptrs {

    my ( $args, $result ) = @_;

    my $domains = Cpanel::Args::CpanelUser::Domains::validate_domains_or_die($args);

    my $mail_helo_ips_hr = _get_domain_mail_helo_ips($domains);

    require Cpanel::DnsUtils::MailRecords;
    my $data_hr = Cpanel::DnsUtils::MailRecords::validate_ptr_records_for_domains($mail_helo_ips_hr);

    $data_hr->{$_}{'domain'} = $_ for keys %$data_hr;

    $result->data( [ map { $data_hr->{$_} } @$domains ] );

    return 1;
}

=head2 validate_current_spfs

Validates the SPF records from the dns server for the given domains
as needed.

see Cpanel::DnsUtils::MailRecords for output

=cut

sub validate_current_spfs {

    my ( $args, $result ) = @_;

    my $domains = Cpanel::Args::CpanelUser::Domains::validate_domains_or_die($args);

    my $domain_to_ip = _get_domain_mail_ips($domains);

    require Cpanel::DnsUtils::MailRecords;
    $result->data( Cpanel::DnsUtils::MailRecords::validate_spf_records_for_domains($domain_to_ip) );

    return 1;
}

=head2 validate_current_dkims

Validates the DKIM records from the dns server for the given domains
as needed.

See L<Cpanel::APICommon::EmailAuth> for documentation.

=cut

sub validate_current_dkims {

    my ( $args, $result ) = @_;

    my $domains = Cpanel::Args::CpanelUser::Domains::validate_domains_or_die($args);

    my $warn_cr = $SIG{'__WARN__'};
    local $SIG{'__WARN__'} = sub {
        my $msg = shift;
        $result->raw_warning($msg);
        $warn_cr->($msg) if $warn_cr;    # prevent die if __WARN__ was already undef
    };

    $result->data( Cpanel::APICommon::EmailAuth::validate_current_dkims($domains) );

    return 1;
}

sub _call_emailauth_api {
    my ( $api_name, $args, $result ) = @_;
    return _do_admin_api_with_args(
        $api_name,
        [ Cpanel::Args::CpanelUser::Domains::validate_domains_or_die($args) ],
        $result
    );
}

sub _do_admin_api_with_args {
    my ( $api_name, $adminbin_args_ar, $result ) = @_;
    $result->data(
        Cpanel::AdminBin::Call::call(
            @_adminbin_namespace,
            $api_name,
            @$adminbin_args_ar,
        )
    );

    return 1;
}

my %_domain_mail_helo_ip;

# mocked in tests
sub _get_domain_mail_helo_ips {
    my ($domains) = @_;

    my $cache_key = join( '_', sort @$domains );
    require Cpanel::AdminBin::Call;
    return $_domain_mail_helo_ip{$cache_key} ||= Cpanel::AdminBin::Call::call( 'Cpanel', 'emailauth', 'GET_MAIL_HELO_IPS', $domains );
}

# In batch mode we may call _get_domain_mail_ips
# multiple times.  With a cache we can avoid
# the multiple adminbin calls
sub _get_domain_mail_ips {
    my ($domains) = @_;

    my $lookup_hr = _get_domain_mail_helo_ips($domains);

    return { map { ( $_ => $lookup_hr->{$_}{'public_ip'} ) } @$domains };
}

our %API = (
    _needs_role    => "MailSend",
    _needs_feature => "emailauth"
);

1;
