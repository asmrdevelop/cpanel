package Cpanel::Validate::OpenIdConnect;

# cpanel - Cpanel/Validate/OpenIdConnect.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::Account           ();
use Cpanel::Exception                    ();
use Cpanel::Security::Authn::Config      ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Validate::AuthProvider       ();

use Try::Tiny;

#+---------------------------------------------------------------------
# This module provides parameter checking for the pluggable
# external authentication support modules.
#+---------------------------------------------------------------------

our $MAX_USER_INFO_ELEMENT_SIZE = 1024;    # May be a url

my $cpuser_key_regex;

sub check_hashref_or_die {
    my ( $hashref, $parameter_name ) = @_;

    $parameter_name = 'hashref' if !length $parameter_name;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $parameter_name ] )                                              if !$hashref;
    die Cpanel::Exception::create_raw( 'InvalidParameter', 'The parameter “[_1]” must be a [_2].', [ $parameter_name, 'hashref' ] ) if ref $hashref ne 'HASH';

    require Cpanel::Validate::LineTerminatorFree;
    foreach ( keys %{$hashref} ) {
        _check_user_info_element_size( $_, $parameter_name );
        Cpanel::Validate::FilesystemNodeName::validate_or_die($_);
        Cpanel::Validate::LineTerminatorFree::validate_or_die($_);
    }
    foreach ( values %{$hashref} ) {
        _check_user_info_element_size( $_, $parameter_name );

        next if !length $_;                                           # it's better to be specific.
        Cpanel::Validate::LineTerminatorFree::validate_or_die($_);    # May be a url
    }

    return 1;
}

sub _check_user_info_element_size {
    my ( $element, $parameter_name ) = @_;

    $element ||= q{};

    if ( length $element > $MAX_USER_INFO_ELEMENT_SIZE ) { die Cpanel::Exception::create( 'TooManyBytes', 'The [_1] element “[_2]” is larger than the allowed size of [_3].', [ $parameter_name, $element, $MAX_USER_INFO_ELEMENT_SIZE ] ); }

    return 1;
}

sub check_subject_unique_identifier_or_die {
    my ($subject_unique_identifier) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'subject_unique_identifier' ] ) if !$subject_unique_identifier;

    if ( ref $subject_unique_identifier ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The subject_unique_identifier must not be a reference.' );
    }

    require Cpanel::Validate::LineTerminatorFree;
    Cpanel::Validate::LineTerminatorFree::validate_or_die($subject_unique_identifier);
    return 1;
}

sub check_protocol_or_die {
    my ($protocol) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'protocol' ] ) if !length $protocol;

    if ( !$Cpanel::Security::Authn::Config::SUPPORTED_PROTOCOLS{$protocol} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The system does not support the “[_1]” authentication protocol.', [$protocol] );
    }

    # Sanity.
    Cpanel::Validate::FilesystemNodeName::validate_or_die($protocol);
    require Cpanel::Validate::LineTerminatorFree;
    Cpanel::Validate::LineTerminatorFree::validate_or_die($protocol);
    return 1;
}

sub check_user_exists_or_die {
    my ($user) = @_;

    if ( index( $user, '@' ) > -1 ) {
        require Cpanel::AcctUtils::Lookup::MailUser::Exists;
        if ( !Cpanel::AcctUtils::Lookup::MailUser::Exists::does_mail_user_exist($user) ) {
            die Cpanel::Exception::create( 'UserNotFound', [ name => $user ] );
        }
        return 1;
    }

    Cpanel::AcctUtils::Account::accountexists_or_die($user);

    return 1;
}

sub check_service_name_or_die {
    my ($service) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'service' ] ) if !length $service;

    if ( !grep { $service eq $_ } @Cpanel::Security::Authn::Config::ALLOWED_SERVICES ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The service “[_1]” does not support [asis,OpenID Connect] authentication.', [$service] );
    }

    # Sanity.
    Cpanel::Validate::FilesystemNodeName::validate_or_die($service);

    return 1;
}

sub check_and_normalize_service_or_die {
    my ($service_name_ref) = @_;

    # $Cpanel::App::appname may be 'whostmgr' or 'whostmgrd'
    # since we are normalizing here we need to append the 'd'
    # if it is missing since openid is for a service and we
    # may be calling this via an api
    $$service_name_ref .= 'd' if length $$service_name_ref && substr( $$service_name_ref, -1 ) ne 'd';

    Cpanel::Validate::OpenIdConnect::check_service_name_or_die($$service_name_ref);
    _lower_case($service_name_ref);

    return 1;
}

sub check_and_normalize_provider_or_die {
    my ($provider_name_ref) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($$provider_name_ref);
    _lower_case($provider_name_ref);

    return 1;
}

sub check_and_normalize_service_and_provider_or_die {
    my ( $service_name_ref, $provider_name_ref ) = @_;

    check_and_normalize_service_or_die($service_name_ref);
    check_and_normalize_provider_or_die($provider_name_ref);

    return 1;
}

sub _lower_case {
    my ($name_sr) = @_;

    $$name_sr =~ tr/A-Z/a-z/;

    return 1;
}

1;
