package Whostmgr::API::1::AdvConfig;

# cpanel - Whostmgr/API/1/AdvConfig.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AdvConfig                    ();
use Whostmgr::API::1::Utils              ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Validate::LineTerminatorFree ();
use Cpanel::Exception                    ();

use Try::Tiny;

use constant NEEDS_ROLE => {
    set_service_config_key => undef,
    get_service_config_key => undef,
    get_service_config     => undef,
};

sub set_service_config_key {
    my ( $args, $metadata ) = @_;

    my $service = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'service' );
    my $key     = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'key' );
    my $value   = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'value' );
    Cpanel::Validate::FilesystemNodeName::validate_or_die($service);
    Cpanel::Validate::LineTerminatorFree::validate_or_die($key);
    Cpanel::Validate::LineTerminatorFree::validate_or_die($value);

    # Cipher lists value cannot have spaces
    die Cpanel::Exception::create( 'InvalidParameter', 'The service “[_2]” does not allow spaces in “[_1]” for the service. Cipher list: “[_3]”.', [ $key, $service, $value ] )
      if $service eq 'dovecot'
      and $key eq 'ssl_cipher_list'
      and $value =~ / /;

    # Cpanel::LoadModule::load_perl_module may throw an exception if "Cpanel::AdvConfig::$service" isn't a module.
    try {
        @{$metadata}{qw(result reason)} = Cpanel::AdvConfig::set_app_conf_key_value( $service, $key, $value );
    }
    catch {
        my $ex = $_;

        # If missing, transmogrify this module execption into a parameter exception, but re-throw other exceptions as-is:
        die Cpanel::Exception::create( 'InvalidParameter', 'The service “[_1]” is not valid.', [$service] ) if try { $ex->isa('Cpanel::Exception::ModuleLoadError') && $ex->is_not_found() };
        die $ex;
    };

    return;
}

sub get_service_config_key {
    my ( $args, $metadata ) = @_;
    my $service = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'service' );
    my $key     = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'key' );
    Cpanel::Validate::FilesystemNodeName::validate_or_die($service);
    Cpanel::Validate::LineTerminatorFree::validate_or_die($key);
    my $conf = Cpanel::AdvConfig::load_app_conf($service);
    die "There is no key “$key” for the “$service”" if !exists $conf->{$key};
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { $key => $conf->{$key} };
}

sub get_service_config {
    my ( $args, $metadata ) = @_;
    my $service = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'service' );
    Cpanel::Validate::FilesystemNodeName::validate_or_die($service);
    my $conf = Cpanel::AdvConfig::load_app_conf($service);
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return $conf;
}

1;
