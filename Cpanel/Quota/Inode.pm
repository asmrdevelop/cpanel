
# cpanel - Cpanel/Quota/Inode.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Quota::Inode;

use strict;

use Cpanel::Exception ();
use Quota             ();
use Errno             qw[ESRCH];

use parent 'Cpanel::Quota::Common';

=head1 NAME

Cpanel::Quota::Inode

=head1 SYNOPSIS

    my $iquota = Cpanel::Quota::Inode->new();
    $iquota->set_user('user1')->set_limits({ soft => 100000, hard => 200000 });

    my $iquota = Cpanel::Quota::Inode->new({ user => 504, limits => { soft => 100000 } });

    my $iquota = Cpanel::Quota::Inode->new()
        ->set_user('user1')
        ->set_paths('/dev/mapper/VolGroup-lv_root')
        ->set_limits({ soft => 100000 });


=head1 DESCRIPTION

Provides a simple interface for leveraging the Quota module on CPAN to make adjustments
to inode quotas. Currently, setting a quota will apply the same limit to each mount point
so the user can inadvertently receive a multiple of the quota allotment if you are not
careful. To work around this, you can restrict the paths before setting the limits.

=head1 CONSTRUCTION

Most of the time, you will only want to construct a single instance of this class and reuse it,
however for one-time use it can be convenient to pass in a list of options to set the inode quota
for a single user using just the constructor.

=head2 set_limits($new_limits)

Sets the quota limits for the set user.

=head3 Arguments

    'new_limits'    hash ref    The new inode limits to apply.
        'soft'  number  The new soft inode quota.
        'hard'  number  The new hard inode quota.

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

    if ( defined $old_limits && !scalar keys %{$old_limits} ) {
        return $self if ( $self->{'skip_fs_with_quotas_off'} );
        die Cpanel::Exception::create( 'Quota::NotEnabled', 'Filesystem quotas are not enabled for any of the provided paths. Paths: [_1]', [ join ',', @{ $self->{paths} } ] );
    }

    my $new_inode_limit;
    $new_inode_limit //= $new_limits->{hard};
    $new_inode_limit //= $new_limits->{soft};

    $self->_update_user_database( 'DISK_INODE_LIMIT', $new_inode_limit ) unless $self->{skip_conf_edit};

    for my $path ( @{ $self->{'paths'} } ) {    # this is the list of active paths

        next if !$path;

        my $bsoft = $old_limits->{$path}{block}{soft};
        my $bhard = $old_limits->{$path}{block}{hard};
        my $isoft = $new_limits->{soft} // $old_limits->{$path}{inode}{soft};
        my $ihard = $new_limits->{hard} // $old_limits->{$path}{inode}{hard};

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
        $self->_logger()->die( 'Unable to set inode quota on filesystem: ' . $err ) if $return;    #XS routine returns 0 on success.
    }

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
