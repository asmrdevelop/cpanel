package Cpanel::cPCPAN;

# cpanel - Cpanel/cPCPAN/Config.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $PREFER_MODULE_BUILD = 0;

sub fetch_config {
    my ( $self, %OPTS ) = @_;
    require Cpanel::cPCPAN::MirrorSearch;
    require Cpanel::Tar;

    my $tarcfg = Cpanel::Tar::load_tarcfg();

    local $Cpanel::cPCPAN::MirrorSearch::USING_CPAN = 1;
    my @GOODURLS = Cpanel::cPCPAN::MirrorSearch::getmirrorlist(%OPTS);
    my $MyConfig = {
        'auto_commit'                  => q[1],
        'build_cache'                  => q[10],
        'build_dir'                    => "$self->{'basedir'}/.cpan/build",
        'cache_metadata'               => q[1],
        'connect_to_internet_ok'       => 'no',
        'cpan_home'                    => "$self->{'basedir'}/.cpan",
        'dontload_hash'                => {},
        'ftp'                          => q[/usr/bin/ftp],
        'ftp_proxy'                    => q[],
        'getcwd'                       => q[cwd],
        'gzip'                         => q[/bin/gzip],
        'histfile'                     => "$self->{'basedir'}/.cpan/histfile",
        'histsize'                     => q[100],
        'http_proxy'                   => q[],
        'inactivity_timeout'           => q[310],
        'inhibit_startup_message'      => q[1],
        'index_expire'                 => q[1],
        'keep_source_where'            => "$self->{'basedir'}/.cpan/sources",
        'lynx'                         => q[],
        'make'                         => q[/usr/bin/make],
        'make_arg'                     => q[],
        'make_install_arg'             => q[UNINST=1],
        'makepl_arg'                   => q[],
        'mbuild_arg'                   => q[],
        'mbuild_install_arg'           => q[],
        'mbuild_install_build_command' => q[./Build],
        'mbuildpl_arg'                 => q[],
        'ncftpget'                     => q[],
        'no_proxy'                     => q[],
        'pager'                        => q[/usr/bin/less],
        'prefer_installer'             => ( $PREFER_MODULE_BUILD ? q[MB] : q[EUMM] ),
        'prerequisites_policy'         => q[follow],
        'scan_cache'                   => q[atstart],
        'shell'                        => '/bin/bash',
        'tar'                          => $tarcfg->{'bin'},
        'term_is_latin'                => q[1],
        'unzip'                        => q[/usr/bin/unzip],
        'use_sqlite'                   => 0,
        'urllist'                      => \@GOODURLS,
        'wget'                         => q[/usr/bin/wget],
    };

    if ($>) {
        require Config;
        require Cpanel::PwCache;
        my $homedir = ( Cpanel::PwCache::getpwuid($>) )[7];
        foreach my $key ( 'makepl_arg', 'make_arg', 'make_install_arg', 'mbuildpl_arg' ) {
            my @c = split( /\s+/, $MyConfig->{$key} );
            push( @c, 'PREFIX=' . $homedir . '/perl' . $Config::Config{'installprefix'} );
            $MyConfig->{$key} = join( ' ', @c );
        }
        $MyConfig->{'make_install_arg'} = '';
    }

    if ( eval { require LWP::UserAgent; } ) {
        warn("Disabling /bin/wget since LWP is available\n");
        $MyConfig->{'wget'} = q[/bin/false];
    }

    if ( eval { require Net::FTP; } ) {
        warn("Disabling /bin/ftp since Net::FTP is available\n");
        $MyConfig->{'ftp'} = q[/bin/false];
    }

    return $MyConfig;
}

1;
