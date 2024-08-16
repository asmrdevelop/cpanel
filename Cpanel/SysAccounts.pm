package Cpanel::SysAccounts;

# cpanel - Cpanel/SysAccounts.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use AcctLock                             ();
use Cpanel::Autodie                      ();
use Cpanel::Mkdir                        ();
use Cpanel::Auth::Generate               ();
use Cpanel::PwCache::Validate            ();
use Cpanel::NSCD                         ();
use Cpanel::SSSD                         ();
use Cpanel::PwCache                      ();
use Cpanel::PwCache::Clear               ();
use Cpanel::OrDie                        ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::LoginDefs                    ();
use Cpanel::Validate::Username           ();
use Cpanel::Exception                    ();
use Cpanel::Transaction::File::Raw       ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Auth::Shadow                 ();

our $PASSWD_PERMS  = 0644;
our $GROUP_PERMS   = 0644;
our $SHADOW_PERMS  = 0600;
our $GSHADOW_PERMS = 0600;

our $UNLOCK      = 0;
our $KEEP_LOCKED = 1;

my $SUCCESS                        = 0;
my $EXIT_CODE_FATAL                = 1;
my $EXIT_CODE_CANNOT_OPEN          = 10;
my $EXIT_CODE_ALREADY_EXISTS_LINUX = 9;
my $EXIT_CODE_CURRENTLY_LOGGED_IN  = 8;
my $EXIT_CODE_DOES_NOT_EXIST       = 6;
my $EXIT_CODE_EXEC_FAILED          = 127;
my $EXIT_CODE_FORK_FAILED          = 128;

our $DEBUG = 0;

our $SYSTEM_SKEL_DIR = '/etc/skel';

our $PASSWD_FILE  = '/etc/passwd';
our $GROUP_FILE   = '/etc/group';
our $SHADOW_FILE  = '/etc/shadow';
our $GSHADOW_FILE = '/etc/gshadow';

=pod

=encoding utf-8

=head1 NAME

Cpanel::SysAccounts - Tools for adding, modifying, and removing system users

=head1 SYNOPSIS

    Cpanel::SysAccounts::add_system_user(
          'bob'
          'uid'    => 11111,
          'gid'    => 11111,
          'shell'  => '/bin/bash',
          'comment'=> 'test user',
          'homedir'=> '/home/bob',
          'pass'   => 'xyz123',
    );

    # By default we release the AcctLock
    Cpanel::SysAccounts::remove_system_user( 'bob', $Cpanel::SysAccounts::UNLOCK );

    # Do not release the AcctLock (useful if you are calling Whostmgr::Accounts::IdTrack::remove_id right after)
    Cpanel::SysAccounts::remove_system_user( 'bob', $Cpanel::SysAccounts::KEEP_LOCK );

    # if you're working the sudoers group
    use Cpanel::OS ();

    Cpanel::SysAccounts::add_user_to_group( Cpanel::OS::sudoers(), $user );

    Cpanel::SysAccounts::remove_user_from_group( Cpanel::OS::sudoers(), $user );

=head1 DESCRIPTION

This module provides functionality to add users, remove
user and change their groups.

=head1 WARNINGS

You must call AcctLock::acctlock() before calling add_system_user
as it does not do the locking like all other
functions in this module

=head1 METHODS

=head2 add_system_user( USER, OPTIONS... )

Add a user to the system

=head3 Arguments

Required:

  USER            - scalar:   The username to add
  OPTIONS         - hash:     A hash of options
     uid
     gid
     shell
     comment
     homedir

=head3 Return Value

=over

=item 1 on success

=back

If an error occurred the function will generate an exception.

If no password is specified, the user will be starred out (have an encoded
password of C<*>) and unable to log in.

=cut

