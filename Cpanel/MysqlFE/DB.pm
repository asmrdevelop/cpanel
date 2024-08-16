package Cpanel::MysqlFE::DB;

# cpanel - Cpanel/MysqlFE/DB.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::StatCache               ();
use Cpanel::CacheFile               ();    ## PPI USE OK -- required for Cpanel::CacheFile::NEED_FRESH
use Cpanel::CachedCommand::Save     ();
use Cpanel::CachedCommand::Utils    ();
use Cpanel::AdminBin                ();
use Cpanel::AdminBin::Call          ();
use Cpanel::Exception               ();
use Cpanel::LoadFile                ();
use Cpanel::Locale                  ();
use Cpanel::Mysql::ApiCompatibility ();
use Cpanel::Mysql::DiskUsage        ();
use Cpanel::PwCache                 ();
use Cpanel::DB                      ();
use Cpanel::DB::Map::Reader         ();

our $VERSION = 1.3;

my $DBCACHETTL = 14440;

our $mysql_status_file = "/var/cpanel/mysql_status";

sub countdbs {
    require Cpanel::UserDatastore;

    my ( $system_cachefile, $local_cachefile ) = ( Cpanel::UserDatastore::get_path($Cpanel::user) . '/mysql-db-count', Cpanel::CachedCommand::Utils::_get_datastore_filename('mysql-db-count') );
    my ( $local_cachefile_mtime, $system_cachefile_mtime ) = ( Cpanel::StatCache::cachedmtime($local_cachefile), Cpanel::StatCache::cachedmtime($system_cachefile) );
    my ( $cachefile, $cachefile_mtime ) = ( $system_cachefile_mtime > $local_cachefile_mtime ) ? ( $system_cachefile, $system_cachefile_mtime ) : ( $local_cachefile, $local_cachefile_mtime );

    if ( ( ( $cachefile_mtime + $DBCACHETTL ) > time ) ) {
        my $dbcount = Cpanel::LoadFile::loadfile($cachefile);
        if ( defined $dbcount && $dbcount ne '' ) {
            return int $dbcount;
        }
    }

    my %DBS = listdbs();

    try {
        Cpanel::CachedCommand::Save::store( 'name' => 'mysql-db-count', 'data' => ( scalar keys %DBS ) );
    }
    catch {
        local $@ = $_;
        warn unless m{Disk Quota}i;    # Sadly the error is already stringified at this point
    };

    return ( scalar keys %DBS );
}

sub listdbswithspace {
    my %DBSPACE;
    if ( $Cpanel::CPCACHE{'mysql'}{'DBSpacecached'} ) {
        if ( ref $Cpanel::CPCACHE{'mysql'}{'DB'} eq 'HASH' ) {
            foreach my $db ( keys %{ $Cpanel::CPCACHE{'mysql'}{'DB'} } ) {
                $DBSPACE{$db} = ref $Cpanel::CPCACHE{'mysql'}{'DB'}{$db} ? ( keys %{ $Cpanel::CPCACHE{'mysql'}{'DB'}{$db} } )[0] : undef;
            }
        }

        # %DBSPACE should contain a canonical list of databases, although we may
        # not have space information for all of them.
        return %DBSPACE unless grep { !defined } values %DBSPACE;
    }

    return if !countdbs();

    try {
        # Copy the canonical list of databases, since Cpanel::Mysql::DiskUsage
        # may not have full information on which ones are available.
        my @dbs = keys %DBSPACE;
        %DBSPACE = %{ Cpanel::Mysql::DiskUsage->load($Cpanel::user) };

        # If we have renamed a database, we may need to recalculate information
        # ourselves until the next time update_db_cache runs.
        die Cpanel::CacheFile::NEED_FRESH->new if grep { !defined } @DBSPACE{@dbs};    ## PPI NO PARSE -- in Cpanel::CacheFile

        $Cpanel::CPCACHE{'mysql'}{'DB'}       = \%DBSPACE;
        $Cpanel::CPCACHE{'mysql'}{'DBcached'} = 1;
    }
    catch {
        if ( !try { $_->isa('Cpanel::CacheFile::NEED_FRESH') } ) {
            local $@ = $_;
            die;
        }

        $Cpanel::context = 'mysql';
        foreach my $uitem ( split( /\n/, Cpanel::AdminBin::adminrun( 'cpmysql', 'LISTDBSWITHSPACE' ) ) ) {
            chomp $uitem;
            my ( $db, $spaceused ) = split( /\t/, $uitem );
            $DBSPACE{$db} = $spaceused;
            $Cpanel::CPCACHE{'mysql'}{'DB'}{$db} = $spaceused;
        }

        $Cpanel::CPCACHE{'mysql'}{'DBSpacecached'} = 1;
    };

    return %DBSPACE;
}

sub listdbs {
    my %DBSPACE;
    if ( ref $Cpanel::CPCACHE{'mysql'}{'DB'} eq 'HASH' ) {
        foreach my $db ( keys %{ $Cpanel::CPCACHE{'mysql'}{'DB'} } ) {
            chomp($db);
            next if !$db;
            $DBSPACE{$db} = 0;
        }
        return %DBSPACE;
    }

    $Cpanel::CPCACHE{'mysql'}{'DBcached'} = 1;

    $Cpanel::context = 'mysql';

    my $map = Cpanel::DB::Map::Reader->new( cpuser => $Cpanel::user || Cpanel::PwCache::getpwuid($>), engine => 'mysql' );
    my @DBS = $map->get_databases();

    foreach my $db (@DBS) {
        chomp $db;
        $DBSPACE{$db} = 0;
        $Cpanel::CPCACHE{'mysql'}{'DB'}{$db} = 0;
    }
    return %DBSPACE;
}

