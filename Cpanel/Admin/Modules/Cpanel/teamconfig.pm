package Cpanel::Admin::Modules::Cpanel::teamconfig;

# cpanel - Cpanel/Admin/Modules/Cpanel/teamconfig.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Exception              ();
use Cpanel::Team::Config           ();
use Cpanel::Team::Constants        ();

use constant _demo_actions => (
    'LOAD',
    'LOAD_ARRAY',
);

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::teamconfig

=head1 SYNOPSIS

  use Cpanel::AdminBin::Call ();
  Cpanel::AdminBin::Call::call( "Cpanel", "teamconfig", "LOAD" );
  Cpanel::AdminBin::Call::call( "Cpanel", "teamconfig", "LOAD_ARRAY" );
  Cpanel::AdminBin::Call::call( "Cpanel", "teamconfig", "ADD_TEAM_USER", %team_user_info );

=head1 DESCRIPTION

These admin bins are for editing team-users through modifying the config file. These
operations require privileges that are not available to the regular users.

=cut

sub _actions {
    my ($self) = @_;

    return (
        $self->SUPER::_actions,
        'LOAD',
        'LOAD_ARRAY',
        'ADD_TEAM_USER',
        'REMOVE_TEAM_USER',
        'SET_PASSWORD',
        'ADD_ROLES',
        'REMOVE_ROLES',
        'SET_ROLES',
        'SET_NOTES',
        'SET_CONTACT_EMAIL',
        'SUSPEND',
        'REINSTATE',
        'SET_EXPIRE',
        'CANCEL_EXPIRE',
        'SEND_CONTACT_INFO_CHANGE_NOTIFICATIONS',
        'SET_TEAM_USER_GUID',
        'SET_LOCALE',
        'SUSPEND_TEAM_MYSQL_USER',
        'UNSUSPEND_TEAM_MYSQL_USER'
    );
}

sub _get_cpuser_data() {
    my ($self) = @_;

    return Cpanel::Config::LoadCpUserFile::load_or_die( $self->get_caller_username() );
}

sub _get_REMOTE_USER() {
    my ($self) = @_;

    return $self->_get_cpuser_data()->{'OWNER'} || 'root';
}

=head1 METHODS

=head2 LOAD

This function loads the Team Config file.

RETURNS: the team data as a hash

=cut

