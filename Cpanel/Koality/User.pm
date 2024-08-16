package Cpanel::Koality::User;

# cpanel - Cpanel/Koality/User.pm                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;
extends 'Cpanel::Koality::Base';

use Cpanel::Imports;
use Cpanel::Plugins::RestApiClient        ();
use Cpanel::Koality::Validate             ();
use Cpanel::PwCache                       ();
use Cpanel::Transaction::File::JSON       ();
use Cpanel::Transaction::File::JSONReader ();

=head1 MODULE

C<Cpanel::Koality::User>

=head1 DESCRIPTION

C<Cpanel::Koality::User> is a class that provides methods to manage a Koality user and retrieve account information.

=head1 ATTRIBUTES

=cut

has '_conf_dir' => (
    is   => 'rw',
    lazy => 1,
    isa  => sub {
        require Cpanel::Validate::FilesystemPath;
        Cpanel::Validate::FilesystemPath::validate_or_die( $_[0] );
    },
    builder => 1
);

has '_conf_file' => (
    is   => 'rw',
    lazy => 1,
    isa  => sub {
        require Cpanel::Validate::FilesystemPath;
        Cpanel::Validate::FilesystemPath::validate_or_die( $_[0] );
    },
    builder => 1
);

=head2 user_config - Hashref

Hashref containing the user configuration read from disk. This configuration is located at C<~/.koality/config>

=cut

has 'user_config' => (
    is  => 'rw',
    isa => sub {
        die 'Not a Hashref.' if ref( $_[0] ) ne 'HASH';
    },
    builder => 1
);

=head2 koality_username - string

The username of the Koality account associated with the cPanel account. This must be an email address.

=cut

