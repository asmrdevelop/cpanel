
# cpanel - Cpanel/Quota/Temp.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Quota::Temp;

use strict;
use warnings;

use Cpanel::Debug         ();
use Cpanel::Quota::Inode  ();
use Cpanel::Quota::Blocks ();
use Cpanel::Quota::Utils  ();

=head1 NAME

Cpanel::Quota::Temp

=head1 SYNOPSIS

  my $tempquota = Cpanel::Quota::Temp->new( user => $user );
  $tempquota->disable();
  Cpanel::AccessIds::do_as_user( $user, sub { ... } );
  $tempquota->restore();

=head1 DESCRIPTION

Wraps the effort of temporarily disabling the quota for a user and then restoring it.
This is useful if you want to safely (i.e., as the user rather than as root) manipulate
files or directories under a user's home directory, but you want to circumvent quota
restrictions.

It should go without saying that this opens a window of time in which the user
could consume more disk space than normally allowed.

=head1 CONSTRUCTION

=head2 Arguments

  'user': (required) The user on which to operate
  'log': (optional) Boolean value which, if true, will cause Cpanel::Logger
                    messages to be produced about what's being done to the quota.

=head1 METHODS

=head2 disable()

Disables the quota for the user. The original quota is saved in the object so that
it can be restored with restore()..

=head3 Arguments

None

=head3 Return

This function returns 1 if the quota was modified.

This function returns undef if the quota was not modified.

=head2 restore()

Restores the original quota for the user. If the operations that have occurred since
the quota was disabled caused the user's disk usage to exceed the original quota, then
the user will be put into an over-quota state. This is the intended effect.

=head3 Arguments

None

=head3 Return

This function returns 1 if the quota was modified.

This function returns undef if the quota was not modified.

=cut

sub new {
    my ( $package, @args ) = @_;
    my $self = {@args};

    if ( !defined $self->{user} ) {
        die 'Please specify a user';
    }
    $self->{'original_pid'} = $$;
    bless $self, $package;

    return $self;
}

sub disable {
    my ($self) = @_;

    _sanity_check();

    $self->{disabled}     = 0;
    $self->{blocks_quota} = Cpanel::Quota::Blocks->new( { user => $self->{user}, skip_conf_edit => 1, skip_fs_with_quotas_off => 1 } );

    if ( !$self->{blocks_quota}->quotas_are_enabled() ) {

        # blocks and inodes are either on or off so no need to check both
        # Nothing to do
        return 0;
    }

    # get_limits returns the same for both inodes and blocks
    # so we store it in both places
    $self->{orig_quota_blocks} = $self->{blocks_quota}->get_limits();

    if ( !Cpanel::Quota::Utils::has_effective_limit( $self->{orig_quota_blocks} ) ) {    # blocks and inodes have the same get_limits data so no need to check both
        if ( $self->{log} ) {
            Cpanel::Debug::log_info("There is no quota in place for $self->{user}, so no change needs to be made.");
        }
        delete @{$self}{qw(orig_quota_blocks orig_quota_inode)};
        return $self->{disabled} ? 1 : undef;

    }

    $self->{inode_quota}      = Cpanel::Quota::Inode->new( { user => $self->{user}, skip_conf_edit => 1, skip_fs_with_quotas_off => 1 } );
    $self->{orig_quota_inode} = $self->{orig_quota_blocks};

    if ( $self->{log} ) {
        for my $device ( keys %{ $self->{orig_quota_inode} } ) {
            my $dev_limits = $self->{orig_quota_inode}{$device}{inode};
            my $bk_limits  = $self->{orig_quota_blocks}{$device}{block};
            my $isoft      = $dev_limits->{soft};
            my $ihard      = $dev_limits->{hard};
            my $bsoft      = $bk_limits->{soft};
            my $bhard      = $bk_limits->{hard};

            Cpanel::Debug::log_info("Temporarily disabling quota for $self->{user} on $device: (was $bsoft/$bhard soft/hard blocks and $isoft/$ihard soft/hard inodes)");
        }
    }

    if ( Cpanel::Quota::Utils::has_effective_limit( $self->{orig_quota_inode}, ['inode'] ) ) {
        $self->{inode_quota}->set_limits( { soft => 0, hard => 0 } );
        $self->{'disabled'} = 1;
    }
    else {
        delete $self->{orig_quota_inode};
    }
    if ( Cpanel::Quota::Utils::has_effective_limit( $self->{orig_quota_blocks}, ['block'] ) ) {
        $self->{blocks_quota}->set_limits( { soft => 0, hard => 0 } );
        $self->{'disabled'} = 1;
    }
    else {
        delete $self->{orig_quota_blocks};
    }

    return $self->{disabled} ? 1 : undef;
}

sub restore {
    my ($self) = @_;

    _sanity_check();

    return undef unless delete $self->{disabled};

    my $orig_quota_inode  = delete $self->{orig_quota_inode};
    my $orig_quota_blocks = delete $self->{orig_quota_blocks};

    if ( $self->{log} ) {
        Cpanel::Debug::log_info("Restoring quota for $self->{user}");
    }

    # Restore the user's original quota. If this puts them over-quota, they will have to
    # work it out with the server admin, unfortunately.
    my $quotas_are_enabled = $self->{blocks_quota}->quotas_are_enabled();    # blocks and inodes are either on or off so no need to check both
    if ($quotas_are_enabled) {
        for my $path ( keys %$orig_quota_inode ) {
            $self->{inode_quota}->set_paths($path)->set_limits( $orig_quota_inode->{$path}{inode} );
        }
        for my $path ( keys %$orig_quota_blocks ) {
            $self->{blocks_quota}->set_paths($path)->set_limits( $orig_quota_blocks->{$path}{block} );
        }
    }
    return 1;
}

sub _sanity_check {
    if ( $> != 0 ) {
        require Carp;
        Carp::confess('Cpanel::Quota::Temp is only useful when executed as root');
    }
    return;
}

sub norestore {
    my ($self) = @_;
    delete $self->{disabled};
    return 1;
}

sub DESTROY {
    my ($self) = @_;

    if ( $$ == $self->{'original_pid'} && $self->{disabled} ) {
        $self->restore();
    }

    return 1;
}

1;
