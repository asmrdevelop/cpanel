package Whostmgr::Accounts::SuspensionData;

# cpanel - Whostmgr/Accounts/SuspensionData.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::SuspensionData - Read access to account suspension data

=head1 SYNOPSIS

    my $is_suspended = Whostmgr::Accounts::SuspensionData->exists('hal');
    my $is_locked = Whostmgr::Accounts::SuspensionData->locked('hal');

    my $why = Whostmgr::Accounts::SuspensionData->get_reason('hal');
    my $info_hr = Whostmgr::Accounts::SuspensionData->get_info('hal');

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie ();

use constant _ENOENT => 2;

# overridden or referenced in tests
use constant {
    _PATH      => '/var/cpanel/suspended',
    _INFO_PATH => '/var/cpanel/suspendinfo',
};

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 $reason = I<CLASS>->get_reason( $USERNAME )

Retrieves the reason why $USERNAME is suspended. If the user isn’t suspended,
undef is returned.

(Note that $reason may be any string, including empty.)

=cut

sub get_reason ( $class, $username ) {
    require Cpanel::LoadFile;
    return Cpanel::LoadFile::load_if_exists( $class->_user_path($username) );
}

#----------------------------------------------------------------------

=head2 $yn = I<CLASS>->exists( $USERNAME )

Whether the $USERNAME exists in the datastore—i.e., whether the user
is suspended or not.

This is a bit quicker than C<get_reason()> if you don’t care about
specifically I<why> the user is suspended.

=cut

sub exists ( $class, $username ) {
    return Cpanel::Autodie::exists( $class->_user_path($username) );
}

#----------------------------------------------------------------------

=head2 $yn = I<CLASS>->locked( $USERNAME )

Whether the $USERNAME exists in the datastore—i.e., whether the user
is suspended or not.

=cut

sub locked ( $class, $username ) {
    return Cpanel::Autodie::exists( $class->_user_lock_path($username) );
}

#----------------------------------------------------------------------

=head2 $info_hr = I<CLASS>->get_info( $USERNAME )

Returns a reference to the key/value information that was submitted
with the account suspension.

Currently the items that regularly go in here are:

=over 4

=item C<shell>

The shell that the user was configured to use before suspension

=item C<leave-ftp-accts-enabled>

Boolean indicating whether the FTP accounts associated with the cPanel account
should be left unsuspended or not.

=back

=cut

sub get_info ( $class, $username ) {
    require Cpanel::LoadFile;
    my $info = Cpanel::LoadFile::load_if_exists( $class->_user_info_path($username) );

    if ( defined $info ) {
        require Whostmgr::Accounts::SuspensionData::Storage;
        $info = Whostmgr::Accounts::SuspensionData::Storage::parse_info($info);
    }

    return $info;
}

#----------------------------------------------------------------------

sub _user_path ( $class, $username ) {
    return $class->_PATH() . "/$username";
}

sub _user_info_path ( $class, $username ) {
    return $class->_INFO_PATH() . "/$username";
}

sub _user_lock_path ( $class, $username ) {
    return $class->_user_path($username) . '.lock';
}

1;
