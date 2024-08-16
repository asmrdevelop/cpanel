package Cpanel::AccessIds::ReducedPrivileges;

# cpanel - Cpanel/AccessIds/ReducedPrivileges.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug                ();
use Cpanel::AccessIds::Utils     ();
use Cpanel::AccessIds::Normalize ();

our $PRIVS_REDUCED = 0;

# WARNING: This code is security-sensitive. Be careful how you use it.  In
# particular, once privileges have been temporarily reduced, anyone can restore
# the privileges if we have not done a fork/exec.
#
# Therefore, this code provides a simple way for trusted code to temporarily
# lower privileges, perform some action, and return to higher privileges. This
# is great for simple filesystem changes and such.
#
# Running arbitrary code would allow for privilege escalation attacks that
# cannot be prevented.
#
# Be careful. You have been warned.

# OO Guard interface.
sub new {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $class = shift;

    if ( $class ne __PACKAGE__ ) {
        Cpanel::Debug::log_die("Attempting to drop privileges as '$class'.");
    }

    my ( $uid, @gids ) = Cpanel::AccessIds::Normalize::normalize_user_and_groups(@_);

    _allowed_to_reduce_privileges();

    _prevent_dropping_to_root( $uid, @gids );

    # Save old values.
    my $self = {
        'uid'     => $>,
        'gid'     => $),
        'new_uid' => $uid,
        'new_gid' => join( q< >, @gids ),
    };

    _reduce_privileges( $uid, @gids );

    $PRIVS_REDUCED = 1;

    return bless $self;
}

sub DESTROY {
    my ($self) = @_;

    _allowed_to_restore_privileges( $self->{'new_uid'}, $self->{'new_gid'} );

    return _restore_privileges( $self->{'uid'}, $self->{'gid'} );
}

# Call anonymous sub interface
#
#Args: The coderef may be in any position, but user must be before group.
sub call_as_user {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my ( $code, $uid, $gid, @supplemental_gids ) = Cpanel::AccessIds::Normalize::normalize_code_user_groups(@_);

    _prevent_dropping_to_root( $uid, $gid );

    if ( !$code ) {
        Cpanel::Debug::log_die("No code reference supplied.");
    }

    _allowed_to_reduce_privileges();

    my ( $saved_uid, $saved_gid ) = ( $>, $) );

    _reduce_privileges( $uid, $gid, @supplemental_gids );

    local $PRIVS_REDUCED = 1;

    my ( $scalar, @list );

    if (wantarray) {    #list context
        @list = eval { $code->(); };
    }
    elsif ( defined wantarray ) {    #scalar context
        $scalar = eval { $code->(); };
    }
    else {                           #void context
        eval { $code->(); };
    }

    my $ex = $@;
    _restore_privileges( $saved_uid, $saved_gid );

    die $ex if $ex;
    return wantarray ? @list : $scalar;
}

# Utility routines.

# Verify real and effective UID.
sub _allowed_to_reduce_privileges {
    if ( $< != 0 ) {
        Cpanel::Debug::log_die("Attempting to drop privileges as a normal user with RUID $<");
    }

    if ( $> != 0 ) {
        Cpanel::Debug::log_die("Attempting to drop privileges as a normal user with EUID $>");
    }

    return 1;
}

# Reduce privileges (only called if privileges are right)
sub _reduce_privileges {
    my ( $uid, $gid, @supplemental_gids ) = @_;

    Cpanel::AccessIds::Utils::set_egid( $gid, @supplemental_gids );
    Cpanel::AccessIds::Utils::set_euid($uid);

    return 1;
}

sub _prevent_dropping_to_root {

    #my (@uids_and_gids) = @_;

    if ( grep { !$_ } @_ ) {
        Cpanel::Debug::log_die("Attempting to drop privileges to root.");
    }

    return 1;
}

# Verify real id is root and effective uid and gid are expected.
sub _allowed_to_restore_privileges {
    my ( $uid, $gid ) = @_;

    # None of these should ever fail, but I'm checking for them anyway. If any
    # failures actually occurred at this point it would be extremely hard to
    # troubleshoot without these messages.
    if ( $< != 0 ) {
        Cpanel::Debug::log_die("Attempting to restore privileges as a normal user with RUID $<");
    }

    if ( $> != $uid ) {
        Cpanel::Debug::log_warn("EUID ($>) does not match expected reduced user ($uid)");
    }

    # Don't test the supplementary group ids
    my ( $first_egid, $first_given_gid ) = ( $), $gid );
    $_ = ( split m{ } )[0] for ( $first_egid, $first_given_gid );

    if ( int $first_egid != int $first_given_gid ) {
        Cpanel::Debug::log_warn("EGID ($)) does not match expected reduced user ($gid)");
    }
}

# Restore privileges to saved values.
# Note: Cpanel::SafeRun::Object calls
# this but the _ was not removed because
# we do not want any other calls to do so
sub _restore_privileges {
    my ( $saved_uid, $saved_gid ) = @_;

    Cpanel::AccessIds::Utils::set_euid($saved_uid);
    Cpanel::AccessIds::Utils::set_egid( split m{ }, $saved_gid );

    $PRIVS_REDUCED = 0;

    return 1;
}

1;
