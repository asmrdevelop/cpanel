package Cpanel::Koality::Base;

# cpanel - Cpanel/Koality/Base.pm                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Cpanel::Koality::ApiClient ();
use Cpanel::License::CompanyID ();
use Cpanel::Plugins::ServerId  ();
use Cpanel::Plugins::UUID      ();
use Cpanel::Imports;

=head1 MODULE

C<Cpanel::Koality::Base>

=head1 DESCRIPTION

C<Cpanel::Koality::Base> is the base class that provides attributes inherited by various different Koality subclasses.

=head1 ATTRIBUTES

=head2 cpanel_username - string

The username of the cPanel user with which the target Koality account is/will be associated. The user must exist.

=cut

has 'cpanel_username' => (
    is  => 'rw',
    isa => sub {
        require Cpanel::Validate::Username;
        Cpanel::Validate::Username::user_exists_or_die( $_[0] );
    },
    default => sub ($self) { return $Cpanel::user || die 'Must set the cpanel_username attribute.' }
);

=head2 company_id - string

Fetch the company id for the server.

=cut

has 'company_id' => (
    is   => 'ro',
    lazy => 1,
    isa  => sub {
        die locale->maketext("[asis,company_id] is not defined!") unless defined $_[0];
    },
    default => sub ($self) { return Cpanel::License::CompanyID::get_company_id() }
);

=head2 server_id - string

Fetch the unique server id for the server.

=cut

has 'server_id' => (
    is   => 'ro',
    lazy => 1,
    isa  => sub {
        die locale->maketext("[asis,server_id] is not defined!") unless defined $_[0];
    },
    default => sub ($self) { return Cpanel::Plugins::ServerId::get_server_id() }
);

=head2 use_stage - boolean

Whether the targeted backend API environment is staging. This is set with a touchfile at C</var/cpanel/use_koality_stage>

=cut

has 'use_stage' => (
    is  => 'rw',
    isa => sub {
        require Cpanel::Validate::Boolean;
        Cpanel::Validate::Boolean::validate_or_die( $_[0] );
    },
    default => sub { return -e '/var/cpanel/use_koality_stage' ? 1 : 0 }
);

=head2 timeout - int

The timeout for requests.

NOTE: 'timeout' is a read-only attribute that should only be set in the object constructor.
Changing the timeout attribute between rest api calls can lead to unintended behavior as the
new HTTP client will create a new socket which is immediately ready for r/w operations and thus
will not properly time out when expected.

=cut

has timeout => (
    is      => 'ro',
    default => 10,
);

=head2 api - C<Cpanel::Plugins::RestApiClient> instance

The API client that will be used to make calls against the Koality API backend.

=cut

has 'api' => (
    is      => 'ro',
    lazy    => 1,
    isa     => \&Cpanel::Koality::Validate::valid_api_object,
    builder => 1
);

=head2 auth_url - string

The base URL to use for authentication requests.
The URL varies based on environment.

=cut

has 'auth_url' => (
    is      => 'ro',
    lazy    => 1,
    isa     => \&Cpanel::Koality::Validate::valid_api_url,
    default => sub ($self) {
        return $self->use_stage ? 'https://auth.stage.koalityengine.com/v1/cpanel/' : 'https://auth.koalityengine.com/v1/cpanel/';
    }
);

=head2 app360_url - string

The base URL to use for App360 requests.
App360 is used as a middleman in the creation of a new user and provides the new user's app token, itself used for session authentication.
The URL varies based on environment.

=cut

has 'app360_url' => (
    is      => 'ro',
    lazy    => 1,
    isa     => \&Cpanel::Koality::Validate::valid_api_url,
    default => sub ($self) {
        return $self->use_stage ? 'https://cpanel.app.stage.360monitoring.com/' : 'https://app.cpanel.360monitoring.com/';
    }
);

has 'uuid' => (
    is   => 'ro',
    lazy => 1,
    isa  => sub ($uuid) {
        require Cpanel::Validate::UUID;
        Cpanel::Validate::UUID::validate_uuid_or_die($uuid);
    },
    default => sub ($self) {
        my $uuid = Cpanel::Plugins::UUID->new( user => $self->cpanel_username );
        return $uuid->uuid();
    }
);

has '_check_privs' => (
    is      => 'ro',
    lazy    => 1,
    builder => 1,
);

sub BUILD ( $self, $args ) {
    $self->_check_privs();
    return;
}

sub _build__check_privs ($self) {
    if ( !$> ) {
        require Cpanel::AccessIds::ReducedPrivileges;
        return Cpanel::AccessIds::ReducedPrivileges->new( $self->cpanel_username );
    }
    return;
}

sub _build_api ($self) {
    return Cpanel::Koality::ApiClient->new( cpanel_username => $self->cpanel_username, timeout => $self->timeout );
}

1;
