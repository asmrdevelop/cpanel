package Cpanel::API::Team;

# cpanel - Cpanel/API/Team.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::API::Team

=head1 DESCRIPTION

This module contains UAPI methods related to Team Accounts.
Modifies the team config file located in /var/cpanel/team/<team-owner>.

=head1 FUNCTIONS

=cut

use cPstrict;
use Cpanel::AdminBin::Call    ();
use Cpanel::Exception         ();
use Cpanel::IP::Remote        ();
use Cpanel::Locale            ();
use Cpanel::Logger            ();
use Cpanel::Server::Type      ();
use Cpanel::Team::Services    ();
use Cpanel::ApiUtils          ();
use Cpanel::AcctUtils::Domain ();
use Cpanel::Rand::Get         ();
use Cpanel::Team::Constants   ();

my $non_mutating = { allow_demo => 1 };
my $mutating     = {};

our %API = (
    _needs_feature                  => 'team_manager',
    list_team                       => $non_mutating,
    list_team_ui                    => $non_mutating,
    add_team_user                   => $mutating,
    set_password                    => $mutating,
    remove_team_user                => $mutating,
    add_roles                       => $mutating,
    remove_roles                    => $mutating,
    set_roles                       => $mutating,
    password_reset_request          => $mutating,
    set_locale                      => $mutating,
    get_team_users_with_roles_count => $mutating,
);

=head2 list_team()

This function displays the data from the Team Config file.

=head3 ARGUMENTS

=over

=item format - string
Optional. Entering anything other than 'hash' will return the data in array format.

=back

=head3 RETURNS

Can return either an array (default) or a hash depending on the 'format' parameter.

=cut

sub list_team ( $args, $result ) {
    _license_check($result);
    my $format = $args->get('format') // 'array';
    if   ( $format ne 'hash' ) { $result->data( Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'LOAD_ARRAY' ) ) }
    else                       { $result->data( Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'LOAD' ) ) }

    return 1;
}

=head2 list_team_ui()

This function displays the data from the Team Config file and transforms roles to role titles for UI.

=head3 RETURNS

Returns an array

=cut

sub list_team_ui ( $args, $result ) {
    _license_check($result);

    my $res_ar = Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'LOAD_ARRAY' );

    my $services_obj = Cpanel::Team::Services->new( $ENV{'REMOTE_USER'} );
    foreach my $team_user_hr ( @{$res_ar} ) {
        @{ $team_user_hr->{roles} } = grep { defined } @Cpanel::Team::Constants::TEAM_ROLES{ @{ $team_user_hr->{roles} } };
        $team_user_hr->{services} = $services_obj->get_team_user_services( $team_user_hr->{subacct_guid} );
        delete( $team_user_hr->{password} );
    }

    $result->data($res_ar);

    return 1;
}

=head2 add_team_user()

This function adds a team-user to the Team Config file.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the new team-user.

=item notes - string
Optional. The notes section of the new team-user.

=item roles - string
Optional. A comma separated string with the feature groups for the new team-user.

=item password - string
Optional. A password for the new team-user.

=item email1 - string
Required. The contact email for the new team-user.

=item email2 - string
Optional. The secondary contact email for the new team-user.

=item services - string
Optional. A comma separated list of permissions for services.

=over 2

=item ftp - string
Optional. Enabled with '1', disabled with empty string.

=item webdisk - string
Optional. Web Disk enabled as 'rw', 'ro', and disabled with empty string.

=item email - string
Optional. Set the email quota with a number (in bytes), or as 'unlimited', or as an empty string.

=back

=item locale - string
Optional. The locale of the team-user. Uses team-owner's locale if not defined.

=item expire_date - string
Optional. The date to suspend the team-user in epoch time or the offset in days.
Format for offset is "X days" or "Xdays".

=item activation_email - boolean
Optional. Send activation email when enabled with 1.

=back

=cut

