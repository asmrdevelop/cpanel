package Cpanel::OSSys;

# cpanel - Cpanel/OSSys.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::OSSys::Env ();
use Cpanel::Sys::Uname ();

our $VERSION = 1.5;

my $logger;
my $POSIX = 'POSIX';

*get_envtype = *Cpanel::OSSys::Env::get_envtype;

if ( !exists $INC{'POSIX.pm'} && !exists $INC{'Cpanel/POSIX/Tiny.pm'} ) {
    local $@;
    eval ' local $SIG{__DIE__} = "DEFAULT"; require Cpanel::POSIX::Tiny; $POSIX = "Cpanel::POSIX::Tiny"; #issafe';    # PPI USE OK
}
elsif ( exists $INC{'Cpanel/POSIX/Tiny.pm'} ) {
    $POSIX = "Cpanel::POSIX::Tiny";                                                                                   #issafe
}

# Last resort load POSIX module.
if ( !exists $INC{'Cpanel/POSIX/Tiny.pm'} ) {
    local $@;
    eval 'require POSIX';                                                                                             #This MUST be require(), not use().
}

sub getos { return 'linux'; }

sub uname {
    my @UNAME = Cpanel::Sys::Uname::syscall_uname();
    wantarray ? return @UNAME : return $UNAME[0];
}

sub write {
    eval $POSIX . '::write(@_);';
}

sub nice {
    eval $POSIX . "::nice($_[0]);";
}

sub setsid {
    no warnings 'redefine';
    eval '*Cpanel::OSSys::setsid = *' . $POSIX . '::setsid;';
    eval $POSIX . "::setsid()";
}

sub pipe {
    my @fds;
    eval '@fds = ' . $POSIX . "::pipe()";
    return @fds;
}

sub close {
    no warnings 'redefine';
    eval '*Cpanel::OSSys::close = *' . $POSIX . '::close;';
    eval $POSIX . '::close(@_)';
}

sub times {
    no warnings 'redefine';
    eval '*times = \&' . $POSIX . "::times;";
    goto \&times if !$@;
}

sub sysconf {
    my $const = shift;
    if ( ref $const ) {
        require Cpanel::Logger;
        Cpanel::Logger->new()->die( "sysconf cannot accept a " . scalar ref $const . " it must be passed a scalar which will be converted into a constant" );
    }
    my $res;
    my $val = ( $POSIX ne 'POSIX' ) ? ( eval $POSIX . '::constant($const,0);' ) : ( eval '&' . $POSIX . "::$const" );
    if ( !$val ) {
        require Cpanel::Logger;
        Cpanel::Logger->new()->die("Unknown constant $const for $POSIX");
    }
    eval '$res = ' . $POSIX . '::sysconf(' . $val . ');';
    return $res;
}

1;
