package Cpanel::Fileman::Trash;

# cpanel - Cpanel/Fileman/Trash.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Chdir           ();
use Cpanel::Exception       ();
use Cpanel::PwCache         ();
use Cpanel::Security::Authz ();

use constant _ENOENT => 2;

sub empty_trash {
    my ($older_than) = @_;

    $older_than //= 0;
    if ( $older_than !~ m/^[0-9]+$/ || $older_than < 0 ) {
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The parameter “[_1]” must be a whole number.',
            ['older_than']
        );
    }

    # if $older_than is zero, we want to delete files irrespective of age. This will be wrong if any files
    # are newer than January 19, 2038, in which case this code needs to be updated, or you have bigger
    # problems than a full .trash folder.
    #
    # Also, off-by-one errors are hard.
    my $age_min  = ( $older_than == 0 ) ? 2147483647 : time - ( ( $older_than + 1 ) * 86400 );
    my $trashdir = Cpanel::PwCache::gethomedir() . '/.trash';

    do_empty( $trashdir, $age_min );
    prune_restore_file($trashdir);

    return 1;
}

sub do_empty {
    my ( $trashdir, $age_min ) = @_;

    Cpanel::Security::Authz::verify_not_root();

    my $ok = opendir( my $dh, $trashdir ) or do {
        die "Failed to open “$trashdir”: $!" if $! != _ENOENT();
    };

    if ($ok) {
        my $chdir = Cpanel::Chdir->new($trashdir);

      RM_ITEM: while ( my $file = readdir $dh ) {

            # .trash_restore is metadata we use, so it MUST NOT be deleted.
            # We skip . and .. because, while rm *will* refuse to remove them,
            # it will do so noisily.
            next RM_ITEM if $file eq '.' || $file eq '..' || $file eq '.trash_restore' || ( lstat $file )[10] >= $age_min;

            # doing Perl's recursive delete would add about 1.3M to queueprocd's RSS.
            # However this is not a problem since we are in a queueprocd child which
            # will end when this task is completed.
            if ( -d _ ) {
                require File::Path;

                try {
                    File::Path::rmtree($file);
                }
                catch {
                    warn "rmtree($file): $_";
                };
            }
            else {
                unlink $file or do {
                    warn "unlink($file): $!" if $! != _ENOENT();
                };
            }
        }

        close $dh;
    }

    return 1;
}

sub prune_restore_file {
    my ($trashdir) = @_;

    return 1 if !-e "$trashdir/.trash_restore";

    local $| = 1;

    # .trash_restore may now refer to files that don't exist and therefore can't be restored.
    open my $restore_fh, '<', "$trashdir/.trash_restore"
      or die "Unable to open $trashdir/.trash_restore for reading: $!";
    open my $temp_fh, '>', "$trashdir/.trash_restore_pruned"
      or die "Unable to open $trashdir/.trash_restore_pruned for writing: $!";

    while (<$restore_fh>) {

        # splitting on = is safe here because .trash_restore encodes literal ='s in filenames.
        my $rel_filename = ( split( /=/, $_ ) )[0];
        print {$temp_fh} $_ if -e "$trashdir/$rel_filename";
    }

    close $restore_fh;
    close $temp_fh;

    unlink "$trashdir/.trash_restore";
    rename "$trashdir/.trash_restore_pruned", "$trashdir/.trash_restore"
      or die "Couldn't move $trashdir/.trash_restore_pruned to $trashdir/.trash_restore: $!";

    return 1;
}

1;
