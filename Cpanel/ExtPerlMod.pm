package Cpanel::ExtPerlMod;

# cpanel - Cpanel/ExtPerlMod.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Test with
# perl -MData::Dumper -MCpanel::XMLParser -e 'print Data::Dumper::Dumper(Cpanel::XMLParser::XMLin("<html><pig><cow></cow></pig></html>"));'

use Cpanel::SafeStorable ();
use IPC::Open3           ();
use Cpanel::Binaries     ();

our $VERSION = '1.0';

sub ExtPerlMod_init {

}

sub func {
    my ( $func, $rargs, $store ) = @_;

    my (@FMOD)  = split( /::/, $func );
    my $modfunc = pop(@FMOD);
    my $module  = join( '::', @FMOD );

    my $res;
    my $code = "require $module;\n";
    if ( ref $rargs ) {
        $code .= "require Cpanel::SafeStorable;\n";
        $code .= "${module}::$modfunc(Cpanel::SafeStorable::fd_retrieve(\\*STDIN));\n";
    }
    else {
        $code .= "local \$/;\n";
        $code .= "${module}::$modfunc(readline(\\*STDIN));\n";
    }
    my $pid = IPC::Open3::open3( my $w_fh, my $r_fh, '>&STDERR', Cpanel::Binaries::path('perl'), '-e', $code );
    if ($pid) {
        if ( ref $rargs ) {
            Storable::nstore_fd( $rargs, $w_fh );
        }
        else {
            print {$w_fh} $rargs;
        }
        close($w_fh);

        if ($store) {
            $res = Cpanel::SafeStorable::fd_retrieve($r_fh);
        }
        else {
            local $/;
            $res = readline($r_fh);
        }

        close($r_fh);
        waitpid( $pid, 0 );
    }
    return $res;
}

sub serialize {
    my @LIST = map { "'" . $_ . "'" } @{ $_[0] };
    return join( ',', @LIST );
}

1;
