package Cpanel::ForcePassword;

# cpanel - Cpanel/ForcePassword.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                    ();
use Cpanel::SafeFile                     ();
use Cpanel::Logger                       ();
use Cpanel::PwCache                      ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Fcntl                        ();
use Cpanel::ForcePassword::Unforce       ();
use Cpanel::Config::LoadUserOwners       ();
use Whostmgr::Quota::User                ();

use Try::Tiny;

my $the_logger = Cpanel::Logger->new();

sub new {
    my ( $class, $args ) = @_;

    if ( ref $args ne 'HASH' ) {
        $the_logger->warn("Parameter to new not a hashref.\n");
        return;
    }
    if ( !exists $args->{'user'} ) {
        $the_logger->warn("Missing required 'user' parameter.\n");
        return;
    }
    my $user = $args->{'user'};
    my $obj  = { 'user' => $user };
    if ( $user =~ /@/ ) {
        if ( !exists $args->{'homedir'} && !exists $args->{'sysuser'} && $< == 0 ) {
            $the_logger->warn("Missing required 'homedir' parameter.\n");
            return;
        }
        $obj->{'sysuser'} = $args->{'sysuser'};
        if ( $< != 0 && !$obj->{'sysuser'} ) {
            $obj->{'sysuser'} = ( Cpanel::PwCache::getpwuid($<) )[0];
        }
    }
    else {
        $obj->{'sysuser'} = $user;
    }

    # Use supplied home dir, or the homedir of the sysuser
    $obj->{'homedir'} = $args->{'homedir'}
      || ( Cpanel::PwCache::getpwnam( $obj->{'sysuser'} ) )[7];

    return bless $obj, $class;
}

sub force_password_change {
    my ($self) = @_;
    if ( !defined $self->{'sysuser'} ) {
        $the_logger->warn("Unable to force password change without a 'sysuser'\n");
        return;
    }
    return $self->_real_force_password_change if $< != 0;

    # Temporarily change the UID/GID just long enough to update the file.
    # Using Cpanel::AccessIds::SetUids::setuids would require a fork for this call. That gets
    # expensive in the WHM interface.
    my $ret;
    return $ret if eval {
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub { $ret = $self->_real_force_password_change() },
            $self->{'sysuser'},
        );
        $ret;
    };
    $the_logger->warn("Unable to change force password status. Issue could be caused by homedir/.cpanel permissions or disk quota.\n");
    return;
}

sub _real_force_password_change {
    my ($self) = @_;
    my $file = $self->_find_password_change_file();

    my $cpaneldir = $self->_cpanel_dir;
    if ( !-d $cpaneldir ) {
        require Cpanel::SafeDir::MK;
        Cpanel::SafeDir::MK::safemkdir($cpaneldir) or return;
    }
    my $fh;
    my $lock = Cpanel::SafeFile::safesysopen( $fh, $file, Cpanel::Fcntl::or_flags(qw( O_RDWR O_CREAT )) );
    unless ( defined $lock ) {
        $the_logger->warn("Unable to lock/open '$file': $!\n");
        return;
    }
    my @users = <$fh>;

    # Put the line ending on the username for comparison. That avoids changing
    # all of the lines and then re-adding the end of line when we write them
    # out again.
    my $match = $self->{'user'} . $/;
    if ( !grep { $_ eq $match } @users ) {

        # Add the flag
        push @users, $match;
        seek( $fh, 0, 0 );

        # Entries MUST be written to the file in sorted order.
        print {$fh} sort @users;
        truncate( $fh, tell($fh) );
    }
    return Cpanel::SafeFile::safeclose( $fh, $lock );
}

sub unforce_password_change {
    my ($self) = @_;
    return unless -d $self->_cpanel_dir();
    my $file = $self->_find_password_change_file();
    return unless -f $file;

    return Cpanel::ForcePassword::Unforce::unforce_password_change( $self->{'sysuser'}, $self->{'user'}, $self->{'homedir'} );
}