sub add_team_user ( $args, $result ) {
    _license_check($result);
    _escalated_privilege_warning($result);

    my %team_user_info = (
        user                    => $args->get_length_required('user'),
        notes                   => $args->get('notes'),
        roles                   => $args->get('roles'),
        password                => $args->get('password'),
        contact_email           => $args->get_length_required('email1'),
        secondary_contact_email => $args->get('email2'),
        activation_email        => $args->get('activation_email'),
        locale                  => $args->get('locale'),
        expire_date             => $args->get('expire_date'),
        expire_reason           => $args->get('expire_reason'),
    );

    Cpanel::ApiUtils::dot_syntax_expand( $args->{'_args'} );
    $team_user_info{services} = $args->get('services');

    if ( !defined $team_user_info{password} && !defined $team_user_info{activation_email} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Provide either the password or activation_email parameter.' );
    }
    if ( defined $team_user_info{expire_date} && length( $team_user_info{expire_date} ) > 0 ) {
        $team_user_info{expire_date} = _convert_offset_to_epoch( $team_user_info{expire_date} );
        $result->data( $team_user_info{expire_date} );
    }
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'ADD_TEAM_USER', %team_user_info );
    my $activation_email = $team_user_info{'activation_email'} || '';
    my $team_owner       = $ENV{'REMOTE_USER'};

    if ($activation_email) {
        my $domain        = Cpanel::AcctUtils::Domain::getdomain($team_owner);
        my $team_username = $team_user_info{user} . "@" . $domain;
        my $cookie        = Cpanel::AdminBin::Call::call(
            'Cpanel',
            'user',
            'CREATE_TEAM_INVITE',
            $team_username,
        );

        # password required for user manager
        $team_user_info{'password'} //= Cpanel::Rand::Get::getranddata(20);
        _send_email_notification( \%team_user_info, $domain, $cookie );
    }

    # Adding subaccounts does not require root.
    # This must be separate because Cpanel::API::Email is excluded from cpanelsync.
    my $services_obj = Cpanel::Team::Services->new($team_owner);

    my $locale = Cpanel::Locale->get_handle();
    my $guid;
    eval { $guid = $services_obj->add_subaccounts( \%team_user_info ) };

    # Using Team Manager requires root again.
    if ( my $err = $@ ) {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'REMOVE_TEAM_USER', $team_user_info{user} );

        # Log full error, but remove trailing filename and line number for end users.
        Cpanel::Logger->new->warn($err);
        $err =~ s!\. at [\w/.]+ line \d+\.$!.!;
        die Cpanel::Exception::create( 'SystemCall', [ name => 'Cpanel::Team::Services::add_subaccounts', error => "$err" ] );
    }
    else {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_TEAM_USER_GUID', $team_user_info{user}, $guid );
    }

    # create a mysql user account for team user
    my $mysql_user = $team_owner . '_' . $team_user_info{user};
    my $mysql_args = {
        name     => $mysql_user,
        password => $team_user_info{password}
    };

    eval { _add_mysql_user($mysql_args); };
    if ( my $err = $@ ) {
        die Cpanel::Exception::create( 'SystemCall', [ name => '_add_mysql_user', error => "$err" ] );
    }

    # suspend the mysql team user account for non database/admin roles.
    # preserve the mysql account for later use when given database/admin roles.
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SUSPEND_TEAM_MYSQL_USER', $mysql_user ) if !defined $team_user_info{roles} || $team_user_info{roles} !~ /\b$Cpanel::Team::Constants::NEEDS_MYSQL\b/i;

    return 1;
}

sub _send_email_notification {
    my ( $team_user_info, $domain, $cookie ) = @_;

    my $full_username = $team_user_info->{'user'} . "@" . $domain;

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'notify_call',
        defined $team_user_info->{'type'} ? 'NOTIFY_TEAM_USER_RESET_REQUEST' : 'NOTIFY_NEW_USER',
        user              => $full_username,
        subaccount        => '',
        cookie            => $cookie,
        user_domain       => $domain,
        origin            => $Cpanel::App::appname,
        source_ip_address => Cpanel::IP::Remote::get_current_remote_ip(),
        to                => $full_username,
        team_account      => 1,
    );

    return;
}

=head2 edit_team_user()

This function edits a team-user in the Team Config file.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to edit.

=item notes - string
Optional. Set the notes section for the team-user.

=item set_role - string
Optional. The role or roles to assign to a team-user, replacing current roles.
Type multiple set_role parameters in the following format: set_role-1=Email set_role-2=Files...

=item add_role - string
Optional. The role or roles to add to a team-user, in addition to the current roles.
Type multiple add_role parameters in the following format: add_role-1=Email add_role-2=Files...

=item remove_role - string
Optional. The role or roles to remove from a team-user.
Type multiple set_role parameters in the following format: remove_role-1=Email remove_role-2=Files...

=item password - string
Optional. A new password for the team-user.

=item email1 - string
Optional. The contact email address to assign to the team-user.

=item email2 - string
Optional. The contact email address to assign to the team-user.

=item services - string
Optional. A comma separated list of permissions for services.

