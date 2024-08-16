package Cpanel::MysqlUtils::InnoDB;

# cpanel - Cpanel/MysqlUtils/InnoDB.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## no critic qw(RequireUseWarnings) -- Hasn't been audited for warnings safety
use strict;

use Cpanel::SafeFile             ();
use Cpanel::StringFunc::File     ();
use Cpanel::MysqlUtils::Restart  ();
use Cpanel::LoadFile             ();
use Cpanel::Logger               ();
use Cpanel::FileUtils::TouchFile ();
my $logger = Cpanel::Logger->new();

sub is_enabled {
    my $my_cnf_txt = Cpanel::LoadFile::loadfile('/etc/my.cnf') || "";

    if ( $my_cnf_txt =~ m/^\s*skip-innodb/m ) {
        return 0;
    }
    return 1;
}

sub is_enabled_on_dbh {
    my ($dbh) = @_;

    my $engines_ar = $dbh->selectall_arrayref(
        'SHOW ENGINES',
        { Slice => {} },    #gives hashes instead of arrays
    );

    my $has_innodb;

    for my $engine_hr (@$engines_ar) {
        next if $engine_hr->{'Engine'} ne 'InnoDB';
        next if $engine_hr->{'Support'} ne 'YES' && $engine_hr->{'Support'} ne 'DEFAULT';
        $has_innodb = 1;
        last;
    }

    return $has_innodb || 0;
}

sub enable {
    Cpanel::StringFunc::File::remlinefile( '/etc/my.cnf', 'skip-innodb' );

    return Cpanel::MysqlUtils::Restart::restart();
}

sub disable {
    if ( !-e '/etc/my.cnf' ) { $logger->warn("No /etc/my.cnf .. creating.."); Cpanel::FileUtils::TouchFile::touchfile('/etc/my.cnf'); }
    my $ml = Cpanel::SafeFile::safeopen( \*MYC, '+<', '/etc/my.cnf' );
    if ( !$ml ) {
        $logger->warn("Could not edit /etc/my.cnf: $!");
        return;
    }
    my @MYCNF = <MYC>;
    if ( !grep( /\[mysqld\]/, @MYCNF ) ) {
        print MYC "\n[mysqld]\n";
        print MYC "skip-innodb\n";
    }
    else {
        if ( !grep( /^\s*skip-innodb/, @MYCNF ) ) {
            seek( MYC, 0, 0 );
            foreach my $line (@MYCNF) {
                print MYC $line;
                if ( $line =~ m/^\s*\[mysqld\]/ ) {
                    print MYC "skip-innodb\n";
                }
            }
            truncate( MYC, tell(MYC) );
        }
    }
    Cpanel::SafeFile::safeclose( \*MYC, $ml );

    return Cpanel::MysqlUtils::Restart::restart();
}

1;
