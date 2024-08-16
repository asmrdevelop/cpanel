package Cpanel::Sys::Group;

# cpanel - Cpanel/Sys/Group.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use AcctLock                ();
use Cpanel::LoadModule      ();
use Cpanel::SafeRun::Errors ();

=encoding utf-8

=head1 NAME

Cpanel::Sys::Group - Tools for manipulating system groups

=head1 SYNOPSIS

    use Cpanel::Sys::Group;

    my $good_group         = Cpanel::Sys::Group->load($group_name_1);

=head1 DESCRIPTION

This module calls the system password utilities to modify
groups.  At some point it will be a wrapper around
Cpanel::SysAccounts in order to avoid the known issues
with the system tools.

=cut

sub create {
    my ( $class, $group, $is_system_account ) = @_;

    my $output = Cpanel::SafeRun::Errors::saferunallerrors( _system_groupadd(), ( $is_system_account ? ('-r') : () ), $group );

    # Note -- clear_cache already checks whether nscd is running.
    # Not sure about this optimization. Would cut down on one loaded
    # module at best.
    Cpanel::LoadModule::load_perl_module('Cpanel::NSCD::Check');
    if ( Cpanel::NSCD::Check::nscd_is_running() ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::NSCD');
        Cpanel::NSCD::clear_cache('group');
    }
    require Cpanel::SSSD;
    Cpanel::SSSD::clear_cache();

    my $gid = ( getgrnam($group) )[2];
    _croak("Error while adding group '$group': $output") if $? || !defined $gid;
    return $class->load($group);
}

=head2 load($group)

Creates a Cpanel::Sys::Group object and checks
/etc/passwd to see if any user has the gid of the
group.

Warning: This reads every line of /etc/passwd
and is expensive.  This is likely only needed
if you are checking the 'wheel' or 'sudo' group
for users that were created outside of cPanel's
control.

Example:

use Cpanel::OS ();
my $sys_group_obj = Cpanel::Sys:Group->load( Cpanel::OS::sudoers() );

=cut

sub load {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $self = load_group_only(@_);

    Cpanel::LoadModule::load_perl_module('Cpanel::PwCache::Build');

    my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();

    my $gid = $self->{'parameters'}{'gid'};

    my %members = map { $_ => undef } @{ $self->{'parameters'}{'members'} };

    my @users_with_gid = map { $_->[3] == $gid ? $_->[0] : () } @$pwcache_ref;

    @members{@users_with_gid} = () x scalar @users_with_gid;

    $self->{'parameters'}{'members'} = [ keys %members ];

    return $self;

}

=head2 load_group_only($group)

Creates a Cpanel::Sys::Group object without checking
/etc/passwd to see if any user has the gid of the
group.

When this module was originally designed it was used
to check for the wheel or sudo group.  Its possible a user
has the gid of 'wheel' or 'sudo', however a user should
never have the gid of ^cpanel group.

Example:

my $sys_group_obj = Cpanel::Sys:Group->load_group_only('cpanelsuspended');

=cut

sub load_group_only {
    my ( $class, $p_group ) = @_;

    # load group info from /etc/group into params #
    my %params;
    ( $params{'name'}, $params{'passwd'}, $params{'gid'}, my $members_str ) = getgrnam($p_group);
    _croak("invalid group name specified: $p_group")
      if !defined $params{'name'};

    # create a temporary hash of members from the space-separated list
    my %members = map { $_ => 1 } split / /, $members_str;

    # populate the members property on params now that we have everything
    $params{'members'} = [ keys %members ];

    # create! #
    return bless { 'parameters' => \%params }, $class;
}

sub load_or_create {
    my ( $class, $p_group, $is_system_account ) = @_;
    {
        local $@;
        my $obj = eval { $class->load_group_only($p_group) };
        return $obj unless $@;
    }
    return $class->create( $p_group, $is_system_account );
}

sub get_members {
    my $self = shift;

    # this is intentionally recreating the members arrayref so that callers can't damage our copy #
    return [ @{ $self->{'parameters'}->{'members'} } ];
}

sub add_member {
    my ( $self, $new_member ) = @_;
    my $group = $self->name();

    Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Account');
    Cpanel::AcctUtils::Account::accountexists_or_die($new_member);
    Cpanel::LoadModule::load_perl_module('Cpanel::SysAccounts');
    Cpanel::SysAccounts::add_user_to_group( $group, $new_member );

    $self->_refresh_memberlist();

    return 1;
}

sub remove_member {
    my ( $self, $old_member ) = @_;
    my $group = $self->name();

    Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Account');
    Cpanel::AcctUtils::Account::accountexists_or_die($old_member);

    if ( !$self->is_member($old_member) ) {
        _croak("'$old_member' is not a member of the group '$group'");
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::SysAccounts');
    Cpanel::SysAccounts::remove_user_from_group( $group, $old_member );

    $self->_refresh_memberlist();

    return 1;
}

sub _refresh_memberlist {
    my $self = shift;

    $self->{'parameters'}->{'members'} = [ split / /, ( getgrnam( $self->name() ) )[3] ];

    return;
}

sub is_member {
    my ( $self, $p_user ) = @_;
    return ( grep { $_ eq $p_user } @{ $self->{'parameters'}->{'members'} } ) ? 1 : 0;
}

sub gid {
    my ($self) = @_;
    return $self->{'parameters'}{'gid'};
}

sub passwd {
    my ($self) = @_;
    return $self->{'parameters'}{'passwd'};
}

sub name {
    my ($self) = @_;
    return $self->{'parameters'}{'name'};
}

sub _system_groupadd {
    my $bin = '/usr/sbin/groupadd';
    -x $bin or die "Do not know how to add a group on this system.";
    return $bin;
}

sub _croak {
    Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
    die Cpanel::Carp::safe_longmess(@_);
}

1;
