package Whostmgr::Templates::Command::Directory;

# cpanel - Whostmgr/Templates/Command/Directory.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

my $datastore_dir = '/var/cpanel/caches/_generated_command_files';

=head1 DESCRIPTION

Utility functions to handle directory for cached command.tmpl files

=cut

=head1 SUBROUTINES

=cut

=head2 get_cache_dir

=head3 Purpose

Returns the cache directory for processed command.tmpl

=cut

sub get_cache_dir {
    return $datastore_dir;
}

=head2 clear_cache_dir

=head3 Purpose

Clear cache files on disk

=cut

sub clear_cache_dir {
    Cpanel::LoadModule::load_perl_module('File::Path');

    # There may be a race condition where additional files can be created while
    # we're removing the directory contents, resulting in the directory not
    # being removed.  Ignore this case, since we already know which files we'll
    # want to have removed.
    File::Path::rmtree( get_cache_dir(), { error => \my $foo } );
    return;
}

1;
