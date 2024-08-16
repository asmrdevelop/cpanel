package Cpanel::CustInfo::Validate;

# cpanel - Cpanel/CustInfo/Validate.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::CustInfo::Model ();
use Cpanel::Exception       ();
use Cpanel::LoadModule      ();

=head1 NAME

Cpanel::CustInfo::Validate

=head1 DESCRIPTION

Provides validation services specific to the Cpanel::CustInfo::*  modules.

=head1 FUNCTIONS

=head2 Cpanel::CustInfo::validate_not_root_or_die

Checks if the user is root and dies if it is.

=head3 ARGUMENTS

    n/a

=head3 THROWS

    string - if running as root.

=cut

sub validate_not_root_or_die {
    die "Only call as user, not as root!" if !$>;
    return;
}

=head2 Cpanel::CustInfo::validate_fields_or_die

Checks if the user is root and dies if it is.

=head3 ARGUMENTS

    hash - contains the fields to save. It will verify if only known fields are present by checking the
           key names. If there are unknown keys, then an exception is thrown.

=head3 THROWS

    Cpanel::Exception::InvalidParameter

=cut

sub validate_fields_or_die {
    my (%opts) = @_;

    my $valid_fields = Cpanel::CustInfo::Model::get_all_possible_contact_fields();

    my @unknown = grep { !exists $valid_fields->{$_} } keys %opts;
    if (@unknown) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The following [numerate,_1,parameter is,parameters are] invalid: [join,~, ,_2]', [ scalar(@unknown), \@unknown ] );
    }

    # CONSIDER: Adding type checking to the validation

    return;
}

=head2 Cpanel::CustInfo::validate_not_demo_mode_or_die

Checks if the user is a demo user

=head3 ARGUMENTS

    n/a

=head3 THROWS

    Cpanel::Exception::ForbiddenInDemoMode

=cut

sub validate_not_demo_mode_or_die {
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        die Cpanel::Exception::create('ForbiddenInDemoMode');
    }
    return;
}

=head2 Cpanel::CustInfo::validate_cpanel_account_or_die

Checks if the user and cpanel user match. Used for operations that should only work for the loggedin cpanel user.

=head3 ARGUMENTS

    username   - string - user to check
    cpusername - string - optional user we are running as, defaults to the running Cpanel::user.

=head3 THROWS

    Cpanel::Exception::InvalidUsername

=cut

sub validate_cpanel_account_or_die {
    my ( $username, $cpusername ) = @_;
    $cpusername ||= $Cpanel::user;
    die Cpanel::Exception::create( 'InvalidUsername', [ value => $username ] ) if !$cpusername || !$username || $cpusername ne $username;
    return;
}

=head2 Cpanel::CustInfo::validate_subaccount_or_email_account_or_die

Checks if the user is a valid subaccount or email account for the cpanel user. Used for operations
that should only work for existing subaccounts for the current cpanel user.

=head3 ARGUMENTS

    username   - string - user to check, defaults to the authenticated user

=head3 THROWS

    Cpanel::Exception::InvalidUsername

=cut

sub validate_subaccount_or_email_account_or_die {
    my ($username) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::UserManager::Storage') if !$INC{'Cpanel/UserManager/Storage.pm'};

    $username ||= $Cpanel::authuser || '';

    my ( $mailbox, $domain ) = split( '@', $username, 2 );
    my $user = Cpanel::UserManager::Storage::lookup_user( username => $mailbox, domain => $domain );

    Cpanel::LoadModule::load_perl_module('Cpanel::Email::Exists') if !$INC{'Cpanel/Email/Exists.pm'};

    # For email accounts not created via the User Manager, we need
    # to also check and see if there is only email account setup.
    # This uses the same existence checking use by Cpanel::API::Email
    # system.
    if ( !$user && !Cpanel::Email::Exists::pop_exists( $mailbox, $domain ) ) {
        die Cpanel::Exception::create( 'InvalidUsername', [ value => $username ] );
    }

    return;
}

=head2 Cpanel::CustInfo::validate_cpanel_account_or_die

Checks if the user and cpanel user match. Used for operations that should only work for the loggedin cpanel user.

=head3 ARGUMENTS

    username   - string  - user to check
    is_virtual - boolean - if truthy, the username is a virtual account, otherwise, its represents a cpanel account.
    cpusername - string  - optional user we are running as, defaults to the running Cpanel::user.

=head3 THROWS

    Cpanel::Exception::InvalidUsername

=cut

sub validate_account_or_die {
    my ( $username, $is_virtual, $cpusername ) = @_;
    $cpusername ||= $Cpanel::user;
    if ( $username =~ /\@/ && !$is_virtual ) {
        validate_team_account_or_die($username);
        return;
    }
    elsif ( !$is_virtual ) {
        validate_cpanel_account_or_die( $username, $cpusername );
    }
    else {
        validate_subaccount_or_email_account_or_die($username);
    }
    return;
}

=head2 Cpanel::CustInfo::validate_team_account_or_die

Checks if the user is a valid team user.

=head3 ARGUMENTS

    username   - string - user to check, defaults to the authenticated user

=head3 THROWS

    Cpanel::Exception::InvalidUsername

=cut

sub validate_team_account_or_die {
    my ($username) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Team::Config') if !$INC{'Cpanel/Team/Config.pm'};

    # get_team_user throws exception on invalid team user.
    Cpanel::Team::Config::get_team_user($username);

    return;
}
1;