# Very important that this method remain synchronized with Cpanel::ForcePassword::Check::need_password_change
# This is the correct, but slow, version of that method.
sub need_password_change {
    my ($self) = @_;

    return unless -d $self->_cpanel_dir();
    my $file = $self->_find_password_change_file();
    return unless -f $file;

    my ( $fh, $lock );
    my $result = undef;

    try {
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub { $lock = Cpanel::SafeFile::safeopen( $fh, '<', $file ); },
            $self->{'user'}
        );

        # What can happen here?
        # - The operation can succeed. $lock (and $fh) are set. Proceed.
        # - The operation can fail. $lock will not be set. Warn and return empty-handed.
        # - The operation can die. Check if the exception is FileCreateError and errno is EDQUOT.
        #   If not, treat as if failed in the previous way.
        #   If so, transfer control to ::Check::need_password_change().

        if ( defined $lock ) {
            while (<$fh>) {
                chomp;
                $result = $self->{'user'} eq $_;

                # Since the force password file is written out in sorted order, we can
                # keep looking if current user is greater than entry.
                last if $self->{'user'} le $_;
            }
            Cpanel::SafeFile::safeclose( $fh, $lock );
        }
        else {
            # Unify error handling code path:
            die Cpanel::Exception::create( 'IO::FileOpenError', [ 'path' => $file, 'error' => $!, 'mode' => '<' ] );
        }
    }
    catch {
        my $ex = $_;

        if ( eval { $ex->isa('Cpanel::Exception::IO::FileCreateError') && $ex->error_name() eq 'EDQUOT' } ) {
            require Cpanel::ForcePassword::Check;
            $result = Cpanel::ForcePassword::Check::need_password_change( $self->{'user'}, $self->{'homedir'} );
        }
        else {
            $the_logger->warn( Cpanel::Exception::get_string($ex) );
        }
    };

    return $result;
}

sub _cpanel_dir {
    my ($self) = @_;
    return "$self->{'homedir'}/.cpanel";
}

sub _find_password_change_file {
    my ($self) = @_;
    return $self->{'file'} if $self->{'file'};

    $self->{'file'} = $self->_cpanel_dir() . '/passwordforce';
    return $self->{'file'};
}

sub get_force_password_flags {
    return ( get_force_password_flags_picky( \@_ ) )[0];
}

sub get_force_password_flags_picky {
    my ( $users_ar, $opts ) = @_;
    my ( $fp, %users, %failures );

    foreach my $u (@$users_ar) {
        $fp = Cpanel::ForcePassword->new( { 'user' => $u } );
        if ( defined $fp ) {
            $users{$u} = $fp->need_password_change() || 0;
        }
        else {
            my $error = "Unable to query user '$u'";
            $the_logger->warn($error);
            $failures{$u} = $error;
            last if $opts->{'stop_on_failure'};
        }
    }
    return ( \%users, \%failures );
}

sub update_force_password_flags {
    my ($successes_ar) = update_force_password_flags_picky(shift);
    return ref $successes_ar eq 'ARRAY' ? @$successes_ar : ();
}

sub _build_failure_msg {
    my ( $user, $verb, $over_quota ) = @_;
    my $failure_prefix = "Unable to $verb forced password change for user '$user'; ";

    if ( !$over_quota ) {
        return $failure_prefix . "check the system log for details.";
    }
    else {
        return $failure_prefix . "'$user' is over disk quota. Please disable the quota and try again. Quota may be reenabled after the user has reset their password.";
    }
}

sub update_force_password_flags_picky {
    my ( $users_hr, $opts ) = @_;
    my ( $u, $flag, $fp, $success, @successes, %failures );

    while ( ( $u, $flag ) = each %{$users_hr} ) {
        $fp = Cpanel::ForcePassword->new( { 'user' => $u } );
        if ( defined $fp ) {
            $success = $flag ? $fp->force_password_change() : $fp->unforce_password_change();
            if ($success) {
                push @successes, $u;
            }
            else {
                my $user_quota_data = Whostmgr::Quota::User::get_users_quota_data( $u, { include_mailman => 0, include_sqldbs => 0 } );
                my $over_quota      = $user_quota_data->{'bytes_remain'} == 0;
                my $verb            = $flag ? 'set' : 'unset';

                $failures{$u} = _build_failure_msg( $u, $verb, $over_quota );

                last if $opts->{'stop_on_failure'};
            }
        }
        else {
            my $reason = "Unable to change user '$u'";
            $failures{$u} = $reason;
            $the_logger->warn($reason);
            last if $opts->{'stop_on_failure'};
        }
    }

    return ( \@successes, \%failures );
}

sub _api2_get_force_password_flags {
    my %OPTS = @_;
    require Cpanel::Config::Users;

    # Find owner and create actual list of users to check.
    my $users;
    if ( $OPTS{'users'} ) {
        $users = [ split /,/, $OPTS{'users'} ];
    }
    elsif ( $OPTS{'owner'} ) {
        my $owners = Cpanel::Config::LoadUserOwners::loadtrueuserowners();
        $users = $owners->{ $OPTS{'owner'} };
    }
    else {
        $users = [ Cpanel::Config::Users::getcpusers() ];
    }
    return [ get_force_password_flags( @{$users} ) ];
}

sub _api2_update_force_password_flags {
    my %OPTS = @_;

    my @users = update_force_password_flags( \%OPTS );

    return [ { 'success' => ( keys %OPTS == @users ), 'updated' => \@users } ];
}

our %API = (
    'get_force_password_flags' => {
        'func'     => '_api2_get_force_password_flags',
        allow_demo => 1,
    },
    'update_force_password_flags' => {
        'func'     => '_api2_update_force_password_flags',
        allow_demo => 1,
    },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;    # Magic true value required at end of module
