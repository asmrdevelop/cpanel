package Cpanel::Validate::DB::Conflict;

# cpanel - Cpanel/Validate/DB/Conflict.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::App ();

=encoding utf-8

=head1 NAME

Cpanel::Validate::DB::Conflict - Functions to determine if database names or users conflict.

=head1 SYNOPSIS

    use Cpanel::Validate::DB::Conflict;

    my $conflicts = Cpanel::Validate::DB::Conflict::get_dbowner_name_conflicts($dbowner);

=head2 get_dbowner_name_conflicts($user_or_dbname)

This function determines if there is a MySQL or PostgreSQL (if installed) user or database
that conflicts with the passed in dbowner name.

=over 2

=item Input

=over 3

=item $dbowner C<SCALAR>

    The dbowner name for which to check for conflicts.

=back

=item Output

An arrayref, each of whose members describes a conflict:

    [
      {
         managed         => A boolean value indicating if the conflict is with a managed resource.
         resource_type   => A string with possible values 'database' and 'user' indicating which type of resource the
                            dbowner name conflicted with.
         database_engine => The database engine where the conflict occurred. Can have the values 'MYSQL' or 'PGSQL'.
         resource_owner  => (optional) If the conflict is with a managed resource, the caller of this method has
                            root privileges, and this method was called from WHM context, then this string will
                            indicate which cPanel user owns the managed resource. Otherwise, it will be undef.
      }
    ]

If there are no conflicts, then the arrayref is empty.

=back

=cut

sub get_dbowner_name_conflicts {
    my ($dbowner) = @_;
    require Cpanel::MysqlUtils::Command;

    my $caller_has_root_and_in_whm_context = 0;
    if ( Cpanel::App::is_whm() ) {
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        $caller_has_root_and_in_whm_context = Whostmgr::ACLS::hasroot() ? 1 : 0;
    }

    my @conflict_info;

    require Cpanel::Services::Enabled;
    require Cpanel::MysqlUtils::Connect;
    my $dbh       = Cpanel::Services::Enabled::is_provided("mysql") ? Cpanel::MysqlUtils::Connect::get_dbi_handle() : undef;
    my @conflicts = _check_dbowner_conflict_by_engine(
        {
            'dbowner'                    => $dbowner,
            'dbengine'                   => 'MYSQL',
            'user_exists_cr'             => \&Cpanel::MysqlUtils::Command::user_exists,
            'db_exists_cr'               => sub { return 0 },                             # ignore database conflicts for MySQL
                                                                                          # A MySQL database is not tied to a MySQL user as the PGSQL databases are
            'caller_has_root_and_in_WHM' => $caller_has_root_and_in_whm_context,
            'dbh'                        => $dbh,
        }
    );
    push @conflict_info, @conflicts if @conflicts;

    require Cpanel::PostgresAdmin::Check;
    require Cpanel::Postgres::Connect;
    require Cpanel::PostgresUtils;
    $dbh       = Cpanel::PostgresAdmin::Check::is_enabled_and_configured() ? Cpanel::Postgres::Connect::get_dbi_handle() : undef;
    @conflicts = _check_dbowner_conflict_by_engine(
        {
            'dbowner'                    => $dbowner,
            'dbengine'                   => 'PGSQL',
            'user_exists_cr'             => \&Cpanel::PostgresUtils::role_exists,
            'db_exists_cr'               => \&Cpanel::PostgresUtils::db_exists,
            'caller_has_root_and_in_WHM' => $caller_has_root_and_in_whm_context,
            'dbh'                        => $dbh,
        }
    );
    push @conflict_info, @conflicts if @conflicts;

    return \@conflict_info;
}

#----------------------------------------------------------------------

sub _check_dbowner_conflict_by_engine {
    my ($opts) = @_;

    my ( $dbh, $dbowner, $dbengine, $user_exists_cr, $db_exists_cr, $caller_has_root_and_in_whm_context ) = @{$opts}{qw( dbh dbowner dbengine user_exists_cr db_exists_cr caller_has_root_and_in_WHM )};

    my @conflicts;
    my $resource_owner = _get_cpuser_from_map_for_db( $dbowner, $dbengine );
    if ( ( !$dbh && $resource_owner ) || ( $dbh && $db_exists_cr->( $dbowner, $dbh ) ) ) {
        push @conflicts,
          {
            'managed'         => length $resource_owner ? 1 : 0,
            'resource_type'   => 'database',
            'database_engine' => $dbengine,
            'resource_owner'  => $caller_has_root_and_in_whm_context ? $resource_owner : undef,
          };
    }

    $resource_owner = _get_cpuser_from_map_for_dbuser( $dbowner, $dbengine );
    if ( ( !$dbh && $resource_owner ) || ( $dbh && $user_exists_cr->( $dbowner, $dbh ) ) ) {
        push @conflicts,
          {
            'managed'         => length $resource_owner ? 1 : 0,
            'resource_type'   => 'user',
            'database_engine' => $dbengine,
            'resource_owner'  => $caller_has_root_and_in_whm_context ? $resource_owner : undef,
          };
    }

    return @conflicts;
}

sub _get_cpuser_from_map_for_dbuser {
    my ( $dbuser, $dbengine ) = @_;

    return _get_cpuser_from_map_by_function_name( $dbuser, $dbengine, 'find_by_dbuser' );
}

sub _get_cpuser_from_map_for_db {
    my ( $db, $dbengine ) = @_;

    return _get_cpuser_from_map_by_function_name( $db, $dbengine, 'find_by_db' );
}

sub _get_cpuser_from_map_by_function_name {
    my ( $search_item, $dbengine, $find_func ) = @_;

    require Cpanel::DB::Map::Collection;

    my $collection = Cpanel::DB::Map::Collection->new( { 'db' => $dbengine } );

    my $map = $collection->$find_func($search_item);

    return $map ? $map->get_cpuser() : undef;
}

1;