sub LOAD {
    my ($self) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my $team_owner = $self->get_caller_username();
    my $team_obj   = eval { Cpanel::Team::Config->new($team_owner) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    my $team_data = eval { $team_obj->load(); };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($team_data);
}

=head2 LOAD_ARRAY

This function loads the Team Config file.

RETURNS: the team data as an array

=cut

sub LOAD_ARRAY {
    my ($self) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my $team_owner = $self->get_caller_username();
    my $team_obj   = eval { Cpanel::Team::Config->new($team_owner) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    my $team_data = eval { $team_obj->load_array(); };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($team_data);
}

=head2 ADD_TEAM_USER

This function adds a user to the Team Config file.

=head3 ARGUMENTS

=over

=item user_info (Hash) -- Required

The information to make a new team-user.

=over 4

=item user (String) -- Required

The name of the new team-user.

=item notes (String) -- Optional

The notes section of the new team-user.

=item feature_groups (String) -- Optional

A comma separated string with the feature groups for the new team-user.

=item password (String) -- Optional

A password for the new team-user.

=item email (String) -- Required

The contact email for the new team-user.

=item locale (String) -- Optional

The locale for the new team-user.

=item services (String) -- Optional

A comma separated list of permissions for services.

=over 4

=item ftp (Integer) -- Optional

Enabled with '1', disabled with empty string.

=item webdisk (String) -- Optional

Webdisk enabled as 'rw', 'ro', and disabled with empty string.

=item email (String) -- Optional

Set the email quota with a number (in bytes), or as 'unlimited', or as an empty string.

=back

=item tfa (String) -- Optional

The secret key to enable tfa with the team-user.

=back

=back

RETURNS: 1 on success

=cut

sub ADD_TEAM_USER {
    my ( $self, %team_user_info ) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my $team_owner = $self->get_caller_username();
    my $team_obj   = eval { Cpanel::Team::Config->new($team_owner) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    my $team_user_added_status = eval { $team_obj->add_team_user(%team_user_info) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($team_user_added_status);
}

=head2 SET_TEAM_USER_GUID

This function sets the Subaccount GUID field for a team-user.

ARGUMENTS

team_user (String) -- Required

The name of the team-user to set subaccount GUID for.

guid (String) -- Required

The subaccount GUID.

SEE ALSO Cpanel::Team::Services for more description of GUID spec, and how we use Cpanel::UserManager to store the records.

=cut

sub SET_TEAM_USER_GUID {
    my ( $self, $team_user, $guid ) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my $team_owner = $self->get_caller_username();
    my $team_obj   = eval { Cpanel::Team::Config->new($team_owner) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    my $team_user_updated_status = eval { $team_obj->set_team_user_guid( $team_user, $guid ) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($team_user_updated_status);
}

=head2 REMOVE_TEAM_USER

This function removes a team-user.

=head3 ARGUMENTS

=over

=item username - string
Required. The name of the team-user to remove.

=back

=cut

sub REMOVE_TEAM_USER {
    my ( $self, $team_user ) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my $team_owner          = $self->get_caller_username();
    my $team_obj            = Cpanel::Team::Config->new($team_owner);
    my $user_removed_status = eval { $team_obj->remove_team_user($team_user) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($user_removed_status);
}

=head2 SET_PASSWORD

This function replaces the password for a team user.

=head3 ARGUMENTS

=over

=item user
Required. The name of the team-user to modify.

=item password
Required. The new password for the team-user.

=back

=cut

sub SET_PASSWORD {
    my ( $self, $team_user, $team_user_password ) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my $team_owner = $self->get_caller_username();
    my $team_obj   = eval { Cpanel::Team::Config->new($team_owner) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    my $set_password_status = eval { $team_obj->set_password( $team_user, $team_user_password ); };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($set_password_status);
}

=head2 ADD_ROLES

This function adds new roles to a team-user.

=head3 ARGUMENTS

=over

=item team_user - string
Required. The name of the team-user to give roles to.

=item roles_aref - array reference
Required. The roles to add.

=back

=head3 RETURNS

Returns 1 on success.

=cut

sub ADD_ROLES {
    my ( $self, $team_user, $roles_aref ) = @_;
    my $team_owner = $self->get_caller_username();

    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();
    my $team_obj           = Cpanel::Team::Config->new($team_owner);
    my $roles_added_status = eval { $team_obj->add_roles( $team_user, @$roles_aref ) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($roles_added_status);
}

=head2 REMOVE_ROLES

This function removes a role from a team-user.

=head3 ARGUMENTS

=over

=item team_user - string
The name of the team-user to remove roles from.

=item roles_aref - array reference
Required. The roles to remove.

=back

=cut

sub REMOVE_ROLES {
    my ( $self, $team_user, $roles_aref ) = @_;
    my $team_owner = $self->get_caller_username();

    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();
    my $team_obj             = Cpanel::Team::Config->new($team_owner);
    my $roles_removed_status = eval { $team_obj->remove_roles( $team_user, @$roles_aref ) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($roles_removed_status);
}

=head2 SET_ROLES

This function sets the roles of a team-user.

=head3 ARGUMENTS

=over

=item team_user - string
The name of the team-user to set roles for.

=item roles_aref - array reference
Required. The new roles passed in as a reference.

=back

=head3 RETURNS

Returns 1 on success.

=cut

sub SET_ROLES {
    my ( $self, $team_user, $roles_aref ) = @_;
    my $team_owner = $self->get_caller_username();

    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();
    my $team_obj        = Cpanel::Team::Config->new($team_owner);
    my $role_set_status = eval { $team_obj->set_roles( $team_user, @$roles_aref ) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($role_set_status);
}

=head2 SET_NOTES

This function sets the notes field for a team-user.

=head3 ARGUMENTS

=over

=item team_user - string
Required. The name of the team-user to set notes for.

=item notes - string
Required. The text to put in the notes field.

=back

=cut

sub SET_NOTES {
    my ( $self, $team_user, $notes ) = @_;
    my $team_owner = $self->get_caller_username();

    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();
    my $team_obj         = Cpanel::Team::Config->new($team_owner);
    my $notes_set_status = eval { $team_obj->set_notes( $team_user, $notes ) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($notes_set_status);
}

=head2 SET_LOCALE

This function sets the locale for a team-user.

=head3 ARGUMENTS

=over

=item team_user - string
Required. The name of the team-user to set locale for.

=item locale - string
Required. The locale for this team-user.

=back

=cut

sub SET_LOCALE {
    my ( $self, $team_user, $locale ) = @_;
    my $team_owner = $self->get_caller_username();

    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();
    my $team_obj          = Cpanel::Team::Config->new($team_owner);
    my $locale_set_status = eval { $team_obj->set_locale( $team_user, $locale ) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($locale_set_status);
}

=head2 SET_CONTACT_EMAIL

This function sets the contact email for a team-user.

=head3 ARGUMENTS

=over

=item team_user - string
Required. The name of the team-user to set the contact email for.

=item email - string
Required. The email address to assign to the team-user.

=back

=cut

sub SET_CONTACT_EMAIL {
    my ( $self, $team_user, $email ) = @_;
    my $team_owner = $self->get_caller_username();

    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();
    my $team_obj         = Cpanel::Team::Config->new($team_owner);
    my $email_set_status = eval { $team_obj->set_contact_email( $team_user, $email ) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($email_set_status);
}

=head2 SUSPEND

This function suspends a team-user and disables their password.

=head3 ARGUMENTS

=over

=item username - string
Required. The name of the team-user to suspend.

=item suspend_reason - string
Optional. The reason for suspension.

=back

=head3 RETURNS

Returns 1 on success.

=cut

sub SUSPEND {
    my ( $self, $username, $suspend_reason ) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my $team_owner     = $self->get_caller_username();
    my $team_obj       = Cpanel::Team::Config->new($team_owner);
    my $suspend_status = eval { $team_obj->suspend_team_user( team_user => $username, suspend_reason => $suspend_reason ) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($suspend_status);
}

=head2 REINSTATE

This function reinstates a team-user and re-enables their password.

=head3 ARGUMENTS

=over

=item username - string
Required. The name of the team-user to reinstate.

=back

=head3 RETURNS

Returns 1 on success.

=cut

sub REINSTATE {
    my ( $self, $username ) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my $team_owner       = $self->get_caller_username();
    my $team_obj         = Cpanel::Team::Config->new($team_owner);
    my $reinstate_status = eval { $team_obj->reinstate_team_user($username) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($reinstate_status);
}

=head2 SET_EXPIRE

This function sets a team-user to expire at a specified date.

=head3 ARGUMENTS

=over

=item username - string
Required. The name of the team-user to expire.

=item expire_date - string
Required. The date to suspend the team-user.

=item expire_reason - string
Optional. The reason for expiration.

=back

=head3 RETURNS

Returns 1 on success.

=cut

sub SET_EXPIRE {
    my ( $self, $username, $expire_date, $expire_reason ) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my $team_owner    = $self->get_caller_username();
    my $team_obj      = Cpanel::Team::Config->new($team_owner);
    my $expire_status = eval { $team_obj->set_expire( $username, $expire_date, $expire_reason ) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($expire_status);
}

=head2 CANCEL_EXPIRE

This function prevents a team-user from expiring and removes the expired status from a team-user.
Note: This function does not unsuspend a team-user.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to cancel expiration for.

=back

=head3 RETURNS

Returns 1 on success.

=cut

sub CANCEL_EXPIRE {
    my ( $self, $username ) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my $team_owner    = $self->get_caller_username();
    my $team_obj      = Cpanel::Team::Config->new($team_owner);
    my $expire_status = eval { $team_obj->cancel_expire($username) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($expire_status);
}

=head2 SEND_CONTACT_INFO_CHANGE_NOTIFICATIONS

This function sends notifications to team user when they turn off notification preferences in
conatact information page.

=head3 ARGUMENTS

 notification_args (Hash) -- Required -- The information to trigger notify module for team-user.

=over 4

 username (String) -- Required -- The login name of the team-user.

 to_user (String) -- Required - The login name of the new team-user.

 origin (String) -- Required -- cpanel will always be the origin.

 ip (String) -- Required -- The ip address of the team user initiating the notification change.

 notifications_hr (hash reference) -- Required -- Contains the name of the modified preferences with new and old values.
 it also contains the email addresses that needs to be notified.

=back

=head3 RETURNS

Returns 1 on success.

=cut

sub SEND_CONTACT_INFO_CHANGE_NOTIFICATIONS {
    my ( $self, %notification_args ) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    require Cpanel::ContactInfo::Notify;
    my $notification_status = eval { Cpanel::ContactInfo::Notify::send_contactinfo_change_notifications_to_user(%notification_args) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($notification_status);
}

=head2 SUSPEND_TEAM_MYSQL_USER

This function suspends team_user's mysql account by locking their mysql account.

=head3 ARGUMENTS

=over

=item mysql_user - string
Required. The name of the team-user's mysql account to suspend.

=back

=head3 RETURNS

Returns 1 on success.

=cut

sub SUSPEND_TEAM_MYSQL_USER {
    my ( $self, $mysql_user ) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    require Cpanel::Team::Config;
    my $notification_status = eval { Cpanel::Team::Config::suspend_mysql_user($mysql_user); };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($notification_status);
}

=head2 UNSUSPEND_TEAM_MYSQL_USER

This function unsuspends team_user's mysql account by unlocking their mysql account.

=head3 ARGUMENTS

=over

=item mysql_user - string
Required. The name of the team-user's mysql account to unsuspend.

=back

=head3 RETURNS

Returns 1 on success.

=cut

sub UNSUSPEND_TEAM_MYSQL_USER {
    my ( $self, $mysql_user ) = @_;
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    require Cpanel::Team::Config;
    my $notification_status = eval { Cpanel::Team::Config::unsuspend_mysql_user($mysql_user); };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;

    return ($notification_status);
}
1;
