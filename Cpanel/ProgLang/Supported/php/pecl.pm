package Cpanel::ProgLang::Supported::php::pecl;

# cpanel - Cpanel/ProgLang/Supported/php/pecl.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();
use parent 'Cpanel::ProgLang::Supported::php::pear';

sub get_relative_binary_path  { return '/usr/bin/pecl'; }
sub get_display_name_singular { return 'PHP PECL'; }                    # corresponds to the 'name' key in Cpanel::LangMods
sub get_display_name_plural   { return 'PHP PECL(s)'; }                 # corresponds to the 'names' key in Cpanel::LangMods
sub get_php_dir_arguments     { return [ 'config-get', 'ext_dir' ]; }
sub search_blocks_beta        { return 1; }

sub is_install_allowed {
    my ( $self, $module ) = @_;

    $module = lc $module;
    my $blocked_by_apache = {
        'eio' => {
            'path' => q{mod_ruid2.so},
            'name' => q{Mod Ruid2},
        },
        'dio' => {
            'path' => q{mod_ruid2.so},
            'name' => q{Mod Ruid2},
        },
        'posix' => {
            'path' => q{mod_ruid2.so},
            'name' => q{Mod Ruid2},
        },
    };
    if ( exists $blocked_by_apache->{$module} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::ConfigFiles::Apache::modules');
        my $soref = Cpanel::ConfigFiles::Apache::modules::get_shared_objects();

        if ( exists $soref->{ $blocked_by_apache->{$module}->{'path'} } ) {
            die Cpanel::Exception->create(
                'Cannot install the [output,acronym,PECL,PHP Extension Community Library] extension “[_1]”. The [asis,Apache] module “[_2]” is installed.',
                [ $module, $blocked_by_apache->{$module}->{'name'} ]
            )->get_string_no_id()
              . "\n";
        }
    }

    return 1;
}

1;
