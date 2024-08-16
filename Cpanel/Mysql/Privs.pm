package Cpanel::Mysql::Privs;

# cpanel - Cpanel/Mysql/Privs.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception           ();
use Cpanel::MysqlUtils::Version ();
use Cpanel::Mysql::Version      ();

my @SUPPORTED_MYSQL_PRIVS = (
    'ALTER ROUTINE',
    'ALTER',
    'CREATE ROUTINE',
    'CREATE TEMPORARY TABLES',
    'CREATE VIEW',
    'CREATE',
    'DELETE',
    'DROP',
    'EXECUTE',
    'INDEX',
    'INSERT',
    'LOCK TABLES',
    'REFERENCES',
    'SELECT',
    'SHOW VIEW',
    'UPDATE',
);

my %VERSION_PRIVS_DBI = (
    50106 => [
        'EVENT',

        #We used to prevent adding TRIGGER when MySQL's "log_bin" was enabled,
        #but, we still allowed granting ALL PRIVILEGES, which includes TRIGGER
        #privileges. So, as of 11.42, we allow TRIGGER regardless of "log_bin".
        'TRIGGER',
    ],
);

my %VERSION_PRIVS_SHORT = (
    '5.1' => $VERSION_PRIVS_DBI{50106},
);

my $privs_regexp;

sub get_mysql_privileges_lookup {
    my $dbh = shift or die "DBI handle needed";

    my %lookup;
    @lookup{@SUPPORTED_MYSQL_PRIVS} = ();

    my $dbh_version = $dbh->{'mysql_serverversion'};

    for my $release ( keys %VERSION_PRIVS_DBI ) {
        if ( $dbh_version >= $release ) {
            @lookup{ @{ $VERSION_PRIVS_DBI{$release} } } = ();
        }
    }

    $_ = 1 for values %lookup;

    return wantarray ? %lookup : \%lookup;
}

sub verify_privileges {
    my @privs = @_;

    my %privs_lookup;
    @privs_lookup{ @SUPPORTED_MYSQL_PRIVS, 'ALL', 'ALL PRIVILEGES' } = ();

    my $mysql_version = Cpanel::Mysql::Version::get_mysql_version();

    for my $version ( keys %VERSION_PRIVS_SHORT ) {
        if ( Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, $version ) ) {
            @privs_lookup{ @{ $VERSION_PRIVS_SHORT{$version} } } = ();
        }
    }

    my @invalid_privs = grep { !exists $privs_lookup{$_} } @privs;
    if (@invalid_privs) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The following [asis,MySQL] [numerate,_1,privilege is,privileges are] invalid: [list_and_quoted,_2]', [ scalar(@invalid_privs), \@invalid_privs ] );
    }

    return 1;
}

#----------------------------------------------------------------------

#Should this be here anymore? It's no longer used in this module,
#and no user-facing code paths seem to reach it as of 11.42 development.
#
#It's also not complete; root or a user without ~/.my.cnf will get nothing.
#
sub checkbinlog {    #i.e., whether the binary log is OFF
    my $self = shift || {};

    return $self->{'_cached_binlog'} if exists $self->{'_cached_binlog'};

    if ( $self->{'dbh'} ) {
        my $value;
        my $dbh  = $self->{'dbh'};
        my $data = $dbh->selectrow_hashref('SHOW VARIABLES LIKE "log_bin"');
        $value = $data->{'Value'};
        return $self->{'_cached_binlog'} = ( $value eq 'OFF' ) ? 0 : 1;
    }

    require Cpanel::PwCache;
    my ( $user, $homedir ) = ( Cpanel::PwCache::getpwuid($>) )[ 0, 7 ];
    if ( $> != 0 && !-e $homedir . '/.my.cnf' ) {
        require Cpanel::AdminBin;
        $self->{'_cached_binlog'} = Cpanel::AdminBin::adminrun( 'cpmysql', 'CHECKBINLOG' );
        return $self->{'_cached_binlog'};
    }

    #XXX: This is added as of 11.42 to make any potential bugs complain loudly.
    die "Unimplemented logic!";
}

1;
