package Cpanel::ApacheConf::Check;

# cpanel - Cpanel/ApacheConf/Check.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie ('exists');
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';
use Cpanel::LoadModule      ();
use Cpanel::SafeRun::Object ();

#Returns a Cpanel::SafeRun::Object instance.
sub check_path {
    my ($path) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::Httpd::EA4');

    my @args = ( '-DSSL', '-t', '-f', $path );

    # otherwise the syntax check below barfs with “httpd: Configuration error: No MPM loaded.”
    if ( Cpanel::Config::Httpd::EA4::is_ea4() ) {
        my $dir_base = apache_paths_facade->dir_base();
        push @args, -C => qq<Include "$dir_base/conf.modules.d/*.conf">;
    }
    elsif ( Cpanel::Autodie::exists( apache_paths_facade->dir_modules() . "/mod_mpm_prefork.so" ) ) {
        push @args, -C => "LoadModule mpm_prefork_module modules/mod_mpm_prefork.so";
    }

    #
    # Removing the before_exec from saferun object
    # allows this to use fastspawn
    #
    # We used to do this in the child, however as root
    # it doesn't do much harm to do this in the parent
    # since the limited circumstances we use this
    # are not a concern about consuming too much memory.
    if ( $> == 0 ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Rlimit');
        Cpanel::Rlimit::set_rlimit_to_infinity();
    }

    return Cpanel::SafeRun::Object->new(
        'program' => scalar apache_paths_facade->bin_httpd(),
        'args'    => \@args,
    );
}

1;
