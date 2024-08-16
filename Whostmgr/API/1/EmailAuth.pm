package Whostmgr::API::1::EmailAuth;

# cpanel - Whostmgr/API/1/EmailAuth.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::EmailAuth - API methods related to email authentication and deliverability

=head1 DESCRIPTION

This module contains API methods related to authenticating email messages to ensure
that they are able to be delivered.

=head1 FUNCTIONS

=cut

#----------------------------------------------------------------------

use Cpanel::APICommon::Persona ();

use constant NEEDS_ROLE => 'MailSend';

#----------------------------------------------------------------------

=head2 validate_current_ptrs

Validates the PTR records for the provided C<domain>s.

This gives a list of hashes as output. Each hash is identical to
the values of the hash that
Cpanel::DnsUtils::MailRecords::validate_ptr_records_for_domains()
returns, with the addition of a C<domain> in each hash. The return
order matches the given C<domain> arguments.

=cut

sub validate_current_ptrs {

    my ( $args, $metadata ) = @_;

    require Whostmgr::API::1::Utils::Domains;
    my $domains = Whostmgr::API::1::Utils::Domains::validate_domains_or_die($args);

    require Cpanel::DnsUtils::MailRecords::Admin;
    my $mail_helo_ips_hr = Cpanel::DnsUtils::MailRecords::Admin::get_mail_helo_ips($domains);

    require Cpanel::DnsUtils::MailRecords;
    my $data_hr = Cpanel::DnsUtils::MailRecords::validate_ptr_records_for_domains($mail_helo_ips_hr);

    $data_hr->{$_}{'domain'} = $_ for keys %$data_hr;

    my $data_ar = [ map { $data_hr->{$_} } @$domains ];

    return _set_ok_result_and_payload( $data_ar, $metadata );
}

=head2 validate_current_spfs

Validates the SPF records for the provided domains

See Cpanel::DnsUtils::MailRecords::validate_spf_records_for_domains for output details

=cut

sub validate_current_spfs {
    my ( $args, $metadata ) = @_;
    require Cpanel::DnsUtils::MailRecords;
    return _do_callback_for_domains_mail_ips( $args, $metadata, \&Cpanel::DnsUtils::MailRecords::validate_spf_records_for_domains );
}

=head2 validate_current_dkims

Validates the DKIM records for the provided domains

See Cpanel::APICommon::EmailAuth::validate_current_dkims for output details

=cut

sub validate_current_dkims {
    my ( $args, $metadata ) = @_;
    require Cpanel::APICommon::EmailAuth;
    return _do_callback_for_domains( $args, $metadata, \&Cpanel::APICommon::EmailAuth::validate_current_dkims );
}

=head2 fetch_dkim_private_keys

Fetches the installed DKIM private keys in PEM format.

See Cpanel::DnsUtils::MailRecords::fetch_dkim_private_keys for output details

=cut

sub fetch_dkim_private_keys {
    my ( $args, $metadata ) = @_;
    require Cpanel::DnsUtils::MailRecords;
    return _do_callback_for_domains( $args, $metadata, \&Cpanel::DnsUtils::MailRecords::fetch_dkim_private_keys );
}

=head2 ensure_dkim_keys_exist

Generates DKIM keys for for a list of domains

See Cpanel::DnsUtils::MailRecords::ensure_dkim_keys_exist_for_user for output details

=cut

sub ensure_dkim_keys_exist ( $args, $metadata, $api_info_hr ) {
    require Cpanel::DnsUtils::MailRecords;
    return _do_callback_for_user_domains( $args, $metadata, $api_info_hr, \&Cpanel::DnsUtils::MailRecords::ensure_dkim_keys_exist_for_user );
}

=head2 enable_dkim

Enables DKIM on the specified domains.

Note that this will be done for the individual users who own the domains in sequence.

See Cpanel::DnsUtils::MailRecords::enable_dkim_for_user for output details

=cut

sub enable_dkim ( $args, $metadata, $api_info_hr ) {
    require Cpanel::DnsUtils::MailRecords;
    return _do_callback_for_user_domains( $args, $metadata, $api_info_hr, \&Cpanel::DnsUtils::MailRecords::enable_dkim_for_user );
}

=head2 disable_dkim

Disables DKIM on the specified domains.

Note that this will be done for the individual users who own the domains in sequence.

See Cpanel::DnsUtils::MailRecords::disable_dkim_for_user for output details

=cut

sub disable_dkim ( $args, $metadata, $api_info_hr ) {
    require Cpanel::DnsUtils::MailRecords;
    return _do_callback_for_user_domains( $args, $metadata, $api_info_hr, \&Cpanel::DnsUtils::MailRecords::disable_dkim_for_user );
}

=head2 install_spf_records

Installs SPF records into the DNS server for the given domains.

Note that this will be done for the individual users who own the domains in sequence.

See Cpanel::DnsUtils::MailRecords::install_spf_records_for_user for output details.

=cut

sub install_spf_records {
    my ( $args, $metadata ) = @_;
    require Cpanel::DnsUtils::MailRecords;

    # Trying to set SPF for a child account should *always* fail since
    # there is no local configuration that needs to happen. So pass
    # in an empty API-opts hashref, which will cause any child account
    # to fail.
    my $mock_api_opts_hr = {};

    return _do_callback_for_user_domains_values( $args, $metadata, $mock_api_opts_hr, "record", \&Cpanel::DnsUtils::MailRecords::install_spf_records_for_user );
}