has 'koality_username' => (
    is   => 'rw',
    lazy => 1,
    isa  => sub {
        require Cpanel::Validate::EmailRFC;
        die locale()->maketext('Invalid email address.') if !Cpanel::Validate::EmailRFC::is_valid( $_[0] );
    },
    default => sub ($self) { $self->user_config->{koality_username} // undef }
);

=head2 app_token - string

The long-lived app token of the Koality account.
This is provided by the app360 backend upon user creation and is used to generate an auth token.

=cut

has 'app_token' => (
    is      => 'rw',
    isa     => \&Cpanel::Koality::Validate::valid_token,
    lazy    => 1,
    default => sub ($self) { $self->user_config->{app_token} // undef }
);

=head2 auth_token - string

The authentication token of the Koality account.
This is retrieved from the Koality authentication endpoint and is used to generate refresh/session tokens.

=cut

has 'auth_token' => (
    is      => 'rw',
    isa     => \&Cpanel::Koality::Validate::valid_token,
    lazy    => 1,
    default => sub ($self) { $self->user_config->{auth_token} // undef }
);

=head2 session_token - string

The token for the authenticated Koality session.

=cut

has 'session_token' => (
    is      => 'rw',
    isa     => \&Cpanel::Koality::Validate::valid_token,
    lazy    => 1,
    default => sub ($self) { $self->user_config->{session_token} // undef }
);

=head2 refresh_token - string

The refresh token for the authenticated Koality session.

=cut

has 'refresh_token' => (
    is      => 'rw',
    isa     => \&Cpanel::Koality::Validate::valid_token,
    lazy    => 1,
    default => sub ($self) { $self->user_config->{refresh_token} // undef }
);

=head2 cluster_endpoint - string

The cluster URL designated for the Koality user retrieved upon authenticating.

=cut

has 'cluster_endpoint' => (
    is      => 'rw',
    isa     => \&Cpanel::Koality::Validate::valid_api_url,
    lazy    => 1,
    default => sub ($self) { $self->user_config->{cluster_endpoint} // undef }
);

=head2 user_id - integer

The Koality user ID number.

=cut

has 'user_id' => (
    is  => 'rw',
    isa => sub {
        require Cpanel::Validate::Integer;
        Cpanel::Validate::Integer::unsigned( $_[0] );
    },
    lazy    => 1,
    default => sub ($self) { $self->user_config->{user_id} // '0' }
);

=head2 user_id - integer

The Koality master user ID number.

=cut

has 'master_user_id' => (
    is  => 'rw',
    isa => sub {
        require Cpanel::Validate::Integer;
        Cpanel::Validate::Integer::unsigned( $_[0] );
    },
    lazy    => 1,
    default => sub ($self) { $self->user_config->{master_user_id} // '0' }
);

=head2 enabled - boolean

Whether the Koality user is enabled.

=cut

has 'enabled' => (
    is  => 'rw',
    isa => sub {
        require Cpanel::Validate::Boolean;
        Cpanel::Validate::Boolean::validate_or_die( $_[0] );
    },
    default => 0,
);

has 'uuid' => ( is => 'rw', lazy => 1, default => sub ($self) { $self->user_config->{uuid} // undef } );

sub _build__conf_dir ($self) {
    my $home = Cpanel::PwCache::gethomedir( $self->cpanel_username );
    die locale()->maketext( "No home directory found for [_1]. Make sure they are a cPanel user.", $self->cpanel_username ) if !$home;
    return "$home/.koality";
}

sub _build__conf_file ($self) {
    my $dir       = $self->_conf_dir;
    my $conf_file = "$dir/config";
    return $conf_file;
}

sub _build_user_config ($self) {
    $self->_ensure_conf_dir();
    my $tx     = Cpanel::Transaction::File::JSONReader->new( path => $self->_conf_file );
    my $config = $tx->get_data();
    return ( $config && ref $config eq 'HASH' ) ? $config : {};
}

sub _build_api ($self) {
    require Cpanel::Koality::ApiClient;
    my $api = Cpanel::Koality::ApiClient->new( cpanel_username => $self->cpanel_username );
    $api->auth_token( $self->session_token );
    $api->base_url( $self->cluster_endpoint );
    return $api;
}

=head1 METHODS

=head2 get_subscription()

Retrieve subscription level.

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

Hashref containing Koality account subscription/billing information.

=over

=item subscription_plan - string

The name of the subscription plan.

=item status - string

The current status of the subscription.

=item price_per_project - integer

The price in euros per project for the active subscription.

=item trial_end - integer

TODO

=item tax_rate - integer

The sales tax (VAT) rate charged to the subscriber for the purchase of the service. The current rate in Germany is 19%.

=item plans - Hashref

=over

=item plan - string

The name of the subscription plan.

=item subPlan - string

The name of the subscription plan, AGAIN.

=item trial - Boolean

Whether the plan is offered on a trial basis.

=item credit_card

TODO

=item invoice

TODO

=back

=item systems - Hashref

=over

=item systems_used - integer

The number of systems currently in use.

=item systems_free - integer

The number of systems currently available to create.

=item systems_all - integer

The total number of systems available on the account's subscription plan.

=back

=back

=head3 EXAMPLES

my $auth = Cpanel::Koality::Auth->new( 'cpanel_username' => $user );

my $user = $auth->auth_session();

my $subscription = $user->get_subscription();

=cut

sub get_subscription ($self) {

    my $company_id = $self->user_config->{full}{user}{company}{id} // die locale()->maketext('Failed to find the company ID.');

    $self->api->method('GET');
    $self->api->base_url( $self->cluster_endpoint );
    $self->api->auth_token( $self->session_token );
    $self->api->endpoint("subscription/company/$company_id/");    # The slash at the end of this request is needed for a quirk in their routing.
    $self->api->payload( { access_token => $self->session_token } );

    my $response = $self->api->run();

    return $response->{data};
}

=head2 save_user_info( \%user_info )

Persist user configuration information on disk.

=head3 ARGUMENTS

A Hashref containing the requisite user information.
This is retreived from the Koality backend upon authentication, and shouldn't be manually supplied.

=head3 RETURNS

1 if saving to disk is successful, dies on failure.

=head3 EXAMPLES

From C<Cpanel::Koality::Auth::auth_session()>:

$self->api->method('POST');

$self->api->base_url( $user_info{cluster_endpoint} );

$self->api->endpoint( "auth/tokens/token/" . $user_info{master_user_id} );

$self->api->auth_token( $user_info{auth_token} );

$self->api->payload( { access_token => $user_info{auth_token} } );

$response = $self->api->run();

...

$user->save_user_info( $response->{data} );

=cut

sub save_user_info ( $self, $full_user_info = {} ) {
    my $info = {
        koality_username => $self->koality_username,
        auth_token       => $self->auth_token,
        app_token        => $self->app_token,
        cluster_endpoint => $self->cluster_endpoint,
        user_id          => $self->user_id,
        master_user_id   => $self->master_user_id,
        refresh_token    => $self->refresh_token,
        session_token    => $self->session_token,
        uuid             => $self->uuid,
    };
    $info->{enabled} = $self->enabled ? 1 : 0;
    $info->{full}    = $full_user_info if defined $full_user_info;

    my $tx = Cpanel::Transaction::File::JSON->new( path => $self->_conf_file, permissions => 0600, ownership => [ $self->cpanel_username ] );
    $tx->set_data($info);
    $tx->save_or_die();

    $self->user_config($info);
    return 1;
}

=head2 disable_onboarding()

Disable the Koality onboarding wizard.

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

Hashref containing the API response.

=over

=item message - string

Response message from API.

=item status - string

Status code for the API response.

=item data - Hashref

Response data from API. This should return undef on success.

=back

=head3 EXAMPLES

my $auth = Cpanel::Koality::Auth->new( 'cpanel_username' => $user );

my $user = $auth->auth_session();

print Dumper $user->disable_onboarding();

=cut

sub disable_onboarding ($self) {

    my $id = $self->master_user_id;

    $self->api->base_url( $self->auth_url );
    $self->api->method('PUT');
    $self->api->endpoint("memory/user/$id");
    $self->api->auth_token( $self->auth_token );
    $self->api->payload(
        {
            key   => 'welcomeFinished',
            value => 'true',              # needs to be a string and not "JSON" true.
        }
    );

    return $self->api->run();
}

=head2 reset_config()

Resets the cPanel user's Koality config.

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

A new Cpanel::Koality::User object.

=head3 EXAMPLES

my $user = Cpanel::Koality::User->new( 'cpanel_username' => $user );

$user = $user->reset_config();

=cut

sub reset_config ($self) {
    require Cpanel::FileUtils::Move;

    # If the conf file does not exist, our job here is already done.
    return 1 unless -e $self->_conf_file;

    my $dest = $self->_conf_file . "." . time;
    if ( Cpanel::FileUtils::Move::safemv( $self->_conf_file, $dest ) ) {
        return Cpanel::Koality::User->new( 'cpanel_username' => $self->cpanel_username );
    }

    die locale()->maketext('Failed to remove the current Site Quality Monitoring user.');
    return 0;
}

# File operations in a user's homedir shouldn't be run as the root user.
# Can fix this later or move the config to /var/cpanel or userdata.
sub _ensure_conf_dir ($self) {
    mkdir( $self->_conf_dir, 0755 );
    my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam( $self->cpanel_username ) )[ 2, 3 ];
    chown( $uid, $gid, $self->_conf_dir );
    return 1;
}

1;
