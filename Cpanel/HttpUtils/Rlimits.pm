package Cpanel::HttpUtils::Rlimits;

# cpanel - Cpanel/HttpUtils/Rlimits.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::SafeRun::Errors          ();
use Sys::Statistics::Linux::MemStats ();

sub determine_rlimitmem_for_apache {
    my $size = 0;

    my $mem_stats = Sys::Statistics::Linux::MemStats->new->get;
    $size += int( $mem_stats->{memtotal} / 2 );
    $size += int( $mem_stats->{swaptotal} / 3 );

    $size = int( $size / 2 );
    $size = int( $size * 1024 );
    $size = int( $size / 3 );

    # memtotal is in kilobytes here, and want to return MB
    return ( $size, int( $mem_stats->{'memtotal'} / 1024 ) );
}

sub get_current_rlimitmem {
    require Cpanel::EA4::Conf;
    return Cpanel::EA4::Conf->instance->rlimit_mem_soft;
}

sub set_rlimits_in_apache {
    my $size = shift;

    if ( not( $size && $size =~ m/^\d+$/ ) ) {
        die "Specified RLimitMEM value is invalid.\n";
    }

    require Cpanel::EA4::Conf;
    my $e4c = Cpanel::EA4::Conf->instance;
    $e4c->rlimit_cpu_hard("");
    $e4c->rlimit_cpu_soft(240);
    $e4c->rlimit_mem_hard("");
    $e4c->rlimit_mem_soft($size);
    $e4c->save;

    # Build new httpd.conf based on our new settings in the main yaml file
    # This causes the generation of the compile templates such as /var/cpanel/template_compiles/var/cpanel/templates/apache2_4/main.default
    Cpanel::SafeRun::Errors::saferunallerrors('/usr/local/cpanel/scripts/buildhttpdconf');
    return 1;
}

sub unset_rlimits_in_apache {
    require Cpanel::EA4::Conf;
    my $e4c = Cpanel::EA4::Conf->instance;
    $e4c->rlimit_cpu_hard("");
    $e4c->rlimit_cpu_soft(0);
    $e4c->rlimit_mem_hard("");
    $e4c->rlimit_mem_soft(0);
    $e4c->save;

    # Build new httpd.conf based on our new settings in the main yaml file
    Cpanel::SafeRun::Errors::saferunallerrors('/usr/local/cpanel/scripts/buildhttpdconf');
    return 1;
}

1;
