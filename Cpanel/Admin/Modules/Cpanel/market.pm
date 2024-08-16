package Cpanel::Admin::Modules::Cpanel::market;

# cpanel - Cpanel/Admin/Modules/Cpanel/market.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::market

=head1 SYNOPSIS

    Cpanel::AdminBin::Call::call( 'Cpanel', 'market',
        'CACHE_CPSTORE_PRODUCTS',
    );

    Cpanel::AdminBin::Call::call( 'Cpanel', 'market',
        'PROVIDER_DNS_DCV_SETUP',
        provider => 'cPStore',
        provider_args => { ... },
    );

    Cpanel::AdminBin::Call::call( 'Cpanel', 'market',
        'PROVIDER_DNS_DCV_TEARDOWN',
        provider => 'cPStore',
        provider_args => { ... },
    );

=head1 DESCRIPTION

This module houses admin logic related to the cPanel Market.

=cut

use parent qw( Cpanel::Admin::Base );

use Cpanel::Exception ();

sub _actions {
    return qw(
      PROVIDER_DNS_DCV_SETUP
      PROVIDER_DNS_DCV_TEARDOWN
      CACHE_CPSTORE_PRODUCTS
      SYNC_CONTACT_EMAIL_FROM_PROVIDER_IF_NEEDED
    );
}

=head1 FUNCTIONS

=head2 PROVIDER_DNS_DCV_SETUP( %OPTS )

This calls into the given provider’s logic for setting up the provider’s
DNS DCV—specifically the C<prepare_for_dns_dcv()> function.

%OPTS is:

=over

=item * C<provider> - string (e.g., C<cPStore>)

=item * C<provider_args> - hashref, the arguments to pass to the provider’s
C<prepare_for_dns_dcv()> function.

=back

=cut

sub PROVIDER_DNS_DCV_SETUP {
    my ( $self, @opts_kv ) = @_;

    return $self->_do_dns_dcv_operation(
        'prepare_for_dns_dcv',
        @opts_kv,
    );
}

=head2 PROVIDER_DNS_DCV_TEARDOWN( %OPTS )

The inverse of PROVIDER_DNS_DCV_SETUP(). %OPTS is the same, except that
C<provider_args> goes to the provider’s C<undo_dns_dcv_preparation()>
function.

=cut

sub PROVIDER_DNS_DCV_TEARDOWN {
    my ( $self, @opts_kv ) = @_;

    return $self->_do_dns_dcv_operation(
        'undo_dns_dcv_preparation',
        @opts_kv,
    );
}

sub _do_dns_dcv_operation {
    my ( $self, $function, %opts ) = @_;

    #NB: This module validates the inputs.
    require Cpanel::Market::SSL::DCV::Root;
    Cpanel::Market::SSL::DCV::Root->can($function)->(
        username => $self->get_caller_username(),
        %opts{ 'provider', 'provider_args' },
    );

    return;
}

=head2 CACHE_CPSTORE_PRODUCTS()

This is logic specific to the cPStore provider. It reads that
provider’s products (i.e., from the remote cPStore server), caches them,
and returns the cache.

=cut

#NB: Move this to its own admin module if we ever add more things
#to the cPStore catalog for sale within cPanel.
sub CACHE_CPSTORE_PRODUCTS {
    my ($self) = @_;

    require Cpanel::Market::Provider::cPStore::ProductsCache;
    return Cpanel::Market::Provider::cPStore::ProductsCache->load();
}

=head2 SYNC_CONTACT_EMAIL_FROM_PROVIDER_IF_NEEDED( $PROVIDER_NAME, $ACCESS_TOKEN )

This function exists to set a cPanel user’s contact email when there is
none defined on the local cPanel account but there I<is> one defined
in a Market provider.

=cut

sub SYNC_CONTACT_EMAIL_FROM_PROVIDER_IF_NEEDED ( $self, $provider_name, $access_token ) {
    $self->whitelist_exceptions(
        ['Cpanel::Exception'],
        sub {
            if ( !length $provider_name ) {

                die Cpanel::Exception::create_raw( 'MissingParameter', 'Need provider name' );
            }

            if ( !length $access_token ) {

                die Cpanel::Exception::create_raw( 'MissingParameter', 'Need access token' );
            }
        },
    );

    require Cpanel::Market;
    my $provider_ns = Cpanel::Market::get_and_load_module_for_provider($provider_name);

    {
        my $get_logged_in_users_email = $provider_ns->can('get_logged_in_users_email');
        last if !$get_logged_in_users_email;

        require Cpanel::Config::CpUserGuard;
        my $guard     = Cpanel::Config::CpUserGuard->new( $self->get_caller_username() );
        my $emails_ar = $guard->{'data'}->contact_emails_ar();

        last if @$emails_ar;

        my $contact_email_from_store = $get_logged_in_users_email->( access_token => $access_token );
        last if !length $contact_email_from_store;

        require Cpanel::Config::CpUser::Object::Update;
        Cpanel::Config::CpUser::Object::Update::set_contact_emails(
            $guard->{'data'},
            $emails_ar,
            [$contact_email_from_store],
        );

        # For historical reasons, we don’t notify the user that their
        # contact email addresses have changed. (Should we?)

        $guard->save();
    }

    return;
}

1;
