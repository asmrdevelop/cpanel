
# cpanel - Cpanel/Quota/Common.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Quota::Common;

use strict;
use warnings;

use parent 'Cpanel::Quota::Filesys';

use Cpanel::PwCache           ();
use Cpanel::Quota::Normalized ();
use Cpanel::Exception         ();

use constant {
    _EPERM  => 1,
    _ENOENT => 2,
    _EACCES => 13
};

our $MEGABYTES_TO_BLOCKS = 1024;

our $debug = 0;

=head1 NAME

Cpanel::Quota::Common

=head1 DESCRIPTION

This module is intended to be used as a base class for
Cpanel::Quota::Inode and Cpanel::Quota::Blocks

=head1 METHODS

=head2 new($args)

Create an instance of the class.

=head3 Arguments

    'args' hash ref (optional)  An optional hash ref of options that shortens the amount of code
                                required for single use objects. All of the options can be set using
                                setter methods as well.

        'user'      string|number       The username or uid of the user upon which you wish to operate.
        'paths'     array of strings    Quotas will only affect these paths, if provided. The path types
                                        are not always standard file system paths and vary depending upon
                                        the system's quota implementation. Use get_paths (after a call to
                                        get_limits) or get_all_paths to see a list and compare with the
                                        output of the 'mount' command for file system paths if they differ.
        'limits'    hash ref            Limits you would like to set immediately for the given user. The
                                        user key MUST be given to the constructor to use this. By cPanel
                                        convention, hard and soft quota limits are set the same, unless
                                        both are specified here.
            'soft'  number  The soft block quota.
            'hard'  number  The hard block quota.
        'skip_conf_edit' boolean        If provided, the dovecot cache will not be flushed and the
                                        The cpanel users file will not be updated.
        'skip_fs_with_quotas_off' boolean        If provided, the Quota::NotEnabled exception will not be thrown
                                        when the system encounters a device with quotas configured that are
                                        currently off/disabled.



=cut

sub new {
    my ( $package, $args ) = @_;
    my $self = {};

    bless $self, $package;

    $self->_get_quota_paths();
    $self->set_user( $args->{user} )     if length $args->{user};
    $self->set_paths( $args->{paths} )   if $args->{paths};
    $self->set_limits( $args->{limits} ) if $args->{limits};

    $self->{skip_conf_edit}          = $args->{skip_conf_edit};
    $self->{skip_fs_with_quotas_off} = $args->{skip_fs_with_quotas_off};

    return $self;
}

=head2 set_paths($path_1, $path_2, ... $path_N)

Filters or resets the paths to act upon. Without using set_paths, setting limits will
apply those limits to all mount points found to use quotas. This method allows you to
restrict that behavior and apply the limits to only the paths specified, so long as they
are still valid paths.

=head3 Arguments

    'path_N'  arrayref(optional)     The argument list is a list of paths upon which the
                                     object will operate. If omitted, the list of paths is
                                     reset to the full original list.

=head3 Return Value

    object  The instantiated object to facilitate chaining.
            e.g. $bquota->set_paths('/dev/sda1', '/dev/sda1')->set_limits({ soft => 10000 })

=cut

sub set_paths {
    my ( $self, @provided_paths ) = @_;
    @provided_paths = @{ $provided_paths[0] } if @provided_paths == 1 && ref $provided_paths[0] eq 'ARRAY';

    if ( scalar @provided_paths ) {
        my %hashed_paths_unfiltered = map { $_ => 1 } @{ $self->{paths_unfiltered} };
        $self->{paths} = [ grep { $hashed_paths_unfiltered{$_} } @provided_paths ];

        if ( !@{ $self->{paths} } ) {

            #This is a debug message, not meant for users.
            die Cpanel::Exception->create_raw("The paths provided (@provided_paths) do not match any available paths. Use get_paths (after get_limits) or get_all_paths to inspect the available paths.");
        }
    }
    else {
        $self->{paths} = [ $self->get_all_paths() ];
    }

    return $self;
}

=head2 get_limits()

Gets the current quota limits for the set user. These will include block quotas as well,
simply because the storage of those values is required so they are available when setting
new inode limits.

=head3 Arguments

    None.

=head3 Return Value

One of:

=over

=item * undef, if there are no filesystems with quotas enabled
and if C<skip_fs_with_quotas_off> is disabled.

=item * Otherwise, a hash reference of all quota limits grouped by path.
(See the code for the deep hash structure.)

=back

=cut

