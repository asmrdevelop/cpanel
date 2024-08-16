package Cpanel::Sys::User;

# cpanel - Cpanel/Sys/User.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule         ();
use Cpanel::SafeRun::Errors    ();
use Cpanel::PwCache::Clear     ();
use Cpanel::AcctUtils::Account ();
use AcctLock                   ();

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::Sys::User - Tools for manipulating system users

=head1 SYNOPSIS

    use Cpanel::Sys::User;

    my $user_1 = Cpanel::Sys::User->new( login => $user_name_1, group => $group_name_1 );


=head1 DESCRIPTION

This module calls the system password utilities to modify
users.  At some point it will be a wrapper around
Cpanel::SysAccounts in order to avoid the known issues
with the system tools.

=cut

my @attributes = qw/login passwd uid gid group password quota comment basedir homedir permissions owner shell is_system_account create_home force/;
my $initialized;

sub new {
    my ( $class, %opts ) = @_;

    my $self = {%opts};

    my $defaults = {
        'quota'             => 0,
        'is_system_account' => 0,
        'create_home'       => 1,
        'shell'             => '/sbin/nologin'
    };

    foreach my $setting ( keys %$defaults ) {
        $self->{$setting} = $defaults->{$setting} if !defined $self->{$setting};
    }

    die 'attribute "login" is required to be set' unless defined $self->{login};

    # default owner is the user himself
    $self->{owner} ||= $self->{login} . ':' . $self->{login};
    $self->{group} ||= $self->{login};

    if ( !$initialized ) {

        # TODO case 63683: factorize that code in a Simple::Accessor class
        foreach my $attribute (@attributes) {

            my $accessor = __PACKAGE__ . "::$attribute";
            no strict 'refs';
            *$accessor = sub {
                my ( $self, $v ) = @_;
                $self->{$attribute} = $v if defined $v;
                return $self->{$attribute};
            }
        }
        $initialized = 1;
    }

    return bless $self, $class;
}

# binaries: can be improved depending on the system or mocked when testing
sub _system_useradd {
    my $bin = '/usr/sbin/useradd';
    -x $bin or die "Do not know how to add a user on this system.";
    return $bin;
}

sub _system_userdel {
    my $bin = '/usr/sbin/userdel';
    -x $bin or die "Do not know how to delete a user on this system.";
    return $bin;
}

sub _system_groupdel {
    my $bin = '/usr/sbin/groupdel';
    -x $bin or die "Do not know how to delete a group on this system.";
    return $bin;
}

# public methods

sub set_quota {
    my ( $self, $quota ) = @_;

    $quota = $self->quota() unless defined $quota;
    my $login = $self->login() or die "no login defined";

    my $err;
    Cpanel::LoadModule::load_perl_module('Cpanel::Quota::Blocks');
    Cpanel::LoadModule::load_perl_module('Cpanel::Quota::Common');
    my $blocks = $quota * $Cpanel::Quota::Common::MEGABYTES_TO_BLOCKS;
    try {
        'Cpanel::Quota::Blocks'->new( { skip_conf_edit => 1 } )->set_user($login)->set_limits_if_quotas_enabled( { soft => $blocks, hard => $blocks } );
    }
    catch {
        $err = $_;

        # No quotas is not an error.
        if ( !try { $err->isa('Cpanel::Exception::Quota::NotEnabled') } ) {
            require Cpanel::Exception;
            warn Cpanel::Exception::get_string($err);
        }
    };

    return $err ? 0 : 1;
}

sub exists {
    my ($self) = @_;
    return Cpanel::AcctUtils::Account::accountexists( $self->login );
}

# if this changes make sure all callers change also, inclduing the RPM repos
sub sanity_check {
    my ( $self, %opts ) = @_;

    if ( $self->exists() ) {
        return $self->post_create();
    }

    if ( $opts{create_if_missing} ) {
        print "Adding missing user '" . $self->login . "'\n" if $opts{verbose};
        $self->create();
    }
    return;
}

# create the user
sub create {
    my ($self) = @_;

    $self->_check();

    # create group if specified and missing
    $self->_check_and_create_group();

    my @args = ( '-s' => $self->shell );
    push @args, '-r' if $self->is_system_account;
    push @args, '-p' => $self->password if defined $self->password;
    push @args, '-g' => $self->group    if $self->group;
    push @args, '-G' => $self->group    if $self->group;
    push @args, '-b' => $self->basedir  if $self->basedir;
    push @args, '-d' => $self->homedir  if $self->homedir;
    push @args, '--create-home' if $self->create_home;

    AcctLock::acctlock();

    # abort earlier: ubuntu is not failing when basedir does not exist (preserve CentOS behavior)
    die "Problem while creating user " . $self->login() if $self->basedir && !-d $self->basedir;

    # TODO refactor this to use Cpanel::SysAccounts/IdAlloc
    Cpanel::SafeRun::Errors::saferunnoerror( _system_useradd(), @args, $self->login );
    AcctLock::acctunlock();

    die "Problem while creating user " . $self->login() if $?;

    $self->post_create();

    return 1;
}