sub add_system_user {
    my ( $user, %OPTS ) = @_;

    foreach my $required (qw(uid gid shell homedir)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !length $OPTS{$required};
    }

    my $uid          = $OPTS{'uid'};
    my $gid          = $OPTS{'gid'};
    my $shell        = $OPTS{'shell'};
    my $comment      = $OPTS{'comment'} || '';
    my $homedir      = $OPTS{'homedir'};
    my $pass         = $OPTS{'pass'};
    my $crypted_pass = $OPTS{'crypted_pass'};

    my $uid_min = Cpanel::LoginDefs::get_sys_uid_min();
    my $gid_min = Cpanel::LoginDefs::get_sys_gid_min();
    if ( $uid =~ tr{0-9}{}c || $uid < $uid_min ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The value for “[_1]” must be a whole number greater than or equal to [numf,_2].", [ "uid", $uid_min ] );
    }
    elsif ( $gid =~ tr{0-9}{}c || $gid < $gid_min ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The value for “[_1]” must be a whole number greater than or equal to [numf,_2].", [ "gid", $gid_min ] );
    }
    elsif ( ( Cpanel::PwCache::getpwnam_noshadow($user) )[0] ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The user “[_1]” already exists.", [$user] );
    }
    elsif ( ( getgrnam($user) )[0] ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The group “[_1]” already exists.", [$user] );
    }
    elsif ( $shell =~ tr{:}{} ) {
        die Cpanel::Exception::create( 'InvalidParameter', "“[_1]” is not a valid “[_2]”.", [ $shell, "shell" ] );
    }
    elsif ( $comment =~ tr{:}{} ) {
        die Cpanel::Exception::create( 'InvalidParameter', "“[_1]” is not a valid “[_2]”.", [ $comment, "comment" ] );
    }

    if ( !Cpanel::Validate::Username::is_valid_system_username($user) ) {
        die Cpanel::Exception::create( 'InvalidUsername', [ value => $user ] );
    }

    if ( !AcctLock::is_locked() ) {
        die Cpanel::Exception->create_raw("add_system_user must be called with an AcctLock");
    }

    #
    # TODO: use Cpanel::CommandQueue ?  Probably impossible to revert if this fails so
    # it might not be useful
    #
    _add_to_file( $GROUP_FILE,   $GROUP_PERMS,   "$user:x:$gid:" );
    _add_to_file( $GSHADOW_FILE, $GSHADOW_PERMS, "$user:!::" );
    _add_to_file( $PASSWD_FILE,  $PASSWD_PERMS,  "$user:x:$uid:$gid:$comment:$homedir:$shell" );
    Cpanel::OrDie::multi_return(
        sub {
            my $encoded = $crypted_pass || ( length $pass ? Cpanel::Auth::Generate::generate_password_hash( $OPTS{'pass'} ) : '*' );
            return Cpanel::Auth::Shadow::update_shadow_without_acctlock(
                $user,
                $encoded,
            );
        }
    );

    Cpanel::PwCache::Validate::invalidate( 'user', $user );           #force recache
    Cpanel::PwCache::Validate::invalidate( 'uid',  $OPTS{'uid'} );    #force recache

    Cpanel::PwCache::Clear::clear_global_cache();

    if ( !-e $homedir ) {
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $homedir, 0000 );
        Cpanel::Autodie::chown( $uid, $gid, $homedir );
        Cpanel::Autodie::chmod( homedir_perms(), $homedir );
    }

    _install_skel_dir( $OPTS{'uid'}, $OPTS{'gid'}, $homedir );

    return 1;
}

=head2 remove_system_user( USER, KEEP_LOCKED )

Remove a user from the system

=head3 Arguments

Required:

  USER            - scalar:   The username to add
  KEEP_LOCKED     - enum:     $Cpanel::SysAccounts::UNLOCK or Cpanel::SysAccounts::KEEP_LOCK
                    KEEP_LOCK will prevent the AcctLock from being released

=head3 Return Value

=over

=item 1 on success

=back

If an error occurred the function will generate an exception

=cut

sub remove_system_user {
    my ( $user, $keep_locked ) = @_;

    my ( $uid, $homedir ) = ( Cpanel::PwCache::getpwnam_noshadow($user) )[ 2, 7 ];
    if ( !$uid ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The user “[_1]” does not exist.", [$user] );
    }

    _queue_homedir_removal( $uid, $homedir );

    AcctLock::acctlock();

    local $@;
    eval {
        #
        # TODO: use Cpanel::CommandQueue ?  Probably impossible to revert if this fails so
        # it might not be useful
        #
        _remove_from_file( $PASSWD_FILE,  $PASSWD_PERMS,  $user );
        _remove_from_file( $GSHADOW_FILE, $GSHADOW_PERMS, $user );
        _remove_from_file( $SHADOW_FILE,  $SHADOW_PERMS,  $user );
        _remove_from_group_file( $GROUP_FILE, $GROUP_PERMS, $user );
    };

    my $err = $@;
    AcctLock::acctunlock() unless $keep_locked;

    Cpanel::PwCache::Validate::invalidate( 'user', $user );    #force recache
    Cpanel::PwCache::Validate::invalidate( 'uid',  $uid );     #force recache

    Cpanel::PwCache::Clear::clear_global_cache();

    require Cpanel::Quota::Clean;
    Cpanel::Quota::Clean::zero_quota($uid);

    if ($err) {
        local $@ = $err;
        die;
    }

    return 1;
}

=head2 homedir_perms()

Returns the protection mode to be used for directory permissions of users' home directories.

=cut

sub homedir_perms {
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    return $cpconf->{'acls'} ? 0750 : 0711;
}

=head2 add_user_to_group( GROUP, USER )

Adds a system user to the system group
in /etc/group

=cut

sub add_user_to_group {
    my ( $group, $user ) = @_;

    return _do_for_group(
        $group,
        sub {
            my ( $group_name, $group_passwd, $gid, @users ) = @_;
            if ( !grep { $_ eq $user } @users ) {
                push @users, $user;
            }
            return _dump_group_line( $group_name, $group_passwd, $gid, @users );
        }
    );
}

=head2 remove_user_from_group( GROUP, USER )

Removes a system user to the system group
in /etc/group

=cut

sub remove_user_from_group {
    my ( $group, $user ) = @_;

    return _do_for_group(
        $group,
        sub {
            my ( $group_name, $group_passwd, $gid, @users ) = @_;
            @users = grep { $_ ne $user } @users;
            return _dump_group_line( $group_name, $group_passwd, $gid, @users );
        }
    );
}