=item set_expire - string
Optional. The epoch time for a team-user to expire on or the number of days before they expire.
The offset is formatted as "X days" or "Xdays" where X is the number of days.

=item expire_reason - string
Optional. The reason for the expiration of the user.

=back

=cut

sub edit_team_user ( $args, $result ) {
    _license_check($result);

    my $team_user     = $args->get_length_required('user');
    my $note_edit     = $args->get('notes');
    my $set_roles     = [ $args->get_multiple('set_role') ];
    my $add_roles     = [ $args->get_multiple('add_role') ];
    my $remove_roles  = [ $args->get_multiple('remove_role') ];
    my $password_edit = $args->get('password');
    my $email1        = $args->get('email1');
    my $email2        = $args->get('email2');
    my $email_edit    = [];
    my $expire_date   = $args->get('expire_date');
    my $expire_reason = $args->get('expire_reason');

    Cpanel::ApiUtils::dot_syntax_expand( $args->{'_args'} );
    my $services = $args->get('services');

    if ( defined $note_edit ) {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_NOTES', $team_user, $note_edit );
    }
    if ( @$set_roles > 0 ) {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_ROLES', $team_user, $set_roles );
    }
    if ( @$add_roles > 0 ) {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'ADD_ROLES', $team_user, $add_roles );
    }
    if ( @$remove_roles > 0 ) {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'REMOVE_ROLES', $team_user, $remove_roles );
    }
    if ( defined $password_edit && length($password_edit) > 0 ) {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_PASSWORD', $team_user, $password_edit );
    }
    if ( defined $email1 || defined $email2 ) {
        push( @{$email_edit}, ( $email1, $email2 ) );
        Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_CONTACT_EMAIL', $team_user, $email_edit );
    }
    if ( defined $expire_date ) {
        $expire_date = _convert_offset_to_epoch($expire_date);
        $result->data($expire_date);
        Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_EXPIRE', $team_user, $expire_date, $expire_reason );
    }
    if ( defined $services || defined $password_edit ) {
        my %team_user_info = (
            user     => $team_user,
            services => $services,
            password => $password_edit,
        );

        # Editing subaccounts does not require root, and dies on failures.
        Cpanel::Team::Services->new( $ENV{'REMOTE_USER'} )->edit_subaccounts( \%team_user_info );

    }

    return 1;
}

=head2 set_password()

This function replaces the password of a team-user.
Encrypts the password.
Fails if:
team configuration file is corrupt,
team-user does not exist,
team-user is suspended.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to modify.

=item password - string
Required. The new password for the team-user.

=back

=cut

sub set_password ( $args, $result ) {
    _license_check($result);
    my $team_user = $args->get_length_required('user');
    my $passwd    = $args->get_length_required('password');
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_PASSWORD', $team_user, $passwd );

    return 1;
}

=head2 remove_team_user()

This function deletes a team-user.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to remove.

=back

=cut

sub remove_team_user ( $args, $result ) {
    _license_check($result);
    my $team_user = $args->get_length_required('user');

    # Get GUID - loading config file requires root.
    my $res    = Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'LOAD' );
    my $guid   = $res->{users}->{$team_user}->{subacct_guid};
    my $locale = Cpanel::Locale->get_handle();

    # Removing subaccounts does not require root, and warns on failures.
    if ($guid) {
        eval { Cpanel::Team::Services->new( $ENV{'REMOTE_USER'} )->remove_subaccounts( $team_user, $guid ); };
        if ( my $err = $@ ) {
            $result->raw_warning( $locale->maketext( 'The subaccount could not be deleted due to the following error “[_1]”.', $err ) );
        }
    }
    else {
        $result->raw_warning( $locale->maketext("The subaccount GUID parameter is missing from the Team configuration file, so no services were removed.") );
    }

    # Remove mysql account for team user
    require Cpanel::MysqlUtils::Command;
    my $mysql_user = $ENV{'REMOTE_USER'} . '_' . $team_user;
    if ( Cpanel::MysqlUtils::Command::user_exists($mysql_user) ) {
        eval {
            require Cpanel::API;
            my $result = Cpanel::API::execute(
                'Mysql', 'delete_user',
                {
                    name => $mysql_user,
                }
            );
        };
        if ( my $err = $@ ) {
            $result->raw_warning( $locale->maketext( 'The MySQL account could not be deleted due to the following error “[_1]”.', $err ) );
        }
    }

    # Removing team user from Team config file requires root.
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'REMOVE_TEAM_USER', $team_user );

    return 1;
}

=head2 add_roles()

This function adds new roles to a team-user.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to give roles to.

