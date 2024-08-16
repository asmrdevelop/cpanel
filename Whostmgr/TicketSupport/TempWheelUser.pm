
# cpanel - Whostmgr/TicketSupport/TempWheelUser.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::TicketSupport::TempWheelUser;

use strict;
use warnings;
use Cpanel::Auth::Generate   ();
use Cpanel::Auth::Shadow     ();
use Cpanel::Exception        ();
use Cpanel::FileUtils::Write ();
use Cpanel::OS               ();
use Cpanel::Rand::Get        ();
use Cpanel::Sys::Escalate    ();
use Cpanel::Sys::User        ();
use Cpanel::Locale 'lh';

=head1 NAME

Whostmgr::TicketSupport::TempWheelUser

=head1 DESCRIPTION

This module manages temporary wheel users created during the ticket grant process (in the
Create Support Ticket application in WHM) for use on systems that do not permit root logins
over SSH but do permit wheel users to use sudo.

=head1 FUNCTIONS

=head2 get(TICKET_ID)

Given a numeric ticket id, TICKET_ID, returns the username of the temporary wheel user.

If such a user already exists for the ticket in question, it will be reused. Otherwise,
a new user will be created.

=head3 Arguments

- TICKET_ID - Number - The ticket id from the ticket system. This will be embedded into the username.

=head3 Returns

(String) The username of the temporary wheel user

(String) The password of the temporary wheel user

=head3 Throws

Known exceptions:

- If the system is not configured to allow wheel users to use sudo.

- If the user creation fails.

=cut

sub get {
    my ($ticket_id) = @_;
    _validate_ticket_id( $ticket_id, 'get' );

    my $existing = _find($ticket_id);
    if ($existing) {
        my ($password) = _set_password_for_user( $existing->login );
        return $existing->login, $password;
    }

    my $name = _make_name($ticket_id);

    my $user_obj = Cpanel::Sys::User->new(
        login => $name,
        group => Cpanel::OS::sudoers(),
        shell => '/bin/bash',
    );
    eval { $user_obj->create };
    if ( my $exception = $@ ) {
        die Cpanel::Exception::create(
            'TicketSupport::TempWheelUser',
            [
                operation => 'get',
                errortype => 'creation failed',
                errormsg  => $exception,
            ]
        );
    }

    my ($password) = _set_password_for_user($name);

    if ( !Cpanel::Sys::Escalate::sudo_allowing_wheel_users() ) {
        _add_temp_sudoers_entry( $name, $ticket_id );
    }

    return $name, $password;
}

