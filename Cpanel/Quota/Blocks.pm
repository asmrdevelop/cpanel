
# cpanel - Cpanel/Quota/Blocks.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Quota::Blocks;

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Exception         ();
use Cpanel::SysQuota::Cache   ();
use Cpanel::Quota::Constants  ();
use Cpanel::Validate::Integer ();
use Quota                     ();
use Errno                     qw[ESRCH];

use parent 'Cpanel::Quota::Common';

=head1 NAME

Cpanel::Quota::Blocks

=head1 SYNOPSIS

    my $bquota = Cpanel::Quota::Blocks->new();
    $bquota->set_user('user1')->set_limits({ soft => 1024, hard => 2048 });

    my $bquota = Cpanel::Quota::Blocks->new({ user => 504, limits => { soft => 1024 } });

    my $bquota = Cpanel::Quota::Blocks->new()
        ->set_user('user1')
        ->set_paths('/dev/mapper/VolGroup-lv_root')
        ->set_limits({ soft => 1024 });


=head1 DESCRIPTION

Provides a simple interface for leveraging the Quota module on CPAN to make adjustments
to block quotas. Currently, setting a quota will apply the same limit to each mount point
so the user can inadvertently receive a multiple of the quota allotment if you are not
careful. To work around this, you can restrict the paths before setting the limits.

This module is a modified copy of Cpanel::Quota::Inode.

=head1 CONSTRUCTION

Most of the time, you will only want to construct a single instance of this class and reuse it,
however for one-time use it can be convenient to pass in a list of options to set the block quota
for a single user using just the constructor.

=head2 set_limits($new_limits)

Sets the quota limits for the set user.

=head3 Arguments

    'new_limits'    hash ref    The new block limits to apply. By cPanel convention, both hard and soft
                                quota limits are set the same, unless both hard and soft limits are
                                explicitly provided.
            'soft'  number  The soft block quota.
            'hard'  number  The hard block quota.

=head3 Return Value

    object  The instantiated object to facilitate chaining.

=cut

sub set_limits {
    my ( $self, $new_limits ) = @_;
    return $self->_set_limits( $self->get_limits(), $new_limits );
}

=head2 set_limits_if_quotas_enabled($new_limits)

Set set_limits.   This function does the exact same thing as set_limits
except it will not adjust the actual disk quota if quotas are not enabled

=cut

sub set_limits_if_quotas_enabled {
    my ( $self, $new_limits ) = @_;
    my $old_limits = undef;
    if ( $self->quotas_are_enabled() ) {
        $old_limits = $self->get_limits();
    }
    return $self->_set_limits( $old_limits, $new_limits );
}

sub _set_limits {
    my ( $self, $old_limits, $new_limits ) = @_;

    return unless ref $new_limits eq 'HASH' && ( defined $new_limits->{soft} or defined $new_limits->{hard} );

    if ( $self->{user} =~ /^cpanel(phpmyadmin|phppgadmin|roundcube|sqmail)$/ ) {
        $new_limits->{soft} = $new_limits->{hard} = 0;    # no, you really *don't* want to limit these.
    }

    if ( defined $old_limits && !scalar keys %{$old_limits} ) {
        return $self if ( $self->{'skip_fs_with_quotas_off'} );
        die Cpanel::Exception::create( 'Quota::NotEnabled', 'Filesystem quotas are not enabled for any of the provided paths. Paths: [_1]', [ join ',', @{ $self->{paths} } ] );
    }

    # if both limits are not explicitly given, we want to set both limits to the same thing. If
    # we ever want to allow cPanel & WHM to set these separately, just chop out ths section, and
    # the later reference to $link_values, and this sub will do the right thing (only editing
    # what is sent into it, and leaving everything else alone!) Assuming the soft quota is stored in
    # MB in the restructured conf file, you'll need to recalculate it like we're doing with hard quotas
    # just below here..
    my $link_values = 0;
    if ( !defined $new_limits->{soft} or !defined $new_limits->{hard} ) {
        $link_values = 1;
    }
    $new_limits->{soft} = $new_limits->{hard} if !defined $new_limits->{soft};
    $new_limits->{hard} = $new_limits->{soft} if !defined $new_limits->{hard};

    my @keys_to_check = ('soft');
    push @keys_to_check, 'hard' if $new_limits->{soft} ne $new_limits->{hard};

    for my $key (@keys_to_check) {
        try {
            Cpanel::Validate::Integer::unsigned_and_less_than(
                $new_limits->{$key},
                Cpanel::Quota::Constants::MAXIMUM_BLOCKS(),
            );
        }
        catch {
            my $str = $_->to_string_no_id();
            die Cpanel::Exception::create_raw( 'InvalidParameter', "$key: $str" );
        };
    }

    # we want to round the hard quota we have to the nearest whole MB. The quota conf file requires integers,
    # in MB.
    my $hard_quota_in_mb = sprintf( '%.0f', $new_limits->{hard} / 1024 );

    if ( $link_values or $new_limits->{soft} > $new_limits->{hard} ) {
        $new_limits->{soft} = $new_limits->{hard};
    }

    # Eventually, I'd like to see the fetch of this moved to new() somehow, and get reused, but
    # for now, to prevent race conditions, keep this really snug.

    unless ( $self->{skip_conf_edit} ) {

        $self->_update_user_database( 'DISK_BLOCK_LIMIT', $new_limits->{hard} );
    }

    # Now that we've updated the cpuser file, let's actually edit the quotas.
    #
    for my $path ( @{ $self->{'paths'} } ) {    # this is the list of active paths
        next if !$path;

        my $isoft = $old_limits->{$path}{inode}{soft};
        my $ihard = $old_limits->{$path}{inode}{hard};
        my $bsoft = $new_limits->{soft} // $old_limits->{$path}{block}{soft};
        my $bhard = $new_limits->{hard} // $old_limits->{$path}{block}{hard};

        my $lookupdev = $self->get_device_arg_for_quota_module_for_path($path);

        local $!;
        my $return = Quota::setqlim( $lookupdev, $self->{uid}, $bsoft, $bhard, $isoft, $ihard );

        if ( $! == ESRCH ) {
            $self->_maybe_throw_for_disabled_quotas_on_fs($path);

            # _maybe_throw_for_disabled_quotas_on_fs did not throw
            # an exception because skip_fs_with_quotas_off was set
            # so we skip to the next device without throwing
            # a logger die below
            next;

        }

        my $err = $!;

        # Generic error
        $self->_logger()->die( "Unable to set block quota on filesystem to “$bhard” blocks: " . $err ) if $return;    #XS routine returns 0 on success.
    }
    $self->update_mtimes_to_clear_cache();

    Cpanel::SysQuota::Cache::purge_cache();
    unless ( $self->{skip_conf_edit} ) {

        # Since we now provide the quota rules to dovecot
        # for filesystem quotas, we must reset the cache
        # each time we update the quota to ensure dovecot
        # is not working with an old rule
        $self->_reset_dovecot_cache_for_users();
    }
    return $self;
}

1;