=item role - string
Required. The role to add. To add multiple roles, type multiple role parameters 'role-1=Email role-2=Files ...'

=back

=cut

sub add_roles ( $args, $result ) {
    _license_check($result);
    _escalated_privilege_warning($result);
    my $team_user = $args->get_length_required('user');
    my $new_roles = [ $args->get_length_required_multiple('role') ];
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'ADD_ROLES', $team_user, $new_roles );

    return 1;
}

=head2 remove_roles()

This function removes one or more roles from a team-user.

=head3 ARGUMENTS

=over

=item user - string
The name of the team-user to remove the role(s) from.

=item role - string
Required. The role to remove. To remove multiple roles, type multiple role parameters 'role-1=Email role-2=Files ...'

=back

=cut

sub remove_roles ( $args, $result ) {
    _license_check($result);
    my $team_user       = $args->get_length_required('user');
    my $roles_to_remove = [ $args->get_length_required_multiple('role') ];
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'REMOVE_ROLES', $team_user, $roles_to_remove );

    return 1;
}

=head2 set_roles()

This function assigns roles to a team-user, replacing current roles.
The frontend calls this function from Edit team user page for updating roles.

=head3 ARGUMENTS

=over

=item user - string
The name of the team-user to set roles for.

=item role - string
Optional. The role or roles to assign.
It also accepts empty role.
Assigns empty role when no role is provided.
Type multiple role parameters in the following format: role-1=Email role-2=Files etc...

=back

=cut

sub set_roles ( $args, $result ) {
    _license_check($result);
    _escalated_privilege_warning($result);
    my $team_user    = $args->get_length_required('user');
    my $roles_to_set = [ $args->get_multiple('role') ] // '';
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_ROLES', $team_user, $roles_to_set );

    return 1;
}

=head2 set_notes

This function sets the notes field for a team-user.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to provide notes for.

=item notes - string
Required. The text to put in the notes field.

=back

=cut

sub set_notes ( $args, $result ) {
    _license_check($result);
    my $name  = $args->get_length_required('user');
    my $notes = $args->get_required('notes');
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_NOTES', $name, $notes );

    return 1;
}

=head2 set_locale

This function sets the locale for a team-user.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to provide notes for.

=item locale - string
Required. The locale to put in the locale field.

=back

=cut

sub set_locale ( $args, $result ) {
    _license_check($result);
    my $name   = $args->get_length_required('user');
    my $locale = $args->get_required('locale');
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_LOCALE', $name, $locale );

    return 1;
}

=head2 set_contact_email

This function sets the contact email for a team-user.
It requires at least one email parameter.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to set the contact email for.

=item email1 - string
Optional. The contact email address to assign to the team-user.

=item email2 - string
Optional. The secondary contact email address to assign to the team-user.

=back

=cut

sub set_contact_email ( $args, $result ) {
    _license_check($result);
    my $name   = $args->get_length_required('user');
    my $email1 = $args->get('email1');
    my $email2 = $args->get('email2');
    if ( !$email1 && !$email2 ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Provide either the email1 or email2 parameter.' );
    }
    my $email = [ $email1, $email2 ];
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_CONTACT_EMAIL', $name, $email );

    return 1;
}

=head2 suspend_team_user

This function suspends a team-user and disables their password.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to suspend.

=item reason - string
Optional. The reason for suspension.

=item suspend_as_team - boolean
Optional. Disables password without leaving a timestamp.

=back

=cut

sub suspend_team_user ( $args, $result ) {
    _license_check($result);
    my $name           = $args->get_length_required('user');
    my $suspend_reason = $args->get('reason');
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SUSPEND', $name, $suspend_reason );

    return 1;
}

=head2 reinstate_team_user

This function reinstates a team-user by removing the suspended and/or expired statuses.
This has no effect on pending expiration events.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to reinstate.

=back

=cut

sub reinstate_team_user ( $args, $result ) {
    _license_check($result);
    my $name = $args->get_length_required('user');
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'REINSTATE', $name );
    return 1;
}

=head2 password_reset_request

This function sends a password reset request to team-user and helps them reset
their password.

=head3 ARGUMENTS

=over

=item user - string
Required. The username of the team-user who requested the password reset.

=back

=cut

sub password_reset_request ( $args, $result ) {
    _license_check($result);
    my $team_user     = $args->get_length_required('user');
    my $team_owner    = $ENV{'REMOTE_USER'};
    my $domain        = Cpanel::AcctUtils::Domain::getdomain($team_owner);
    my $team_username = $team_user . "@" . $domain;
    my $cookie        = Cpanel::AdminBin::Call::call(
        'Cpanel',
        'user',
        'CREATE_TEAM_INVITE',
        $team_username,
    );
    _send_email_notification( { 'user' => $team_user, 'type' => 'reset_request' }, $domain, $cookie );

    return 1;
}

