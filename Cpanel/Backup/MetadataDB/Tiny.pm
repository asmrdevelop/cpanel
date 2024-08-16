package Cpanel::Backup::MetadataDB::Tiny;

# cpanel - Cpanel/Backup/MetadataDB/Tiny.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Backup::Config ();
use Cpanel::Mkdir          ();

=head1 NAME

Cpanel::Backup::MetadataDB::Tiny

=head1 DESCRIPTION

Routines that are split out from Cpanel::Backup::MetadataDB

=head1 SYNOPSIS

    my $user = 'billy';
    if (does_user_have_a_backup ($user)) {
        print "Coolio\n";
    }

=cut

=head1 SUBROUTINES

=head2 base_path

Returns the path to the directory containing metadata DBs.

Example:

    my $dbfile = base_path() . "/$username.db"

=cut

sub base_path {
    my $conf            = Cpanel::Backup::Config::load();
    my $backup_dir      = $conf->{'METADATADIR'} || $conf->{'BACKUPDIR'} || '/backup/';
    my $backup_meta_dir = $backup_dir . '/.meta';
    if ( !-e $backup_meta_dir ) {
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $backup_meta_dir, 0711 );
    }
    return $backup_meta_dir;
}

=head2 does_user_have_a_backup

Returns true if the user has a metadata db present.

=cut

my $_cached_base_path;
my %_users_dbs;

# NOTE: Thus far this is only called from WHM API v1, so it’s
# optimized for that context. If we need it not to slurp in the
# entire list of users, it might make sense to create a fetch
# call for all users that have backups.
sub does_user_have_a_backup {
    my ($user) = @_;

    return 0 if not defined $user;

    if ( !defined $_cached_base_path ) {
        $_cached_base_path = eval { base_path(); };

        return 0 if not defined $_cached_base_path;

        require Cpanel::FileUtils::Dir;

        # Its much cheaper to load the list of users that have files into memory
        # once than stat every file in the directory since it will significantly
        # reduce the number of syscalls when there are even just a few users.
        %_users_dbs = map { $_ => 1 } @{ Cpanel::FileUtils::Dir::get_directory_nodes($_cached_base_path) };

    }

    return $_users_dbs{"$user.db"} ? 1 : 0;
}

sub _clear_cache {
    $_cached_base_path = undef;
    return;
}

1;
