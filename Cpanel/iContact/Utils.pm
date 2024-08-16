package Cpanel::iContact::Utils;

# cpanel - Cpanel/iContact/Utils.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Context                      ();
use Cpanel::LoadModule                   ();
use Cpanel::TailWatch::ChkServd::Version ();

my $MIB_TO_BYTES = 2**20;

#Returns a list of key/value pairs:
#
#   chkservd_version    => $$
#   hostname            => $$
#   ssl_hostname        => $$
#   mainip              => $$
#   memory_installed    => ## (bytes)
#   memory_used         => ## (bytes)
#   memory_available    => ## (bytes)
#   load_one            => ##
#   load_five           => ##
#   load_fifteen        => ##
#   uptime              => ## (seconds)
#   iostat_txt          => $$
#
sub system_info_template_vars {
    Cpanel::Context::must_be_list();

    Cpanel::LoadModule::load_perl_module('Cpanel::DIp::MainIP');
    Cpanel::LoadModule::load_perl_module('Cpanel::Hostname');
    Cpanel::LoadModule::load_perl_module('Cpanel::Redirect');
    Cpanel::LoadModule::load_perl_module('Cpanel::Sys::Hardware::Memory');
    Cpanel::LoadModule::load_perl_module('Cpanel::Sys::IOStat');
    Cpanel::LoadModule::load_perl_module('Cpanel::Sys::Load');
    Cpanel::LoadModule::load_perl_module('Cpanel::Sys::Uptime');

    my $hostname = Cpanel::Hostname::gethostname();

    my %load;
    @load{qw( load_one  load_five  load_fifteen )} = Cpanel::Sys::Load::getloadavg($Cpanel::Sys::Load::ForceFloat);

    return (
        chkservd_version => $Cpanel::TailWatch::ChkServd::Version::CHKSERVD_VERSION,
        hostname         => $hostname,
        ssl_hostname     => Cpanel::Redirect::getserviceSSLdomain('cpanel') || $hostname,
        mainip           => scalar Cpanel::DIp::MainIP::getpublicmainserverip(),
        memory_used      => $MIB_TO_BYTES * Cpanel::Sys::Hardware::Memory::get_used(),
        memory_available => $MIB_TO_BYTES * Cpanel::Sys::Hardware::Memory::get_available(),
        memory_installed => $MIB_TO_BYTES * Cpanel::Sys::Hardware::Memory::get_installed(),

        %load,

        uptime => Cpanel::Sys::Uptime::get_uptime(),

        iostat_txt => scalar Cpanel::Sys::IOStat::getiostat(),
    );
}

#Returns an arrayref of: [
#       {
#           cpu     => percentage   (sorted descending)
#           mem     => percentage   (sorted descending)
#           pid     => ##           (sorted ascending)
#           nice    => ##
#           user    => $$
#           command => $$
#       },
#       ...
#   ]
#
sub procdata_for_template {
    Cpanel::LoadModule::load_perl_module('Cpanel::PsParser');

    return Cpanel::PsParser::fast_parse_ps(
        memory_stats   => 1,
        cpu_stats      => 1,
        exclude_kernel => 1,
        exclude_self   => 1,
        resolve_uids   => 1,
    );
}

sub procdata_for_template_sorted_by_cpu {
    my $procdata_ar = shift || procdata_for_template();

    return [
        sort {
            $b->{'cpu'}      <=> $a->{'cpu'}    #descending
              || $b->{'mem'} <=> $a->{'mem'}    #descending
              || $a->{'pid'} <=> $b->{'pid'}
        } @$procdata_ar
    ];
}

sub procdata_for_template_sorted_by_mem {
    my $procdata_ar = shift || procdata_for_template();

    return [
        sort {
            $b->{'mem'}      <=> $a->{'mem'}    #descending
              || $b->{'cpu'} <=> $a->{'cpu'}    #descending
              || $a->{'pid'} <=> $b->{'pid'}
        } @$procdata_ar
    ];
}

1;
