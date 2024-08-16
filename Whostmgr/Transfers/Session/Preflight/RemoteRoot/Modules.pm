package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Modules.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule     ();
use Cpanel::FileUtils::Dir ();

sub get_module_objects {

    # FIXME: this should not be a static path?
    # Do we want to allow them to add modules in /var?
    my $dir_nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes("/usr/local/cpanel/Whostmgr/Transfers/Session/Preflight/RemoteRoot/Modules");
    my %mods;
    foreach my $pm ( grep ( m{\.pm$}, @{$dir_nodes_ar} ) ) {
        my $module = $pm;
        $module =~ s/\.pm$//g;
        my $full_name = "Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::$module";
        Cpanel::LoadModule::load_perl_module($full_name);
        $mods{$module} = $full_name->new();
    }

    return \%mods;
}

# TODO: abstract away $self->module_name() so the Modules.pm adds and removes it and
#   # hides this from the implementor so they can't create conflicts
1;
