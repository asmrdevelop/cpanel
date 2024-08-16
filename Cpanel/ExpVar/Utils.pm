package Cpanel::ExpVar::Utils;

# cpanel - Cpanel/ExpVar/Utils.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

## no critic qw(TestingAndDebugging::RequireUseWarnings) -- use warnings not enabled in this module to preserve original behava[ior before refactoring

use Cpanel::AdminBin      ();
use Cpanel::DIp::Owner    ();
use Cpanel::ExpVar::Cache ();
use Cpanel::GlobalCache   ();
use Cpanel::Locale        ();
use Cpanel::NAT           ();
use Cpanel::Parser::Vars  ();

sub has_expansion {
    die "Cpanel::ExpVar::Utils is not an expansion module";
}

sub expand {
    die "Cpanel::ExpVar::Utils is not an expansion module";
}

# For test purposes
sub clear_varcache {
    %Cpanel::ExpVar::Cache::VARCACHE = ();
    return;
}

sub chomped_adminrun {
    my @args   = @_;
    my $result = Cpanel::AdminBin::adminrun(@args) || '';
    chomp $result;
    return $result;
}

sub initialize_mysql_version_varcache {

    my $mysqlversion = $Cpanel::ExpVar::Cache::VARCACHE{'$mysqlversion'};

    if ( !defined $mysqlversion ) {
        if ( $> == 0 ) {
            require Cpanel::MysqlUtils::Version;
            $mysqlversion = Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default();
        }
        else {
            $mysqlversion = Cpanel::AdminBin::adminrun( 'cpmysql', 'VERSION' ) || '';
        }
        chomp($mysqlversion);
        $Cpanel::ExpVar::Cache::VARCACHE{'$mysqlversion'} = $mysqlversion;
    }

    my $locale            = Cpanel::Locale->get_handle();
    my $mysql_sane        = 1;
    my $mysql_sane_errmsg = $locale->maketext("[asis,MySQL] is sane.");

    require Cpanel::MysqlUtils::MyCnf::Full;
    my $my_cnf        = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf();
    my $old_passwords = $my_cnf->{'mysqld'}{'old_passwords'};

    if ( !defined $old_passwords ) {
        $old_passwords = 0;
    }

    if (   $old_passwords == 1
        || uc($old_passwords) eq "ON"
        || uc($old_passwords) eq "YES"
        || uc($old_passwords) eq "TRUE" ) {
        $old_passwords = 1;
    }

    if ( $old_passwords == 1 ) {
        require Cpanel::MysqlUtils::Version;

        if ( Cpanel::MysqlUtils::Version::cmp_versions( $mysqlversion, '5.6' ) >= 0 ) {
            $mysql_sane        = 0;
            $mysql_sane_errmsg = $locale->maketext("[asis,cPanel] does not support [asis,old_passwords=1] on this version of [asis,MySQL].");
        }
    }

    $Cpanel::ExpVar::Cache::VARCACHE{'$mysql_sane'}        = $mysql_sane;
    $Cpanel::ExpVar::Cache::VARCACHE{'$mysql_sane_errmsg'} = $mysql_sane_errmsg;
    return;
}

sub hasdedicatedip {
    my $dipkey = '$hasdedicatedip_' . $Cpanel::CPDATA{'DNS'};
    return $Cpanel::ExpVar::Cache::VARCACHE{$dipkey} if exists $Cpanel::ExpVar::Cache::VARCACHE{$dipkey};
    return ( ( $Cpanel::ExpVar::Cache::VARCACHE{$dipkey} = Cpanel::DIp::Owner::get_dedicated_ip_owner( get_local_ip() ) eq $Cpanel::user ) ? 1 : 0 );
}

sub haspostgres {
    return $Cpanel::ExpVar::Cache::VARCACHE{'$haspostgres'} if exists $Cpanel::ExpVar::Cache::VARCACHE{'$haspostgres'};
    return ( $Cpanel::ExpVar::Cache::VARCACHE{'$haspostgres'} = Cpanel::GlobalCache::data( 'cpanel', 'has_postgres' ) );
}

