package Whostmgr::API::1::Sitejet;

=encoding utf8

=head1 NAME

Whostmgr::API::1::Sitejet

=head1 DESCRIPTION

This module contains whmapi methods related to Sitejet.

=head1 FUNCTIONS

=cut

use cPstrict;
use Whostmgr::API::1::Utils ();
use Cpanel::Config::CpConfGuard;
use Cpanel::Exception();
use constant NEEDS_ROLE => {
    set_ecommerce => undef,
    get_ecommerce => undef,
};

=head2 set_ecommerce()

This function stores ecommerce data in cpanel.config

=head3 ARGUMENTS

=over

=item allowEcommerce - boolean
Required. The flag to turn on/off ecommerce in Sitejet CMS.

=item storeurl - string
Optional. The partner's store URL if provided will be used as a shop url
in Sitejet CMS.

=back

=cut

sub set_ecommerce {
    my ( $args, $metadata ) = @_;
    my $ecommerce_flag = Whostmgr::API::1::Utils::get_required_argument( $args, 'allowEcommerce' );
    my $storeurl       = $args->{storeurl} // '';

    die Cpanel::Exception::create( 'InvalidParameter', "Expected values are '0' or '1' for 'ecommerce' flag." ) if $ecommerce_flag !~ /^[01]$/;
    require Cpanel::Validate::URL;
    if ( $storeurl && !Cpanel::Validate::URL::is_valid_url($storeurl) ) {
        die Cpanel::Exception::create( 'InvalidParameter', "Please provide a valid URL." );
    }

    my %ecommerce_data = (
        'sitejet_ecommerce' => $ecommerce_flag,
        'sitejet_storeurl'  => $storeurl,
    );

    my $cpconf_guard = Cpanel::Config::CpConfGuard->new();
    while ( my ( $key, $value ) = each(%ecommerce_data) ) {
        $cpconf_guard->{'data'}->{$key} = $value;
    }
    $cpconf_guard->save();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

=head2 get_ecommerce()

This function fetches ecommerce data from cpanel.config

=head3 ARGUMENTS

none

=head3 RETURNS

A hash_ref with ecommerce enabled status and storeurl if exist.

Ex: {
        is_enabled => 1,
        storeurl   => 'https://partner.com/store',
    }


Note: is_enabled has three states.

* '1'  - Sitejet ecommerce is enabled.

* '0'  - Sitejet ecommerce is disabled.

* ''   - Sitejet ecommerce is not set.

=cut

sub get_ecommerce {
    my ( $args, $metadata ) = @_;
    require Cpanel::Config::LoadCpConf;
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return {
        is_enabled => $cpconf->{'sitejet_ecommerce'} // '',
        storeurl   => $cpconf->{'sitejet_storeurl'},
    };
}

sub APPLIST {
    return {
        set_ecommerce => [
            namespace => 'Sitejet',
            method    => 'set_ecommerce',
            argsmode  => 'strict',
        ],
        get_ecommerce => [
            namespace => 'Sitejet',
            method    => 'get_ecommerce',
            argsmode  => 'strict',
        ],
    };
}

1;
