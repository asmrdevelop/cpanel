package Cpanel::DB::Map::Rebuild::Mysql;

# cpanel - Cpanel/DB/Map/Rebuild/Mysql.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::ArrayFunc::Uniq     ();
use Cpanel::DB::Utils           ();
use Cpanel::MysqlUtils::Connect ();
use Cpanel::MysqlUtils::Grants  ();
use Cpanel::MysqlUtils::Unquote ();
use Cpanel::Validate::DB::Name  ();
use Cpanel::Validate::DB::User  ();

#Returns a hashref of:
#{
#   db1 => [],
#   db2 => [ 'dbuser1', .. ],
#}
#
#The hashref does NOT include the dbowner.
#
sub read_dbmap_data {
    my ($username) = @_;

    my $dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle();

    my $dbowner = Cpanel::DB::Utils::username_to_dbowner($username);

    my $grants_ar = Cpanel::MysqlUtils::Grants::show_grants_for_user( $dbh, $dbowner );

    my %db_dbusers;
    for my $grant_obj (@$grants_ar) {
        next if $grant_obj->quoted_db_obj() ne '*';
        next if $grant_obj->db_privs() eq 'USAGE';

        my $dbname = $grant_obj->db_name();

        my ( $is_valid, $err );
        try {
            $is_valid = Cpanel::Validate::DB::Name::verify_mysql_database_name($dbname);
        }
        catch {
            $err = $_;
        };

        if ($err) {
            last if try { $err->isa('Cpanel::Exception::Reserved') };
            last if try { $err->isa('Cpanel::Exception::InvalidParameter') };
            die $err;
        }

        next if !$is_valid;

        my $dbname_pattern = Cpanel::MysqlUtils::Unquote::unquote_identifier( $grant_obj->quoted_db_name() );

        #We could use Cpanel::MysqlUtils::Show::show_grants_on_dbs here, but that function
        #does lots of other things that we don’t need. The below is much faster.
        my $users_ar = $dbh->selectcol_arrayref(
            "SELECT DISTINCT user FROM mysql.db WHERE db = ? ORDER BY user",
            undef,
            $dbname_pattern,
        );

        my @dbusers;
        foreach my $dbuser ( Cpanel::ArrayFunc::Uniq::uniq( grep { $_ ne $dbowner } @$users_ar ) ) {

            my ( $is_valid, $err );
            try {
                $is_valid = Cpanel::Validate::DB::User::verify_mysql_dbuser_name($dbuser);
            }
            catch {
                $err = $_;
            };

            if ($err) {
                last if try { $err->isa('Cpanel::Exception::Reserved') };
                last if try { $err->isa('Cpanel::Exception::InvalidParameter') };
                die $err;
            }

            push @dbusers, $dbuser if $is_valid;
        }

        $db_dbusers{$dbname} = \@dbusers;
    }

    return \%db_dbusers;
}

1;
