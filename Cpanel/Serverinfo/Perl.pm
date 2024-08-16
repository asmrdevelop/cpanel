package Cpanel::Serverinfo::Perl;

# cpanel - Cpanel/Serverinfo/Perl.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# cnanel12 - Cpanel::Serverinfo::Perl;             Copyright(c) 1999-2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

our $VERSION = '1.0';

use Cpanel::CachedCommand    ();
use Cpanel::SafeRun::Dynamic ();
use Cpanel::GlobalCache      ();

sub path {
    return '/usr/bin/perl';
}

sub version {
    my $perlv = Cpanel::GlobalCache::cachedcommand( 'cpanel', path(), '-v' );
    if ( $perlv =~ /v(\d+\.\d+\.\d+)/ ) {
        return $1;
    }
    else {
        return 'unknown';
    }
}

sub modules {
    return Cpanel::SafeRun::Dynamic::saferundynamic('/usr/local/cpanel/bin/perlmodules');
}

sub linkedmodules {
    return Cpanel::SafeRun::Dynamic::saferundynamic( '/usr/local/cpanel/bin/perlmodules', '-l', 'manpage.html' );
}

sub baselib {
    return Cpanel::CachedCommand::cachedcommand( path(), '-e', 'require Config;my $baselib=$Config::Config{privlib};$baselib =~ s/\/?\Q$Config::Config{version}\E$//;print $baselib;' );
}

sub installsitelib {
    return Cpanel::CachedCommand::cachedcommand( path(), '-e', 'require Config;print$Config::Config{installsitelib};' );
}

sub archname {
    return Cpanel::CachedCommand::cachedcommand( path(), '-e', 'require Config;print $Config::Config{archname};' );
}

1;