sub _remove_from_group_file {
    my ( $file, $perms, $user ) = @_;

    my $user_line_start = "$user:";
    my $group_regex     = qr/[:,]\Q$user\E(?:,|$)/;

    my $group_trans = Cpanel::Transaction::File::Raw->new( 'path' => $file, 'permissions' => $perms );
    my $dataref     = $group_trans->get_data();
    my @group;
    foreach my $line ( split( "\n", $$dataref ) ) {
        next if rindex( $line, $user_line_start, 0 ) == 0;
        if ( index( $line, $user ) > -1 && $line =~ $group_regex ) {
            my @LINE   = split( m{:}, $line );
            my @groups = grep { $_ ne $user } split( m{,}, $LINE[3] );
            $LINE[3] = join( ',', @groups );
            $line = join( ":", @LINE );
        }
        push @group, $line;
    }
    $$dataref = join( "\n", @group ) . "\n";
    _fail_if_empty( $file, $dataref );
    $group_trans->save_and_close_or_die();
    return 1;
}

sub _remove_from_file {
    my ( $file, $permissions, $user ) = @_;

    my $user_line_start = "$user:";
    my $trans           = Cpanel::Transaction::File::Raw->new( 'path' => $file, 'permissions' => $permissions );
    my $dataref         = $trans->get_data();
    $$dataref = join( "\n", grep { rindex( $_, $user_line_start, 0 ) != 0 } split( m{\n}, $$dataref ) ) . "\n";
    _fail_if_empty( $file, $dataref );
    $trans->save_and_close_or_die();
    return 1;
}

sub _add_to_file {
    my ( $file, $perms, $line ) = @_;

    my $group_trans = Cpanel::Transaction::File::Raw->new( 'path' => $file, 'permissions' => $perms );
    my $dataref     = $group_trans->get_data();
    _fail_if_empty( $file, $dataref );
    $$dataref .= "\n" if substr( $$dataref, -1, 1 ) ne "\n";
    $$dataref .= $line;
    $$dataref .= "\n" if substr( $line, -1, 1 ) ne "\n";
    $group_trans->save_and_close_or_die();
    return 1;
}

sub _fail_if_empty {
    my ( $file, $dataref ) = @_;
    if ( !length $$dataref ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("Refusing to modify or write empty file $file");
    }
    return;
}

sub _load_group_line {
    my ($group_line) = @_;
    my ( $group_name, $group_passwd, $gid, $user_list ) = split( m{:}, $group_line );
    my @users = split( m{,}, $user_list );
    return ( $group_name, $group_passwd, $gid, @users );
}

sub _dump_group_line {
    my ( $group_name, $group_passwd, $gid, @users ) = @_;
    return join( ':', $group_name, $group_passwd, $gid, join( ',', @users ) );
}

sub _do_for_group {
    my ( $group, $code ) = @_;

    _modify_group_file( $GROUP_FILE, $GROUP_PERMS, $group, $code ) or return;

    Cpanel::NSCD::clear_cache('group');
    Cpanel::SSSD::clear_cache();

    return 1;
}

sub _modify_group_file {
    my ( $file, $permissions, $group, $code ) = @_;

    AcctLock::acctlock();

    my $group_line_start = "$group:";
    my $trans            = Cpanel::Transaction::File::Raw->new( 'path' => $file, 'permissions' => $permissions );
    my $dataref          = $trans->get_data();
    $$dataref = join( "\n", map { rindex( $_, $group_line_start, 0 ) == 0 ? $code->( _load_group_line($_) ) : $_ } split( m{\n}, $$dataref ) ) . "\n";
    _fail_if_empty( $file, $dataref );
    my ( $status, $msg ) = $trans->save_and_close();

    AcctLock::acctunlock();

    die $msg if !$status;
    return 1;
}

sub _install_skel_dir {
    my ( $uid, $gid, $homedir ) = @_;
    my $access_ids = Cpanel::AccessIds::ReducedPrivileges->new( $uid, $gid );
    require File::Copy::Recursive;
    return File::Copy::Recursive::rcopy( "$SYSTEM_SKEL_DIR/*", $homedir );
}

sub _queue_homedir_removal {
    my ( $uid, $homedir ) = @_;
    if ( -e $homedir ) {
        require File::Basename;
        require Cpanel::Mkdir;
        my $basedir             = File::Basename::dirname($homedir);
        my $remove_homedir_path = "$basedir/.remove_homedir";
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $remove_homedir_path, 0700 );
        my $rand = rand(10000000);
        $rand = rand(10000000) while ( -e "$remove_homedir_path/${uid}_${rand}" );
        my $remove_dir = "$remove_homedir_path/${uid}_${rand}";
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $remove_dir, 0700 );
        rename $homedir, $remove_dir;
        require Cpanel::ServerTasks;
        Cpanel::ServerTasks::schedule_task( ['AccountTasks'], 5, join( ' ', 'remove_homedir', $uid, $remove_homedir_path ) );
    }
    return 1;
}

1;
