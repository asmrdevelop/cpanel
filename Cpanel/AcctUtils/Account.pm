package Cpanel::AcctUtils::Account;

# cpanel - Cpanel/AcctUtils/Account.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache ();

our $USERS_DIR = '/var/cpanel/users';

=encoding utf-8

=head1 NAME

Cpanel::AcctUtils::Account - account existence subroutines

=head1 SYNOPSIS

    use Cpanel::AcctUtils::Account;

    my $exists = Cpanel::AcctUtils::Account::accountexists($user);
    Cpanel::AcctUtils::Account::accountexists_or_die($user); #throws Exception
    my @existingparts = Cpanel::AcctUtils::Account::get_existing_account_parts($user);

=head1 DESCRIPTION

account existence subroutines

=cut

=head2 accountexists

Determine whether a system account exists

=over 2

=item Input

=over 3

=item C<SCALAR>

    $user - The user you want to test the existence of

=back

=item Output

=over 3

=item C<SCALAR>

    returns 1 or 0 depending on existence of an account on the system

=back

=back

=cut

sub accountexists {

    # Avoid hitting the filesystem if we can:
    return 1 if $_[0] && $_[0] eq 'root';

    return length( scalar Cpanel::PwCache::getpwnam_noshadow( $_[0] ) ) ? 1 : 0;
}

=head2 get_existing_account_parts

Get the parts of an account that exist on a system

=over 2

=item Input

=over 3

=item C<SCALAR>

    $user - The user you want to test the existence of

=back

=item Output

=over 3

=item C<ARRAYREF>

    returns an array of existing major user account parts including:
    - a system account
    - a userdata folder
    - a users file

=back

=back

=cut

sub get_existing_account_parts {
    my ($user) = @_;

    my @existing_parts = ();

    push( @existing_parts, "$USERS_DIR/$user" ) if -e "$USERS_DIR/$user";

    push( @existing_parts, "system user “$user”" ) if accountexists($user);

    require Cpanel::Config::userdata::Constants;
    push( @existing_parts, "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user" ) if -e "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user";

    return \@existing_parts;
}

=head2 accountexists_or_die

Throws an exception if a user does not exist

=over 2

=item Input

=over 3

=item C<SCALAR>

    $user - The user you want to test the existence of

=back

=item Output

=over 3

=item C<SCALAR>

    returns 1 if user exists

=back

=item Exceptions

=over 3

=item C<UserNotFound>

    throws a UserNotFound exception if system user does not exist

=back

=back

=cut

sub accountexists_or_die {
    accountexists( $_[0] ) or do {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'UserNotFound', [ name => $_[0] ] );
    };
    return 1;
}

1;
