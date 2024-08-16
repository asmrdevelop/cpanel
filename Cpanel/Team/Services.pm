package Cpanel::Team::Services;

# cpanel - Cpanel/Team/Services.pm                 Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::AcctUtils::Domain ();
use Cpanel::Exception         ();
use Cpanel::PwCache           ();
use Cpanel::UserManager       ();

=encoding utf-8

=head1 NAME

Cpanel::Team::Services

=head1 DESCRIPTION

Creates/links/updates one main subaccount and up to 3 associated service subaccounts:
FTP, Web Disk, and email.

When a team user is created through the API, it is associated with a new main
subaccount, and the association is saved in the Team Manager Config. Also at
creation, any service subaccounts requested are created and associated. When
Team Manager API needs information about these subaccounts, this module gets the
data and parses it for Team Manager consumption.

This is really an interface to Cpanel::UserManager, from which further associations
and disassociations of service accounts are possible.

This module and UserManager run as the cPanel user, while the rest of Team project
runs as root.

  my $services_obj = Cpanel::Team::Services->new( 'team_owner_name' );

  my $team_user_subacct_guid = $services_obj->add_subaccounts(
    {
      user          => 'teamusername',
      services      => {
        ftp => {
          enabled => 1,
          homedir => 'team_user',        # Path, relative to team-owner's home directory.
          quota   => '',
        },
        webdisk => {
          enabled      => 1,
          perms        => 'rw',
          homedir      => 'team_user',   # Path, relative to team-owner's home directory.
          enabledigest => 0,
          private      => 0,
        },
        email => {
          enabled => 1,
          quota   => 2048,               # 2GB
        },
      },
      password_hash => '$6$xHH1bymC/5BqNQ2w$kxnuAxmyWFl5QXBuoanTfvnLnhkUQ2o8Nt4EdCDc4bPe2aO57Of4uytoqeuxm5vdrefgmk./LiX/fjka6LTgH1',
    }
  );

=head1 METHODS

=head2 $obj = I<CLASS>->new( $team_owner_name )

Instantiate and return a team services object.

=cut

sub new ( $class, $team_owner ) {

    my $self = { team_owner => $team_owner };

    return bless $self, $class;
}

=head2 $subaccount_guid = I<OBJ>->add_subaccounts( { user => $u, services => $svs, password_hash => $pw } )

Create and associate service subaccounts to a Team Manager user.

EXAMPLE found in the module description above.

RETURNS the subaccount GUID in User Manager format, e.g.:

  BOBBY:TEAMOWNER.TLD:A2345678:A234567890B234567890C234567890D234567890E234567890F234567890G123

SEE ALSO

  Cpanel::Team::Config::_encode                       - For how this GUID parameter is encoded when saved to disk.
  Cpanel::Team::Config::add_team_user                 - For service params validation.

  t/small/Cpanel-Team-Services.t _get_mocks           - Data structure for the hash of inputs %team_user_info
  t/small/Cpanel-Team-Services.t test_add_subaccounts - Data structure for the return from UserManager::create_user

=cut

sub add_subaccounts ( $self, $team_user_info_hr ) {
    my %args = (
        username   => $team_user_info_hr->{user},
        password   => $team_user_info_hr->{password},
        team_owner => $self->{team_owner},
        home_dir   => ( Cpanel::PwCache::getpwnam( $self->{team_owner} ) )[7],
        domain     => Cpanel::AcctUtils::Domain::getdomain( $self->{team_owner} ),
        services   => $team_user_info_hr->{services},
    );
    my $res = Cpanel::UserManager::create_user( \%args );

    if ( !defined $res->{guid} || $res->{guid} eq '' ) {
        die Cpanel::Exception::create( 'SystemCall', [ name => 'Cpanel::UserManager::create_user', error => 'No GUID returned' ] );
    }

    return $res->{guid};
}

=head2 $success = I<OBJ>->remove_subaccounts( $team_user_name )

Delete a Team Manager user associated subaccount, and all of its associated service accounts.

RETURNS 1 for success.

=cut

sub remove_subaccounts ( $self, $username, $guid ) {
    my %args = (
        username   => $username,
        team_owner => $self->{team_owner},
        domain     => Cpanel::AcctUtils::Domain::getdomain( $self->{team_owner} ),
    );

    Cpanel::UserManager::delete_user(%args);

    # Ensure all service subaccounts are gone
    $self->fetch_team_services;
    my $should_be_empty = $self->get_team_user_services($guid);
    if ( $should_be_empty->{ftp}->{enabled} || $should_be_empty->{webdisk}->{enabled} || $should_be_empty->{email}->{enabled} ) {
        die Cpanel::Exception::create( 'SystemCall', [ name => 'Cpanel::UserManager::delete_user', error => 'Subaccount total removal failed.' ] );
    }

    return 1;
}

=head2 $success = I<OBJ>->fetch_team_services()

Bring a cPanel user team subaccount, and all of its associated services accounts,
into the Services object memory.

RETURNS 1 for success.

SEE ALSO F<t/small/Cpanel-Team-Services.t> (sub _mock_and_test_fetch)
for the return data structure, including services, of Cpanel::UserManager::list_users

=cut

sub fetch_team_services ($self) {
    require Cpanel::UserManager;

    my $um_resp = Cpanel::UserManager::list_users();

    for my $um_obj ( @{$um_resp} ) {
        $self->{subguids_services_hr}->{ $um_obj->{guid} } = $um_obj->{services};
    }

    return 1;
}

=head2 $services_hr = I<OBJ>->get_team_user_services( $team_manager_user_subaccount_guid )

Get one team user's associated service accounts. User Manager retrieves the entire
subaccount's information at one time. If the team services hash has already been
loaded into Services object memory, use that cache instead of querying the same
information repeatedly.

RETURNS a hashref of the team account 3 services and options, e.g.:

  {
    ftp => {
      enabled => 1,
      homedir => '',
      quota   => '',
    },
    webdisk => {
      enabled      => 1,
      perms        => 'rw',
      homedir      => '/custom/path',
      enabledigest => 0,
      private      => 0,
    },
    email => {
      enabled => 1,
      quota   => 'unlimited',
    },
  }

=cut

sub get_team_user_services ( $self, $tm_guid ) {

    # allows subguids/services hash to be cached if looping through team users
    if ( !defined $self->{subguids_services_hr} ) {
        $self->fetch_team_services();
    }

    my $size = keys %{ $self->{subguids_services_hr} };
    return undef if $size < 1;

    return $self->{subguids_services_hr}->{$tm_guid};
}

=head2 $success = I<OBJ>->edit_subaccounts( $team_user_info_hr )

Edit a Team Manager user associated subaccount, and all of its associated service accounts.

RETURNS 1 for success.

=cut

sub edit_subaccounts ( $self, $team_user_info_hr ) {
    my %args = (
        username   => $team_user_info_hr->{user},
        team_owner => $self->{team_owner},
        home_dir   => ( Cpanel::PwCache::getpwnam( $self->{team_owner} ) )[7],
        domain     => Cpanel::AcctUtils::Domain::getdomain( $self->{team_owner} ),
    );

    # don't send undef or it will delete them
    $args{services} = $team_user_info_hr->{services} if defined $team_user_info_hr->{services};
    $args{password} = $team_user_info_hr->{password} if defined $team_user_info_hr->{password};

    require Cpanel::UserManager;
    Cpanel::UserManager::edit_user( \%args );

    return 1;
}

1;
