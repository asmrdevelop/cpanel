package Whostmgr::Templates::Chrome::Rebuild;

# cpanel - Whostmgr/Templates/Chrome/Rebuild.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

use Whostmgr::Templates::Command::Directory ();

=head1 DESCRIPTION

Rebuild WHM chrome (headers and footers) cache

=cut

=head1 SUBROUTINES

=cut

=head2 rebuild_whm_chrome_cache

=head3 Purpose

Queue a task to rebuild the cache

=cut

sub rebuild_whm_chrome_cache {
    Whostmgr::Templates::Command::Directory::clear_cache_dir();

    Cpanel::LoadModule::load_perl_module('Cpanel::ServerTasks');
    Cpanel::ServerTasks::queue_task( ["WHMChromeTasks"], "rebuild_whm_chrome" );

    return;
}

1;
