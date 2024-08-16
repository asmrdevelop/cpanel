package Whostmgr::DB;

# cpanel - Whostmgr/DB.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::DB::Map::Reader    ();
use Cpanel::Exception          ();
use Cpanel::Session::Constants ();
use Whostmgr::ACLS             ();
use Whostmgr::AcctInfo         ();

my %DB_OBJ_TYPE_LISTER = qw(
  user        get_dbusers
  database    get_databases
);

#returns an arrayref of: { cpuser => '..', name => '..' }
sub list_databases {
    return _list_database_objects('database');
}

#returns an arrayref of: { cpuser => '..', name => '..' }
sub list_database_users {
    return _list_database_objects('user');
}

sub list_mysql_databases_and_users {
    my $cpanel_user = shift;

    my $data;
    try {
        my $map = Cpanel::DB::Map::Reader->new( 'cpuser' => $cpanel_user, 'engine' => 'mysql' );
        $data = $map->get_dbusers_for_all_databases();
    }
    catch {
        warn Cpanel::Exception::get_string($_);
    };

    return $data;
}

sub _list_database_objects {
    my ($what_to_list) = @_;

    my $lister_method = $DB_OBJ_TYPE_LISTER{$what_to_list};

    my $dbowners_hr = _get_owned_accounts();

    my @objects;

  CPUSER:
    for my $cpuser ( keys %$dbowners_hr ) {
        my $map;
        for my $engine (qw( mysql  postgresql )) {
            if ($map) {
                $map->set_engine($engine);
            }
            else {
                try {
                    $map = Cpanel::DB::Map::Reader->new( cpuser => $cpuser, engine => $engine );
                }
                catch {
                    warn Cpanel::Exception::get_string($_);
                };

                next CPUSER if !$map;
            }

            my @names = $map->$lister_method();

            #Should not be necessary anymore...
            if ( $what_to_list eq 'user' ) {
                @names = grep { !m<\A\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E> } @names;
            }

            push @objects, map { { cpuser => $cpuser, engine => $engine, name => $_, } } @names;
        }
    }

    return \@objects;
}

sub _get_owned_accounts {

    #TODO: Remove this when/if WHM extends DB listing to non-root.
    die "Only root resellers can do this!" if !Whostmgr::ACLS::hasroot();

    my $reseller = Whostmgr::ACLS::hasroot() ? undef : $ENV{'REMOTE_USER'};
    return _get_accounts($reseller);
}

#NOTE: Mocked in tests.
*_get_accounts = \&Whostmgr::AcctInfo::get_accounts;

1;
