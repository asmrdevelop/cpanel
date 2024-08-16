package Cpanel::MemUsage::Daemons::Banned;

# cpanel - Cpanel/MemUsage/Daemons/Banned.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Binary ();

our @BANNED_MEMORY_MODULES = (
    'CDB_File',
    'HTTP::Date',                       # use Cpanel::Time::HTTP
    'Cpanel::API',                      # should never be in a daemon, means for cpanel.pl and family only
    'Cpanel::Locale',                   # suggest Cpanel::LoadModule::load_perl_module after fork()
    'Cpanel::Themes::Serializer',       # suggest Cpanel::LoadModule::load_perl_module only when needed
    'Storable',                         # suggest Cpanel::JSON instead
    'YAML::Syck',                       # suggest Cpanel::JSON instead
    'Sub::Name',                        # Suggest *Try::Tiny::subname = return { 1; };
    'attributes',                       # Suggest $INC{'attributes.pm'} = '__DISABLED__'; in BEGIN
    'Cpanel::HttpRequest',              # suggest Cpanel::LoadModule::load_perl_module after fork()
    'Cpanel::POSIX::Tiny',              # Get rid of OSSys calls (there are already alternatives for all of them in the codebase, Cpanel::TimeHiRes, Cpanel::SysConf::Constants, etc)
    'Cpanel::OSSys',                    # Get rid of OSSys calls (there are already alternatives for all of them in the codebase, Cpanel::TimeHiRes, Cpanel::SysConf::Constants, etc)
    'POSIX',                            # Get rid of OSSys calls (there are already alternatives for all of them in the codebase, Cpanel::TimeHiRes, Cpanel::SysConf::Constants, etc)
    'Lchown',                           # use Cpanel::Lchown
    'IO::Socket::SSL::PublicSuffix',    # use Cpanel::LoadModule::load_perl_module after fork()
    'DateTime',                         # use Cpanel::Time or Time::Piece
);

sub check {
    return 1 if $ENV{'TEST2_HARNESS_ACTIVE'};    # Don't complain about Test2 issues.
    return 1 if Cpanel::Binary::is_binary();     # No need to run this check if we already made it though compile
    foreach my $mod (@BANNED_MEMORY_MODULES) {
        my $mod_path = $mod;
        $mod_path =~ s{::}{/}g;
        $mod_path .= '.pm';
        if ( $INC{$mod_path} && $INC{$mod_path} ne '__DISABLED__' ) {
            require Carp;
            Carp::confess("$mod is not permitted to be compiled into a daemon");
        }

    }
    return 1;
}

sub add_exception {
    my ($exception) = @_;

    @BANNED_MEMORY_MODULES = grep { $_ ne $exception } @BANNED_MEMORY_MODULES;

    return 1;
}

1;