=head2 install_dkim_private_keys

Installs DKIM keys into the local server for the given domains.

Note that this will be done for the individual users who own the domains in sequence.

See Cpanel::DnsUtils::MailRecords::install_dkim_private_keys_for_user for output details.

=cut

sub install_dkim_private_keys ( $args, $metadata, $api_info_hr ) {
    require Cpanel::DnsUtils::MailRecords;
    return _do_callback_for_user_domains_values( $args, $metadata, $api_info_hr, "key", \&Cpanel::DnsUtils::MailRecords::install_dkim_private_keys_for_user );
}

sub _do_callback_for_domains_mail_ips {
    my ( $args, $metadata, $callback ) = @_;

    require Whostmgr::API::1::Utils::Domains;
    my $domains = Whostmgr::API::1::Utils::Domains::validate_domains_or_die($args);

    require Cpanel::DIp::Mail;
    my $domain_to_ip = Cpanel::DIp::Mail::get_public_mail_ips_for_domains($domains);

    return _set_ok_result_and_payload( $callback->($domain_to_ip), $metadata );
}

sub _do_callback_for_domains {
    my ( $args, $metadata, $callback ) = @_;

    require Whostmgr::API::1::Utils::Domains;
    my $domains = Whostmgr::API::1::Utils::Domains::validate_domains_or_die($args);

    return _set_ok_result_and_payload( $callback->($domains), $metadata );
}

sub _do_callback_for_user_domains_values ( $args, $metadata, $api_info_hr, $value, $callback ) {    ## no critic qw(ManyArgs) - mis-parse

    require Whostmgr::API::1::Utils::Domains;
    my $domains_to_values = Whostmgr::API::1::Utils::Domains::validate_domain_value_pairs_or_die( $args, $value );

    my $user_to_domains = _map_domains_to_users( [ keys %$domains_to_values ] );

    my $err_obj = _get_child_account_error( $metadata, $api_info_hr, $user_to_domains );
    return $err_obj if $err_obj;

    my @returns;
    foreach my $user ( keys %$user_to_domains ) {
        my $user_domains            = $user_to_domains->{$user};
        my $user_domains_to_records = {};
        @{$user_domains_to_records}{@$user_domains} = @{$domains_to_values}{@$user_domains};
        push @returns, @{ $callback->( $user, $user_domains_to_records ) };
    }

    return _set_ok_result_and_payload( \@returns, $metadata );
}

sub _get_child_account_error ( $metadata, $api_info_hr, $user_to_domains ) {    ## no critic qw(ManyArgs) - mis-parse
    my $err_obj;

    for my $username ( keys %$user_to_domains ) {
        ( my $str, $err_obj ) = Cpanel::APICommon::Persona::get_whm_expect_parent_error_pieces( $api_info_hr->{'persona'}, $username );

        if ($str) {
            $metadata->set_not_ok($str);
        }
    }

    return $err_obj;
}

sub _do_callback_for_user_domains ( $args, $metadata, $api_info_hr, $callback ) {    ## no critic qw(ManyArgs) - mis-parse

    require Whostmgr::API::1::Utils::Domains;
    my $domains = Whostmgr::API::1::Utils::Domains::validate_domains_or_die($args);

    my $user_to_domains = _map_domains_to_users($domains);

    my $err_obj = _get_child_account_error( $metadata, $api_info_hr, $user_to_domains );
    return $err_obj if $err_obj;

    my @returns;
    foreach my $user ( keys %$user_to_domains ) {
        push @returns, @{ $callback->( $user, $user_to_domains->{$user} ) };
    }

    return _set_ok_result_and_payload( \@returns, $metadata );
}

sub _map_domains_to_users {

    my ($domains) = @_;

    my %user_to_domains;

    my $userdomains;

    require Cpanel::Sys::Hostname;
    my $hostname = Cpanel::Sys::Hostname::gethostname();

    my @invalid;
    foreach my $domain (@$domains) {

        if ( $domain eq $hostname ) {
            $user_to_domains{root} = [$hostname];
        }
        else {

            $userdomains ||= _get_userdomains();
            my $user = $userdomains->{$domain};

            if ($user) {
                $user_to_domains{$user} ||= [];
                push @{ $user_to_domains{$user} }, $domain;
            }
            else {
                push @invalid, $domain;
            }
        }

    }

    if (@invalid) {
        require Cpanel::Exception;
        die Cpanel::Exception->create( "No users correspond to the [numerate,_1,domain,domains] [list_and_quoted,_2].", [ scalar @invalid, @invalid ] );
    }

    return \%user_to_domains;
}

# Exposed for testing
our $_userdomains_ref;

sub _get_userdomains {
    require Cpanel::Config::LoadUserDomains;
    $_userdomains_ref ||= Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    return $_userdomains_ref;
}

sub _set_ok_result_and_payload {

    my ( $records, $metadata ) = @_;

    $metadata->{result} = 1;
    $metadata->{reason} = 'OK';

    return { payload => $records };
}

1;