sub _set_password_for_user {
    my ($user) = @_;

    my $password = Cpanel::Rand::Get::getranddata( 64, [ 'a' .. 'z', 'A' .. 'Z', 0 .. 9, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')' ] );
    $password =~ m/^[a-zA-Z0-9\!\@\#\$\%\^\&\*\(\)]{64}$/ or die;    # just in case getranddata stops working; should never happen

    # Setting the password via Cpanel::Auth::Shadow is slightly more secure than setting it as
    # part of the user creation by Cpanel::Sys::User, which would pass the digest as an argument
    # to useradd, therefore exposing it in the process table.

    my $password_hash = Cpanel::Auth::Generate::generate_password_hash($password) || die 'empty password field is not safe';
    my ( $status, $statusmsg ) = Cpanel::Auth::Shadow::update_shadow( $user, $password_hash );
    if ( !$status ) {
        die Cpanel::Exception::create(
            'TicketSupport::TempWheelUser',
            [
                operation => 'get',
                errortype => 'password',
                errormsg  => $statusmsg,
            ]
        );
    }

    return $password;
}

=head2 cleanup(TICKET_ID)

Given a numeric ticket id, TICKET_ID, removes the temporary wheel user, if any, associated
with that ticket.

=head3 Arguments

- TICKET_ID - Number - The ticket id from the ticket system. This will be embedded into the username.

=head3 Returns

True - If the user was found and successfully removed

False - If the user was not found

=head3 Throws

This function will throw an exception if the user was found but could not be removed for some reason.

=cut

sub cleanup {
    my ($ticket_id) = @_;

    _validate_ticket_id( $ticket_id, 'cleanup' );

    _remove_temp_sudoers_entry_if_present($ticket_id);

    my $existing = _find($ticket_id);

    if ($existing) {
        $existing->delete( force => 1, remove => 1 );
        return 1;
    }

    return 0;
}

=head2 exists(TICKET_ID)

Given a numeric ticket id, TICKET_ID, determins if the related wheel user exists on the system.

=head3 Arguments

- TICKET_ID - Number - The ticket id from the ticket system.

=head3 Returns

True - If the user was found to exist

False - If the user was not found to exist

=cut

sub exists {
    my ($ticket_id) = @_;

    _validate_ticket_id( $ticket_id, 'exists' );

    my $existing = _find_name($ticket_id);
    return $existing ? 1 : 0;
}

=head2 identify_ticket(USERNAME)

Given a username (whether a temporary wheel user or not), identifies the ticket, if any, associated with it.

=head3 Arguments

USERNAME - The username as it appears in the passwd file

=head3 Returns

If the user in question is a temporary wheel user, returns the ticket id with which it is associated.

Otherwise, returns nothing.

=cut

sub identify_ticket {
    my ($username) = @_;
    if ( $username =~ /^cp([0-9]+)\.ssh$/ ) {
        return $1;
    }
    return;
}

# _make_name
#
# Arguments:
# - The numeric ticket id
#
# Returns:
# - The wheel user name for the ticket.
#
sub _make_name {
    my ($ticket_id) = @_;
    return sprintf( 'cp%s.ssh', $ticket_id );
}

# _find_name
#
# Arguments:
# - The numeric ticket id
#
# Returns:
# - The wheel user name for the ticket if it already exists.
#
sub _find_name {
    my ($ticket_id) = @_;

    my $expected_username = _make_name($ticket_id);
    my $found             = _user_exists($expected_username);
    return $found ? $expected_username : undef;
}

# _find
#
# Arguments:
# - The numeric ticket id
#
# Returns:
# - If the user in question already exists, a Cpanel::Sys::User object representing that user.
#   Important note: The object will not have all the correct attributes of the user because
#   Cpanel::Sys::User doesn't actually load these. We just need the Cpanel::Sys::User object
#   so we can do a delete.
# - Otherwise, undef
sub _find {
    my ($ticket_id) = @_;

    if ( my $existing = _find_name($ticket_id) ) {
        return Cpanel::Sys::User->new( login => $existing );
    }

    return;
}

# _validate_ticket_id
#
# Arguments:
# - The numeric ticket id
#
# Returns:
# - If the ticket id is defined and a valid number.
#
# Dies:
# - If the ticket id is not defined or is not a number
#
sub _validate_ticket_id {
    my ( $ticket_id, $operation_name ) = @_;
    if ( !$ticket_id || $ticket_id !~ /^[0-9]+$/ ) {
        die Cpanel::Exception::create(
            'TicketSupport::TempWheelUser',
            [
                operation => $operation_name,
                errortype => 'argument',
                errormsg  => 'you must provide a ticket id',    # this is a developer-only error; do not translate
            ]
        );
    }
    return;
}

sub _add_temp_sudoers_entry {
    my ( $username, $ticket_id ) = @_;

    my $sudoers_d = '/etc/sudoers.d';
    mkdir $sudoers_d if !-e $sudoers_d;
    my $sudoers_file = $sudoers_d . '/ticket' . $ticket_id;

    my $sudoers_line = sprintf( "%s ALL=(ALL) ALL\n", $username );
    Cpanel::FileUtils::Write::overwrite( $sudoers_file, $sudoers_line, 0440 );

    return;
}

sub _remove_temp_sudoers_entry_if_present {
    my ($ticket_id) = @_;

    my $sudoers_file = '/etc/sudoers.d/ticket' . $ticket_id;
    unlink $sudoers_file if -e $sudoers_file;

    return;
}

sub _user_exists {
    my ($user) = @_;
    return getpwnam($user) ? 1 : 0;
}

1;
