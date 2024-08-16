package Cpanel::TailWatch::Utils::Stubs;

# cpanel - Cpanel/TailWatch/Utils/Stubs.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::TailWatch::Utils::Stubs::ScalarUtil ();    # PPI USE OK - provide Scalar::Util::weaken

package File::Spec;
$INC{'File/Spec.pm'} = __FILE__;

sub curdir { return '.' }

package overload;
$INC{'overload.pm'} = __FILE__;

package strict;
$INC{'strict.pm'} = __FILE__;

package warnings::register;
$INC{'warnings/register.pm'} = __FILE__;

package warnings;
$INC{'warnings.pm'} = __FILE__;

no warnings 'redefine';

sub warn {
    return syswrite( STDERR, join( ' ', @_ ) . "\n" );
}

*warnif = \&warn;

package common::sense;

$INC{'common/sense.pm'} = __FILE__;

package DBI::Const::GetInfoType;

$INC{'DBI/Const/GetInfoType.pm'} = __FILE__;

our %GetInfoType = ( 'SQL_DBMS_VER' => 18 );

package Cpanel::TailWatch::Utils::Stubs;

package Config;

use Exporter ();
use Cpanel::Binaries();

if ( exists $INC{'Config.pm'} ) {
    return 1;    #keep cplint happy
}

$INC{'Config.pm'} = __FILE__;

our %Config = (
    'so'               => 'so',
    'dlext'            => 'so',
    'dlsrc'            => 'dl_dlopen.xs',
    'perlpath'         => Cpanel::Binaries::path('perl'),
    'path_sep'         => ':',
    'd_flock'          => 'define',
    'd_fcntl_can_lock' => 'define',
    'd_lockf'          => 'define'
);

our @EXPORT = qw(%Config);    ## no critic(ProhibitAutomaticExportation)

sub import {    ## no critic(RequireArgUnpacking)
    my $pkg = shift;    ## no critic qw(Variables::ProhibitUnusedVariables); # This one's complicated.
    @_ = @EXPORT unless @_;
    my @func = grep { $_ ne '%Config' } @_;
    local $Exporter::ExportLevel = 1;
    Exporter::import( 'Config', @func ) if @func;
    return                              if @func == @_;
    my $callpkg = caller(0);
    *{"$callpkg\::Config"} = \%Config;
    return 1;
}

1;
