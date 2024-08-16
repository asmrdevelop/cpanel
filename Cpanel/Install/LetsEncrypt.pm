package Cpanel::Install::LetsEncrypt;

# cpanel - Cpanel/Install/LetsEncrypt.pm           Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS                       ();
use Cpanel::LoadModule::Custom       ();
use Cpanel::Plugins                  ();
use Cpanel::Server::Type             ();
use Cpanel::SSL::Auto::Loader        ();
use Whostmgr::API::1::Utils::Execute ();

use Cpanel::Imports;
use Try::Tiny;

use constant _PROVIDER_NAME => 'LetsEncrypt';
use constant _PLUGIN_NAME   => 'cpanel-letsencrypt-v2';

=encoding utf-8

=head1 NAME

Cpanel::Install::LetsEncrypt

=head1 SYNOPSIS

    use Cpanel::Install::LetsEncrypt ();

    $bool = Cpanel::Install::LetsEncrypt::is_supported();
    $bool = Cpanel::Install::LetsEncrypt::is_installed();
    $ok = Cpanel::Install::LetsEncrypt::install();
    $ok = Cpanel::Install::LetsEncrypt::activate();
    $ok = Cpanel::Install::LetsEncrypt::install_and_activate();

=head1 DESCRIPTION

Provides the installation and activation (account registration and enabling the
AutoSSL provider) of the L<Let’s Encrypt|https://letsencrypt.org> plugin.

=head1 FUNCTIONS

=head2 is_supported

Returns true if the cpanel-letsencrypt-v2 plugin is supported on this system.

=cut

sub is_supported {
    return Cpanel::OS::supports_letsencrypt_v2();
}

=head2 is_installed

Returns true if the cpanel-letsencrypt-v2 plugin is installed.

=cut

sub is_installed {
    return Cpanel::Plugins::is_plugin_installed( _PLUGIN_NAME() );
}

=head2 activate

Returns true if a L<Let’s Encrypt|https://letsencrypt.org> account registration
is successfully obtained and the AutoSSL provider is successfully enabled.

This will log a warning and return false if:

=over

=item * the plugin is not installed.

=item * a problem is encountered while obtaining the current Terms of Service

=item * a problem is encountered while enabling the AutoSSL provider

=back

=cut

sub activate {

    if ( !is_installed() ) {
        logger->warn( locale->maketext( 'The system is unable to activate the “[_1]” provider because the “[_2]” plugin is not installed.', _PROVIDER_NAME(), _PLUGIN_NAME() ) );
        return 0;
    }

    # DNSONLY does not have cPanel accounts, so we can quietly skip activating the AutoSSL provider.
    return 1 if Cpanel::Server::Type::is_dnsonly();

    my $tos = try {
        my $ns    = Cpanel::SSL::Auto::Loader::get_and_load( _PROVIDER_NAME() );
        my %props = $ns->PROPERTIES();
        $props{terms_of_service};
    }
    catch {
        logger->warn( locale->maketext( 'The system encountered the following error while activating the “[_1]” provider: [_2]', _PROVIDER_NAME(), $_ ) );
        0;
    };
    return 0 unless $tos;

    my $ok = try {
        my $result = Whostmgr::API::1::Utils::Execute::execute_or_die(
            'SSL' => 'set_autossl_provider',
            {
                'provider'                    => _PROVIDER_NAME(),
                'x_terms_of_service_accepted' => $tos,
            },
        );
        1;
    }
    catch {
        logger->warn( locale->maketext( 'The system encountered the following error while activating the “[_1]” provider: [_2]', _PROVIDER_NAME(), $_ ) );
        0;
    };
    return $ok;
}

=head2 install

Returns true if the cpanel-letsencrypt-v2 plugin is successfully installed and an ACME account is created.

This will log a warning and return false if:

=over

=item * the plugin is not successfully installed.

=item * a problem is encountered while creating a new ACME account.

=back

=cut

sub install {
    if ( !is_supported() ) {
        logger->warn( locale->maketext( 'The system is unable to install the “[_1]” plugin because it is not supported on this system.', _PLUGIN_NAME() ) );
        return 0;
    }
    my $ok = try {
        Cpanel::Plugins::install_or_upgrade_plugins( _PLUGIN_NAME() );
        Cpanel::LoadModule::Custom::load_perl_module('Cpanel::SSL::Auto::Provider::LetsEncrypt');
        Cpanel::SSL::Auto::Provider::LetsEncrypt->new()->EXPORT_PROPERTIES( terms_of_service_accepted => 1 );    # PPI USE OK
        1;
    }
    catch {
        logger->warn( locale->maketext( 'The system encountered the following error while installing the “[_1]” plugin: [_2]', _PLUGIN_NAME(), $_ ) );
        0;
    };
    return $ok;
}

=head2 install_and_activate

A convenience function that wraps C<install()> and C<activate()> and
returns true if both are successful.

=cut

sub install_and_activate {
    if ( install() && activate() ) {
        return 1;
    }
    return 0;
}

1;