sub has_cloudlinux {
    return $Cpanel::ExpVar::Cache::VARCACHE{'$hascloudlinux'} if exists $Cpanel::ExpVar::Cache::VARCACHE{'$hascloudlinux'};
    return ( $Cpanel::ExpVar::Cache::VARCACHE{'$hascloudlinux'} = Cpanel::GlobalCache::data( 'cpanel', 'has_cloudlinux' ) );
}

sub get_public_ip {
    my $ipkey = '$public_ip_' . $Cpanel::CPDATA{'DNS'};
    return ( $Cpanel::ExpVar::Cache::VARCACHE{$ipkey} //= Cpanel::NAT::get_public_ip( get_local_ip() ) );
}

sub get_local_ip {
    my $ipkey = '$local_ip_' . $Cpanel::CPDATA{'DNS'};

    return $Cpanel::ExpVar::Cache::VARCACHE{$ipkey} //= do {
        my $ip;

        if ($Cpanel::rootlogin) {
            require Cpanel::DIp::MainIP;
            $ip = Cpanel::DIp::MainIP::getmainip();
        }
        else {
            $ip = $Cpanel::CPDATA{'IP'} // do {
                require Cpanel::UserDomainIp;
                Cpanel::UserDomainIp::getdomainip( $Cpanel::CPDATA{'DNS'} );
            };
        }

        $ip;
    };
}

sub get_basefilename {
    ## e.g. /frontend/x3/
    my $rootpath = ( $Cpanel::appname eq 'webmail' ? '/webmail/' : '/frontend/' ) . $Cpanel::CPDATA{'RS'} . '/';

    ## e.g. ./frontend/x3/ssl/keys.html
    my $basedir = $Cpanel::Parser::Vars::firstfile;

    ## remove e.g. ./frontend/x3/ssl/
    my @BDIR         = split( m{/+}, $basedir );
    my $basefilename = pop(@BDIR);

    ## remove extension
    my $index = index( $basefilename, '.' );
    return -1 == $index ? $basefilename : substr( $basefilename, 0, $index );
}

sub get_basefile {
    ## e.g. /frontend/x3/
    my $rootpath = ( $Cpanel::appname eq 'webmail' ? '/webmail/' : '/frontend/' ) . $Cpanel::CPDATA{'RS'} . '/';

    ## e.g. ./frontend/x3/ssl/keys.html
    my $basefile = _strip_leading_path( $Cpanel::Parser::Vars::firstfile, $rootpath );

    ## remove extension
    my $index = index( $basefile, '.' );
    return -1 == $index ? $basefile : substr( $basefile, 0, $index );
}

sub get_basedir {
    my $rootpath = ( $Cpanel::appname eq 'webmail' ? '/webmail/' : '/frontend/' ) . $Cpanel::CPDATA{'RS'} . '/';

    my $basedir = $Cpanel::Parser::Vars::firstfile;

    my @BDIR = split( m{/+}, $basedir );
    pop(@BDIR);
    $basedir = _strip_leading_path( join( '/', @BDIR ), $rootpath );

    my $index = index( $basedir, '.' );
    return -1 == $index ? $basedir : substr( $basedir, 0, $index );
}

sub _strip_leading_path {
    my ( $basedir, $leading_path ) = @_;

    substr( $basedir, 0, 1, '' ) if rindex( $basedir, '.', 0 ) == 0;
    substr( $basedir, 0, 1, '' ) while rindex( $basedir, '//', 0 ) == 0;
    return ''                                       if ( $basedir . '/' ) eq $leading_path;
    substr( $basedir, 0, length $leading_path, '' ) if rindex( $basedir, $leading_path, 0 ) == 0;

    return $basedir;

}

1;
