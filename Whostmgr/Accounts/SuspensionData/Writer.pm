package Whostmgr::Accounts::SuspensionData::Writer;

# cpanel - Whostmgr/Accounts/SuspensionData/Writer.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::SuspensionData::Write - Write account suspension data

=head1 SYNOPSIS

    my $wtr = Whostmgr::Accounts::SuspensionData::Write->new();

    $wtr->suspend_locked(
        'hal',
        'just because',
        { shell => '/bin/bash' },
    );

    $wtr->unsuspend('hal');

    $wtr->suspend_unlocked(
        'hal',
        'just because',
        { shell => '/bin/bash' },
    );

=cut

=head1 DESCRIPTION

This is the writer counterpart to L<Whostmgr::Accounts::SuspensionData>.

Note that this class’s methods are called as instance methods.

=cut

#----------------------------------------------------------------------

use parent qw( Whostmgr::Accounts::SuspensionData );

use Cpanel::Autodie ();

use constant _PATH_MODE      => 0710;
use constant _INFO_FILE_MODE => 0640;

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    $class->_verify_filesystem();

    my $v;
    return bless \$v, $class;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->suspend_locked( $USERNAME, $REASON, \%INFO )

Suspends the user with the given $USERNAME for the given $REASON.
The user will be marked as locked, such that only an administrator
can unsuspend the account (i.e., a non-administrator reseller cannot
unsuspend).

%INFO should normally contain C<shell>.

Nothing is returned.

B<NOTE:> This function consists of multiple discrete actions. If any of
them fails the function tries to roll back any changes, but there is a
possibility that this can leave the system in an invalid state.

=cut

sub suspend_locked ( $self, $username, $reason, $info_hr ) {
    _verify_reason($reason);

    my $newly_locked;

    _run_queue(
        [
            sub { $self->write_info( $username, $info_hr ) },
            sub { $self->_delete_info($username) },
            'delete info',
        ],
        [
            sub { $newly_locked = $self->_lock($username) },
            sub { $self->_unlock($username) if !$newly_locked },
            'unlock',
        ],
        [
            sub { $self->_write_reason( $username, $reason ) },
        ],
    );

    return;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->suspend_unlocked( $USERNAME, $REASON, \%INFO )

Like C<suspend_locked()> but marks the account as unlocked so that a
non-administrator reseller can unsuspend the account.

=cut

sub suspend_unlocked ( $self, $username, $reason, $info_hr ) {
    _verify_reason($reason);

    _run_queue(
        [
            sub { $self->write_info( $username, $info_hr ) },
            sub { $self->_delete_info($username) },
            'delete info',
        ],
        [
            sub { $self->_write_reason( $username, $reason ) },
            sub { $self->_delete_reason($username) },
            'delete reason',
        ],
        [
            sub { $self->_unlock($username) },
        ],
    );

    return;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->unsuspend( $USERNAME )

Unsuspends the user with the given $USERNAME.

B<NOTE:> The same caveats about potential invalid states as noted for
C<suspend_locked()> apply to this function as well.

=cut

sub unsuspend ( $self, $username ) {
    my $reason = $self->get_reason($username);
    my $locked;

    _run_queue(
        [
            sub { $locked = $self->_unlock($username) },
            sub { $self->_lock($username) if $locked },
            're-lock',
        ],
        [
            sub { $self->_delete_reason($username) },
            sub { $self->_write_reason( $username, $reason ) },
        ],
        [
            sub { $self->_delete_info($username) },
        ],
    );

    return;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->write_info( $USERNAME, \%INFO )

Writes $USERNAME’s suspension info out. It is assumed that $USERNAME
is already suspended; no pre-verification of that happens here.

If %INFO contains any invalid values, an exception is thrown before
any system state is altered.

=cut

sub write_info ( $self, $username, $info_hr ) {
    require Whostmgr::Accounts::SuspensionData::Storage;
    my $buffer = Whostmgr::Accounts::SuspensionData::Storage::serialize_info($info_hr);

    require Cpanel::FileUtils::Write;
    Cpanel::FileUtils::Write::overwrite(
        $self->_user_info_path($username),
        $buffer,
        {
            before_installation => sub { Cpanel::Autodie::chmod( _INFO_FILE_MODE(), $_[0] ); Cpanel::Autodie::chown( 0, _mail_gid(), $_[0] ); }
        }
    );

    return;
}

#----------------------------------------------------------------------

sub _lock ( $self, $username ) {
    require Cpanel::FileUtils::Touch;
    return Cpanel::FileUtils::Touch::touch_if_not_exists( $self->_user_lock_path($username) );
}

sub _unlock ( $self, $username ) {
    return Cpanel::Autodie::unlink_if_exists( $self->_user_lock_path($username) );
}

sub _run_queue (@queue) {
    require Cpanel::CommandQueue;

    my $cq = Cpanel::CommandQueue->new();
    $cq->add(@$_) for @queue;

    $cq->run();

    return;
}

sub _verify_reason ($reason) {

    # Sanity check
    die 'reason must be defined!' if !defined $reason;

    return;
}

sub _write_reason ( $self, $username, $reason ) {
    require Cpanel::FileUtils::Write;
    Cpanel::FileUtils::Write::overwrite( $self->_user_path($username), $reason );

    return;
}

sub _delete_reason ( $self, $username ) {
    return Cpanel::Autodie::unlink_if_exists( $self->_user_path($username) );
}

sub _delete_info ( $self, $username ) {
    return Cpanel::Autodie::unlink_if_exists( $self->_user_info_path($username) );
}

my $_cached_mail_gid;

sub _mail_gid {
    $_cached_mail_gid //= ( getgrnam('mail') )[2] // 13;
    return $_cached_mail_gid;
}

sub _verify_filesystem ($class) {
    for my $dir ( $class->_PATH(), $class->_INFO_PATH() ) {
        my @stat_ar = stat($dir);
        if ( !-d _ ) {
            Cpanel::Autodie::mkdir( $dir, $class->_PATH_MODE() );
            @stat_ar = stat($dir);
        }
        if ( $class->_PATH_MODE() != ( $stat_ar[2] & 0777 ) ) {
            Cpanel::Autodie::chmod( $class->_PATH_MODE(), $dir );
        }
        if ( _mail_gid() != $stat_ar[5] ) {
            Cpanel::Autodie::chown( 0, _mail_gid(), $dir );
        }
    }

    return;
}

1;