sub delhost {
    my ($host) = @_;
    return Cpanel::AdminBin::adminrun( 'cpmysql', 'DELHOST', $host );
}

sub adduserdb {
    my ( $db, $user, $privs ) = @_;

    if ( !defined $user ) {
        $Cpanel::CPERROR{'mysql'} = 'No username given';
        return;
    }
    elsif ( !defined $privs ) {
        $Cpanel::CPERROR{'mysql'} = 'No privs given';
        return;
    }

    $user = Cpanel::DB::add_prefix_if_name_and_server_need($user);
    $db   = Cpanel::DB::add_prefix_if_name_and_server_need($db);

    my @old_privs = map { tr<+>< >r } grep { length } split /\s+/, $privs;

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'mysql',
        'SET_USER_PRIVILEGES_ON_DATABASE',
        $user,
        $db,
        [ Cpanel::Mysql::ApiCompatibility::convert_legacy_privs_to_standard(@old_privs) ],
    );

    return 1;
}

sub deluserdb {
    my ( $db, $user ) = @_;

    $db   = Cpanel::DB::add_prefix_if_name_and_server_need($db);
    $user = Cpanel::DB::add_prefix_if_name_and_server_need($user);

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'mysql',
        'REVOKE_USER_ACCESS_TO_DATABASE',
        $user,
        $db,
    );

    return 1;
}

sub changeuserpasswd {
    my ( $dbuser, $pw ) = @_;

    $dbuser = Cpanel::DB::add_prefix_if_name_and_server_need($dbuser);

    my $retval = _wrap_adminbin_call( 'SET_PASSWORD', $dbuser, $pw );
    return if ref $retval eq 'HASH' && !@{ $retval->{'failures'} };
    return $retval;
}

sub _wrap_adminbin_call {
    my ( $func, @params ) = @_;

    my $result;
    my $ok;
    try {
        $result = Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', $func, @params );
        $ok     = 1;
    }
    catch {
        $Cpanel::CPERROR{'mysql'} = Cpanel::Exception::get_string($_);
    };

    return $ok ? $result : $Cpanel::CPERROR{'mysql'};
}

sub _mysql_is_remote {

    # This file is updated when update_db_cache is run
    if ( -e $mysql_status_file ) {
        my $mtime = ( stat($mysql_status_file) )[9];
        my $now   = time();
        if ( $mtime < $now || $mtime > ( $now - 86400 ) ) {    #not time warped and less the a day old
            if ( open( my $mysql_status_fh, '<', $mysql_status_file ) ) {
                local $/;
                my %mysql_status = map { ( split( /=/, $_, 2 ) )[ 0, 1 ] } split( /\n/, readline($mysql_status_fh) );
                close($mysql_status_fh);
                return $mysql_status{'remote'} if exists $mysql_status{'remote'};
            }
        }
    }

    # Fall back to priv escalation to get this if the file is out of date or non existant
    return Cpanel::AdminBin::adminrun( 'cpmysql', 'ISREMOTE' );
}

sub _initcache {
    my ($db_arg) = @_;
    alarm(3600);
    $Cpanel::context = 'mysql';
    $Cpanel::CPCACHE{'mysql'}{'cached'} = 1;
    foreach my $line ( split( /\n/, Cpanel::AdminBin::adminrun( 'cpmysql', 'DBCACHE', $db_arg ) ) ) {
        $line =~ s/\n//g;
        my ( $ttype, $item, $val, $ptv ) = split( /\t/, $line );
        next unless defined $item;
        if ( defined $ptv ) {
            $Cpanel::CPCACHE{'mysql'}->{$ttype}->{$item}->{$val} = $ptv;
        }
        elsif ( defined $val ) {    # need to preserve a hash structure for all usage
            $Cpanel::CPCACHE{'mysql'}->{$ttype}->{$item}->{$val} = 1;
        }
        else {                      # need to preserve a hash structure for all usage
            $Cpanel::CPCACHE{'mysql'}->{$ttype}->{$item} = 1;
        }
    }

    $Cpanel::CPCACHE{'mysql'}{'DBSpacecached'} = 1;
    foreach my $db ( keys %{ $Cpanel::CPCACHE{'mysql'}{'DB'} } ) {
        $Cpanel::CPCACHE{'mysql'}{'DB'}{$db} = $Cpanel::CPCACHE{'mysql'}{'DBDISKUSED'}{$db} || 0;
    }

    foreach my $running ( keys %{ $Cpanel::CPCACHE{'mysql'}{'ISRUNNING'} } ) {
        $Cpanel::CPCACHE{'mysql'}{'ALIVE'} = $running;
    }

    if ( !$Cpanel::CPCACHE{'mysql'}{'ALIVE'} && !$Cpanel::CPERROR{'mysql'} ) {

        # only set error if unset
        $Cpanel::CPERROR{'mysql'} = 'The mysql server is offline.';
    }
    return;
}

1;