sub get_limits {
    my ($self) = @_;

    if ( !defined $self->{uid} ) {
        die Cpanel::Exception->create_raw('Cannot retrieve inode limits before setting a user. Use set_user first or pass user information to the constructor.');
    }

    my $limits = $self->{limits} = {};
    my %paths_with_quotas_disabled;

    for my $dev ( @{ $self->{'paths'} } ) {    # this is the list of active paths
        my $lookupdev = $self->get_device_arg_for_quota_module_for_path($dev);

        my @results = Cpanel::Quota::Normalized::query( $lookupdev, $self->{uid} );
        my ( $blocks, $bsoft, $bhard, $bgrace, $inodes, $isoft, $ihard, $igrace ) = @results;

        if ( @results != 8 ) {                 # If it's not 8 items long, quotas aren't enabled on the file system
                                               # We will remove the device from $self->{'paths'}
                                               # below after we have finished enumerating the array.
            delete $self->{'paths_info'}{$dev};
            $paths_with_quotas_disabled{$dev} = 1;
            next;
        }

        $limits->{$dev} = {
            block => {
                blocks => $blocks,
                soft   => $bsoft,
                hard   => $bhard,
                grace  => $bgrace,
            },
            inode => {
                inodes => $inodes,
                soft   => $isoft,
                hard   => $ihard,
                grace  => $igrace,
            },
        };
    }

    # Remove paths with disabled quotas AFTER enumeration to avoid inconsistant behavior
    # in the for loop
    @{ $self->{paths} } = grep { !$paths_with_quotas_disabled{$_} } @{ $self->{paths} };

    if ( !%{$limits} && !$self->{'skip_fs_with_quotas_off'} ) {
        die Cpanel::Exception::create( 'Quota::NotEnabled', 'Quotas are not enabled on any of the provided paths. Please check the paths and try again. Paths: [_1]', [ join ',', @{ $self->{paths} } ] );
    }

    return $self->{limits};
}

=head2 set_user($user)

Sets the user to act upon.

=head3 Arguments

    'user'  string|number   The username or uid of the user upon which you wish to operate.

=head3 Return Value

    object  The instantiated object to facilitate chaining.
            e.g. $iquota->set_user('user_1')->set_limits({ soft => 10000 })
                 $iquota->set_user('user_2')->set_limits({ soft => 15000 })

=cut

sub set_user {
    my ( $self, $user ) = @_;
    my $uid;

    if ( $user =~ m/^[0-9]+$/ ) {
        $uid  = $user;
        $user = undef;
    }

    if ( defined $uid ) {
        $user = $uid;    # It’s possible to have a uid without username (a deleted user)
    }
    else {
        $uid = Cpanel::PwCache::getpwnam($user);
        if ( !defined $uid ) {
            die Cpanel::Exception->create( 'User with username “[_1]” not found.', [$user] );
        }
    }

    $self->{uid}    = $uid;
    $self->{user}   = $user;
    $self->{limits} = undef;

    return $self;
}

=head2 update_mtimes_to_clear_cache

Ensures the mtime is updated on the quota files that we
use in Cpanel::QuotaMtime::get_quota_mtime() for cache invalidation.

=head3 Arguments

none

=head3 Returns

The number of files updated

=cut

sub update_mtimes_to_clear_cache {
    my ($self) = @_;
    my $touched = 0;
    foreach my $device ( @{ $self->{'paths'} } ) {
        my $mntpoint = $self->{'paths_info'}{$device}{'mountpoint'} || next;
        foreach my $quotafile (qw( quota.user aquota.user quota.group aquota.group)) {
            my $path = "$mntpoint/$quotafile";
            $path =~ s{/+}{/}g;

            print "Updating $path mtime\n" if $debug;

            # This utime() only succeeds when quotas are disabled.
            # When quotas are enabled, even “root” receives EACCES or EPERM
            # when trying to utime() the quota files.
            #
            # This shouldn’t be necessary, in theory, but (per JNK)
            # it has been necessary previously, and it’s more work
            # to test which kernel versions need or don’t need it
            # now than it is just to keep the utime().
            #
            # FYI: It’s normal for some of these to not exist since
            # since some versions of the kernel use different paths.
            #
            if ( utime( undef, undef, $path ) ) {
                $touched += 1;
            }
            elsif ( $! != _ENOENT() && $! != _EACCES() && $! != _EPERM ) {
                warn "utime($path): $!";
            }
        }
    }
    return $touched;
}

# tested directly
sub _reset_dovecot_cache_for_users {
    my ($self) = @_;

    require Cpanel::ServerTasks;
    require Cpanel::Dovecot::FlushcPanelAccountAuthQueue::Adder;
    Cpanel::Dovecot::FlushcPanelAccountAuthQueue::Adder->add( $self->{'user'} );
    return Cpanel::ServerTasks::schedule_task( ['DovecotTasks'], 60, 'flush_cpanel_account_dovecot_auth_cache_queue' );
}

sub _update_user_database {
    my ( $self, $key, $new_limit ) = @_;

    require Cpanel::Config::CpUserGuard;

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new( $self->{'user'} );
    $cpuser_guard->{'data'}->{$key} = ( $new_limit || 0 );
    $cpuser_guard->save();
    return 1;
}

my $logger;

sub _logger {
    require Cpanel::Logger;
    return ( $logger ||= Cpanel::Logger->new() );
}

# Either throw Quota::NotEnabled, or log and return empty,
# according to the object configuration.
#
sub _maybe_throw_for_disabled_quotas_on_fs {
    my ( $self, $path ) = @_;
    my $suppress;
    if ( $self->{'skip_fs_with_quotas_off'} ) {
        $suppress = Cpanel::Exception::get_stack_trace_suppressor();
    }
    my $exception = Cpanel::Exception::create( 'Quota::NotEnabled', 'The system failed to modify the quota for “[_1]” on the device “[_2]” because quotas are not enabled on this device. Generally you can run “[_3]” to fix this.', [ $self->{'user'}, $path, '/usr/local/cpanel/scripts/fixquotas' ] );
    if ( $self->{'skip_fs_with_quotas_off'} ) {
        $self->_logger()->info($exception);
        return;
    }
    die $exception;
}

1;