# called in case of success or when the force option is used
sub post_create {
    my $self = shift;

    $self->_check_ids();

    # (re)set the quota ( 0 by default if not defined )
    $self->set_quota();

    # set the owner before setting the permissions
    $self->_set_owner();
    $self->_set_permissions();

    Cpanel::PwCache::Clear::clear_global_cache();

    return;
}

=head2 delete($self, force => ..., remove => ...)

=head3 Description

Deletes the user and its group, if the group will be empty after the user is gone.

=head3 Arguments

=over

=item - I<force> (boolean)

When true, the --force flag will be used when running the `userdel` command. This will ensure that the account is deleted, even if the user is still logged in or running a process.

B<Warning:> This flag may have the side effect of removing the group with the same username as the user, even if that group is still the primary group of another user. The delete method already handles group cleanup outside of the `userdel` binary, so only use this option if you need to ensure that lingering processes don't hinder the deletion operation or you're sure that it's a very remote possibility that any other user would be a member of the group.

=item - I<remove> (boolean)

When true, the --remove flag will be used when running the `userdel` command. This flag will remove the user's home directory and mail spool.

=back

=head3 Returns

=over

=item - I<success> (number)

This method will return 1 when successful or die if it's not.

=back

=cut

sub delete {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $self    = shift;
    my %options = @_;

    $self->login or die "Cannot delete a user without a username.";

    # force to reset quota before removing user
    $self->set_quota(0);

    # set the deletion options
    my @command_options;
    if ( delete $options{force} ) {
        push @command_options, '--force';
    }
    if ( delete $options{remove} ) {
        push @command_options, '--remove';
    }
    if (%options) {
        die 'Unknown command option(s) provided to delete method: ' . join ',', @command_options;
    }

    # then delete user
    AcctLock::acctlock();

    # TODO refactor this to use Cpanel::SysAccounts
    Cpanel::SafeRun::Errors::saferunnoerror( _system_userdel(), @command_options, $self->login );
    AcctLock::acctunlock();

    die "Problem while deleting user " . $self->login() if $?;
    Cpanel::PwCache::Clear::clear_global_cache();

    # and delete the group(s)
    $self->_check_and_delete_group( $self->login );
    $self->_check_and_delete_group( $self->group ) if ( $self->group ne $self->login );

    return 1;
}

# internal methods

sub _check {
    my ($self) = @_;

    die "No name to adduser." unless $self->login;
    die "homedir and basedir cannot be used at the same time." if $self->homedir && $self->basedir;
    if ( $self->exists() ) {

        # even if the user alreay exists
        #    make sure that we are going to set everything
        my $extra = '';
        if ( $self->force() ) {
            $self->post_create();
            $extra = ' ( permissions, owner and quota reset )';
        }
        die "User '" . $self->login . "' already exists.$extra";
    }

    return;
}

sub _check_ids {
    my ($self) = @_;
    my ( $uid, $gid, $homedir ) = ( getpwnam( $self->login ) )[ 2, 3, 7 ];

    die "Cannot get user id for user " . $self->login unless $uid;
    $self->uid($uid);
    $self->gid($gid);
    $self->homedir($homedir) if $homedir;

    return;
}

sub _set_owner {
    my ($self) = @_;
    return unless $self->owner && -e $self->homedir;
    my ( $u, $g ) = split( ':', $self->owner, 2 );
    my $gid = $self->_check_and_create_group($g);

    # do not use safe_chown here as we really want to change the ownership of the directory
    #    whatever is the value, there are no reasons to use the force option here
    chown( scalar( ( getpwnam $u )[2] ), $gid, $self->homedir ) and return;
    die "Cannot set homedir owner to " . $self->owner;
}

sub _set_permissions {
    my ($self) = @_;
    return unless defined $self->permissions && -e $self->homedir;

    # No need to use safetybits here since root owns the parent directory
    chmod( oct( $self->permissions ), $self->uid, $self->homedir )
      or die "Cannot set homedir permissions to " . $self->permissions;
    return;
}

sub _check_and_delete_group {
    my ( $self, $group_name ) = @_;

    $group_name ||= $self->login;

    # Check to see if the group exists and if there are any members
    # left in the group before trying to delete it.
    Cpanel::LoadModule::load_perl_module('Cpanel::Sys::Group');
    my $group = eval { Cpanel::Sys::Group->load($group_name) };
    if ( $group && !@{ $group->get_members } ) {

        # TODO refactor this to use Cpanel::SysAccounts
        AcctLock::acctlock();
        Cpanel::SafeRun::Errors::saferunnoerror( _system_groupdel(), $group_name );
        AcctLock::acctunlock();

        die "Error while deleting group '$group_name': " . ( $? >> 8 ) if $?;
    }
    return 1;
}

sub _check_and_create_group {
    my ( $self, $group ) = @_;

    $group ||= $self->group;
    return unless $group;

    # check if group alreay exists
    my $gid;
    if ( $group =~ /^[0-9]+$/ ) {
        $gid = $group if scalar getgrgid($group);
        die "Cannot load group ID '$group'" unless defined $gid;
    }
    else {
        Cpanel::LoadModule::load_perl_module('Cpanel::Sys::Group');
        $gid = Cpanel::Sys::Group->load_or_create( $group, $self->is_system_account() )->gid();
    }
    return $gid;
}

1;
