package Whostmgr::Services::Load;

# cpanel - Whostmgr/Services/Load.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LoadModule       ();
use Cpanel::StringFunc::Case ();
use Cpanel::SafeRun::Simple  ();

sub reload_service {
    my $service = shift;
    $service = Cpanel::StringFunc::Case::ToLower($service);
    if ( _load_and_init_service_module($service) ) {
        local $@;
        eval { "Whostmgr::Services::$service"->can('reload_service')->(); };
        return 1 if !$@;
    }
    require Cpanel::RestartSrv::Script;
    my $script = Cpanel::RestartSrv::Script::get_restart_script($service);
    if ($script) {
        Cpanel::SafeRun::Simple::saferunallerrors($script);
        return 1 unless $?;
    }
    return;
}

sub _load_and_init_service_module {
    my $service = shift;
    return 1 if $INC{"Whostmgr/Services/$service.pm"};
    local $@;
    eval {
        my $fullmodule = "Whostmgr::Services::$service";
        Cpanel::LoadModule::load_perl_module($fullmodule);
        my $init_ref = $fullmodule->can('init');
        $init_ref->() if $init_ref;
    };
    return 1 if !$@;
    return;
}

1;

__END__