=head2 set_expire

This function schedules a team-user to expire on a specified date, disabling the account.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to expire.

=item date - string
Optional. The date to suspend the team-user in epoch time or the offset in days.
Format for offset is "X days" or "Xdays". 

=item reason - string
Optional. The reason for expiration.

=back

=cut

sub set_expire ( $args, $result ) {
    _license_check($result);
    my $name          = $args->get_length_required('user');
    my $expire_date   = $args->get_length_required('date');
    my $expire_reason = $args->get('reason');
    _validate_team_user($name);
    $expire_date = _convert_offset_to_epoch($expire_date);

    $result->data($expire_date);
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SET_EXPIRE', $name, $expire_date, $expire_reason );

    return 1;
}

=head2 cancel_expire

This function enables an expired team-user and removes any pending expire tasks for the team-user.

=head3 ARGUMENTS

=over

=item user - string
Required. The name of the team-user to cancel expiration for.

=back

=cut

sub cancel_expire ( $args, $result ) {
    _license_check($result);
    my $name = $args->get_length_required('user');
    Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'CANCEL_EXPIRE', $name );

    return 1;
}

=head2 get_team_users_with_roles_count

This function provides the count of max team users with roles
and the count of actual team users with roles.

=cut

sub get_team_users_with_roles_count ( $args, $result ) {
    _license_check($result);
    my $team_owner = $ENV{'REMOTE_USER'};
    require Cpanel::Team::Config;
    my $max_team_users_with_roles = Cpanel::Team::Config::max_team_users_with_roles_count($team_owner);

    my $final_reult = {
        used => _current_team_users_count($team_owner),
        max  => $max_team_users_with_roles
    };
    $result->data($final_reult);

    return 1;
}

sub _convert_offset_to_epoch ($date) {

    $date =~ s/^(\d+) ?days?$/time + $1 * 60 * 60 * 24/ei;
    if ( $date =~ /\D+/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The parameter “[_1]” must be either the number of days: “[_2]” or a Unix Epoch time in the future: “[_3]”.", [ 'date', '30 days', time + 60 * 60 * 24 * 30 ] );
    }
    elsif ( $date <= time ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” value must be a future date.", ['date'] );
    }

    return $date;
}

sub _validate_team_user ($team_user) {
    my $team = Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'LOAD' );
    if ( !defined $team->{users}->{$team_user} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    return 1;
}

sub _license_check ($result) {
    if ( !Cpanel::Server::Type::has_feature('teams') ) {
        die Cpanel::Exception::create( 'FeatureNotEnabled', 'The “[_1]” feature is not available. Ask your reseller about adding this feature.', ['Team Manager'] );
    }

    return $result;
}

sub _escalated_privilege_warning ($result) {
    my $locale = Cpanel::Locale->get_handle();
    $result->raw_warning( $locale->maketext("Warning: This action may result in team users gaining access to team owner level privileges.") );

    return $result;
}

sub _add_mysql_user ($team_user_info) {

    # Create a MYSQL user with team owner prefix
    require Cpanel::API;
    my $result = Cpanel::API::execute(
        'Mysql', 'create_user',
        {
            name     => $team_user_info->{name},
            password => $team_user_info->{password}
        }
    );

    # list all databases
    require Cpanel::MysqlFE::DB;
    my %dbs       = Cpanel::MysqlFE::DB::listdbs();
    my @databases = keys %dbs;

    # grant all privileges to team_user
    foreach my $db (@databases) {
        my $result = Cpanel::API::execute(
            'Mysql', 'set_privileges_on_database',
            {
                user       => $team_user_info->{name},
                database   => $db,
                privileges => 'ALL'
            }
        );

    }
    return;

}

sub _current_team_users_count ($team_owner) {
    my $team_config_file = "$Cpanel::Team::Constants::TEAM_CONFIG_DIR/$team_owner";
    return 0 if !-e $team_config_file;
    Cpanel::Autodie::open( my $FH, '<', $team_config_file );
    local $/ = undef;
    my $config = <$FH>;
    close $FH;

    my $team_users_with_roles_cnt = my @all_roles = $config =~ /^[^:]+:[^:]*:([^:]+):/gm;
    return $team_users_with_roles_cnt;
}

1;
