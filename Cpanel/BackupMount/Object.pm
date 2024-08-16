package Cpanel::BackupMount::Object;

# cpanel - Cpanel/BackupMount/Object.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::BackupMount ();
use Cpanel::Destruct    ();
use Cpanel::Exception   ();

my $DEFAULT_TTL = 15_000;

#Parameters (named):
#
#   mount_point - the filesystem mount point
#
#   ttl         - max time that the mount should stay open for, in seconds
#                 defaults to $DEFAULT_TTL
#
#NOTE: Unlike the functions in Cpanel::BackupMount, this interface doesn't
#provide a means of working with the "mount key". This is by design; if you
#need to work with mounts that this module has created, add methods here
#rather than exposing the "mount key". The advantages are tighter abstraction
#and a simpler interface.
#
sub new {
    my ( $class, %opts ) = @_;

    #Generate a unique key. This is NOT meant for external consumption.
    my $backup_mount_key = join(
        '-',
        __PACKAGE__,
        time(),
        $$,
        int rand 1_000_000_000,
    );

    my $self = {
        _mount_point => $opts{'mount_point'},
        _mount_key   => $backup_mount_key,
        _ttl         => $opts{'ttl'} || $DEFAULT_TTL,
    };
    bless $self, $class;

    Cpanel::BackupMount::mount_backup_disk( @{$self}{qw( _mount_point _mount_key _ttl )} ) or do {
        die Cpanel::Exception->create( 'The system failed to mount the backup disk at “[_1]”.', [ $opts{'mount_point'} ] );
    };

    return $self;
}

sub DESTROY {
    my ($self) = @_;

    return if Cpanel::Destruct::in_dangerous_global_destruction();

    return Cpanel::BackupMount::unmount_backup_disk( $self->{'_mount_point'}, $self->{'_mount_key'} );
}

1;
