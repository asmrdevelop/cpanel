package Cpanel::DeliveryReporter;    # Adds into main namespace

# cpanel - Cpanel/DeliveryReporter/Basic.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- Not safe yet

our $VERSION = 1.3;

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = { 'dbh' => $OPTS{'dbh'} };
    if ( $OPTS{'user'} )    { $self->{'user'}    = $OPTS{'user'}; }
    if ( $OPTS{'webmail'} ) { $self->{'webmail'} = $OPTS{'webmail'}; }

    return bless $self, $class;
}

sub group_stats {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::RequireArgUnpacking)
    my $self = shift;
    bless $self;     ## no critic qw(ClassHierarchies::ProhibitOneArgBless)
    my %OPTS = @_;

    my $startdate    = int( $OPTS{'startdate'} || 0 ) || int( $OPTS{'starttime'} || 0 );
    my $enddate      = int( $OPTS{'enddate'}   || 0 ) || int( $OPTS{'endtime'}   || 0 );
    my $deliverytype = ( $OPTS{'deliverytype'} || '' ) eq 'remote' ? 'remote' : ( $OPTS{'deliverytype'} || '' ) eq 'remote_or_faildefer' ? 'remote_or_faildefer' : ( $OPTS{'deliverytype'} || '' ) eq 'local' ? 'local' : 0;
    my $sender       = $OPTS{'sender'};

    my $needs_fail_defer = ( !$deliverytype || ( $deliverytype && $deliverytype eq 'remote_or_faildefer' ) );

    my %ROWMAP = (
        'USER'         => 'USER',
        'SUCCESSCOUNT' => 'SUCCESSCOUNT',
        'TOTALSIZE'    => 'TOTALSIZE',
        'SENDCOUNT'    => 'SENDCOUNT',
        ( $needs_fail_defer ? ( 'FAILCOUNT' => 'FAILCOUNT', 'DEFERCOUNT' => 'DEFERCOUNT', 'DEFERFAILCOUNT' => 'DEFERFAILCOUNT' ) : () )
    );
    my $dir        = lc( $OPTS{'dir'}         || '' ) eq 'asc' ? 'ASC' : 'DESC';
    my $startIndex = int( $OPTS{'startIndex'} || 0 );
    my $results    = int( $OPTS{'results'}    || 0 );
    my $sort       = $ROWMAP{ ( $OPTS{'sort'} || '' ) } || 'SENDCOUNT';

    # for main query
    my $main_order_by = ( $OPTS{'sort'}  || '' ) eq 'none' ? '' : " ORDER BY $sort $dir ";
    my $main_group_by = ( $OPTS{'group'} || '' ) eq 'none' ? '' : ( " GROUP BY " . ( $OPTS{'group'} eq 'domain' ? 'DOMAIN, USER' : "USER" ) );

    my $is_user_restricted = $self->{'user'} || $self->{'webmail'} ? 1 : 0;

    # for subqueries
    my %WHERES;
    my @tables = ( 'x', 's', ( $needs_fail_defer ? ( 'f', 'd' ) : () ) );

    foreach my $table (@tables) {
        $WHERES{$table} = " WHERE " . join(
            ' AND ', 1,
            ( $table =~ m/^s/ && $OPTS{'deliverytype'} ? ( $OPTS{'deliverytype'} =~ /remote/i ? " ($table.transport_is_remote='1')  " : " ($table.transport_is_remote='0')" ) : () ),
            ( $self->{'user'}                          ? $self->_build_user_query()                                                                                           : () ),
            ( $self->{'webmail'}                       ? $self->_build_webmail_query()                                                                                        : () ),
            ( $sender                                  ? " (x.sender=" . $self->{'dbh'}->quote($sender) . ") "                                                                : () ),
            join(
                ' AND ',
                1,
                ( $startdate ? " (" . $table . ".sendunixtime >= " . int($startdate) . ") " : () ),
                ( $enddate   ? " (" . $table . ".sendunixtime <= " . int($enddate) . ") "   : () )
            ),
        );

    }
    $WHERES{'inprogress'} = " WHERE " . join(    # cannot limit to dates as we are looking for the absense of data
        ' AND ', 1,
        ( $self->{'user'}    ? $self->_build_user_query()                            : () ),
        ( $self->{'webmail'} ? $self->_build_webmail_query()                         : () ),
        ( $sender            ? " (x.sender=" . $self->{'dbh'}->quote($sender) . ") " : () ),
        "  (failures.msgid IS NULL and defers.msgid IS NULL and smtp.msgid IS NULL) ",

        # We do restrict the time to startdate (or two hours before now() if no startdate) and after now as if there is no event in side that block there never will be
        "(x.sendunixtime >= " . ( ( $startdate && ( $startdate > ( time() - 7200 ) ) ) ? " " . int($startdate) . " " : " strftime('%s', 'now', '-2 HOUR') " ) . " AND " . " x.sendunixtime <= strftime('%s', 'now', '+2 HOUR')) "
    );

    my $group_by = ( $OPTS{'group'} || '' ) eq 'domain' ? 'GROUP BY domain, user' : 'GROUP BY user';

    my @sub_queries;

    # sends
    push @sub_queries, "
-- sends query
 select
 x.domain, x.user, COUNT(msgid) as itemcount, 0 as totalsize, 'sends' as what
 from
 sends x
 $WHERES{'x'}
 $group_by
-- end sends query
";

    # inprogress
    if ( $OPTS{'needs_in_progress'} ) {
        push @sub_queries, "
-- inprogress query
select
 x.domain, x.user, SUM( CASE WHEN failures.msgid IS NULL and defers.msgid IS NULL and smtp.msgid IS NULL THEN 1 ELSE 0 END ) as itemcount, 0 as totalsize, 'inprogress' as what
from
 sends x
 LEFT JOIN smtp ON (x.msgid=smtp.msgid)
 LEFT JOIN failures ON (x.msgid=failures.msgid)
 LEFT JOIN defers ON (x.msgid=defers.msgid)
 $WHERES{'inprogress'}
 $group_by
-- end inprogress query
";
    }

    # success
    push @sub_queries, $self->_generate_group_stats_subquery( 'table' => 'smtp', 'key' => 's', 'group_by' => $group_by, 'where' => $WHERES{'s'}, 'name' => 'smtp' );

    if ($needs_fail_defer) {

        # failures
        push @sub_queries, $self->_generate_group_stats_subquery( 'table' => 'failures', 'key' => 'f', 'group_by' => $group_by, 'where' => $WHERES{'f'}, 'name' => 'failures' );

        # defers
        push @sub_queries, $self->_generate_group_stats_subquery( 'table' => 'defers', 'key' => 'd', 'group_by' => $group_by, 'where' => $WHERES{'d'}, 'name' => 'defers' );
    }

    my $count_query = "select " . join(
        ",\n",
        ( $OPTS{'nodomain'} ? () : 'domain as DOMAIN' ),
        ( $OPTS{'nouser'}   ? () : 'user as USER' ),
        ("sum( CASE WHEN what = 'sends' THEN itemcount ELSE 0 END ) as SENDCOUNT"),
        ( $OPTS{'nosuccess'}         ? ()                                                                                  : "sum( CASE WHEN what = 'smtp' THEN itemcount ELSE 0 END ) as SUCCESSCOUNT" ),
        ( $OPTS{'needs_in_progress'} ? "sum( CASE WHEN what = 'inprogress' THEN itemcount ELSE 0 END ) as INPROGRESSCOUNT" : () ),
        ( $OPTS{'nosize'}            ? ()                                                                                  : "sum(totalsize) as TOTALSIZE" ),

        (
            $needs_fail_defer
            ? (
                "sum( CASE WHEN what = 'failures' THEN itemcount ELSE 0 END ) as FAILCOUNT", "sum( CASE WHEN what = 'defers' THEN itemcount ELSE 0 END ) as DEFERCOUNT",
                "sum( CASE WHEN what in ('defers', 'failures') THEN itemcount ELSE 0 END ) as DEFERFAILCOUNT"
              )
            : ()
        )
      )
      . " from " . "("
      . join( "\nUNION ALL\n", @sub_queries )
      . ") as t "    #add sub queries
      . $self->_generate_main_where( $OPTS{'filters'} ) . $main_group_by . $self->_generate_main_having( $OPTS{'filters'} ) . $main_order_by;

    my $query = $count_query . ( $results ? " LIMIT $startIndex,$results" : '' ) . ';';
    $count_query = "select count(*) from ($count_query) s;";

    return ( $query, $count_query ) if $self->{'test_mode'};

    if ( $Cpanel::Debug::level > 3 ) {
        print STDERR "[DeliveryReporter::group_stats for $OPTS{'group'}] " . $query . "\n\n\n\n";
    }

    my $rows = $self->{'dbh'}->selectall_arrayref( $query, { Slice => {} } );
    my ($count_rows) = $self->{'dbh'}->selectrow_array( $count_query, { Slice => {} } );

    return $rows if !wantarray;

    return ( $rows, $count_rows );
}

my @SEARCHALL_COLUMNS = qw(USER DOMAIN);

#Columns that are filtered in WHERE; everything else is filtered in HAVING.
my @WHERE_COLUMNS = qw(USER DOMAIN);

my @HAVING_COLUMNS = qw(
  DEFERCOUNT
  FAILCOUNT
  FAILDEFERCOUNT
  INPROGRESSCOUNT
  SENDCOUNT
  SUCCESSCOUNT
  TOTALSIZE
);

my %is_integer;
@is_integer{@HAVING_COLUMNS} = ();

my %TYPE_CONVERSION = (
    'contains' => 'LIKE',
    'begins'   => 'LIKE',
    'eq'       => '=',
    '=='       => '=',
    'gt'       => '>',
    'lt'       => '<',
);

sub _generate_main_where {
    my $where_query = shift->_generate_sql_where_from_filters( $_[0], \@WHERE_COLUMNS );
    return '' if !$where_query;
    return ' WHERE ' . $where_query . ' ';
}

sub _generate_main_having {
    my $having_query = shift->_generate_sql_where_from_filters( $_[0], \@HAVING_COLUMNS );
    return '' if !$having_query;
    return ' HAVING ' . $having_query . ' ';
}

sub _generate_sql_where_from_filters {
    my ( $self, $filters_ar, $ok_cols_ar ) = @_;

    return q{} if ( 'ARRAY' ne ref $filters_ar );

    my @query = (1);

    for my $filter (@$filters_ar) {
        my ( $col, $type, $term ) = @$filter;

        next if ( $col ne '*' ) && !grep { $_ eq $col } @$ok_cols_ar;

        if ( $type eq 'contains' ) {
            $term = $self->{'dbh'}->quote( '%' . $term . '%' );
        }
        elsif ( $type eq 'begins' ) {
            $term = $self->{'dbh'}->quote( $term . '%' );
        }
        else {
            $term = $self->{'dbh'}->quote($term);

            if ( exists $is_integer{$col} ) {
                $term = "CAST($term AS INTEGER)";
            }
        }

        #Only types that we know and trust.
        $type = $TYPE_CONVERSION{$type};
        next if !$type;

        #Prevent weird column names that could be SQL attacks.
        next if $col ne '*' && $col =~ m{[^a-z]}i;

        if ( $col eq '*' ) {
            push @query, '(' . join( ') OR (', map { "$_ $type $term" } @SEARCHALL_COLUMNS ) . ')';
        }
        else {
            push @query, "$col $type $term";
        }
    }

    return '(' . join( ') AND (', @query ) . ')';
}

sub _generate_group_stats_subquery {
    my $self    = shift;
    my %OPTS    = @_;
    my $opt_str = $self->{'dbh'}->quote( $self->_hash_to_sql_str( \%OPTS ) );
    return "\n-- $OPTS{'name'} query $opt_str\n" . "select
 x.domain, x.user, COUNT(x.msgid) as itemcount, " . ( $OPTS{'table'} eq 'smtp' ? 'SUM(x.size)' : 0 ) . " as totalsize, '$OPTS{'table'}' as what
from
 $OPTS{'table'} $OPTS{'key'}
 join sends x using (msgid)
 $OPTS{'where'}
 $OPTS{'group_by'}
-- end $OPTS{'name'} query\n\n";
}

sub _build_user_query {
    my ( $self, %OPTS ) = @_;
    my ($table) = ( $OPTS{'table'} || 'x' ) =~ /([A-Za-z_]+)/;
    my $exclude_x_table = $OPTS{'exclude_x_table'};

    # Multiple
    if ( ref $self->{'user'} ) {
        if ($exclude_x_table) {
            return '(' . " ( x.user NOT IN (" . join( ',', map { $self->{'dbh'}->quote($_) } @{ $self->{'user'} } ) . ") ) AND  ( $table.deliveryuser IN (" . join( ',', map { $self->{'dbh'}->quote($_) } @{ $self->{'user'} } ) . ') ) ' . ')';
        }
        else {
            return "( $table." . ( $table eq 'x' ? 'user' : 'deliveryuser' ) . " IN (" . join( ',', map { $self->{'dbh'}->quote($_) } @{ $self->{'user'} } ) . ") )";
        }

    }

    # Single
    if ($exclude_x_table) {
        return '(' . " ( x.user != " . $self->{'dbh'}->quote( $self->{'user'} ) . ") AND  ( $table.deliveryuser = " . $self->{'dbh'}->quote( $self->{'user'} ) . ') ' . ')';
    }
    else {
        return "( $table." . ( $table eq 'x' ? 'user' : 'deliveryuser' ) . " = " . $self->{'dbh'}->quote( $self->{'user'} ) . ' ) ';
    }
}

sub _build_webmail_query {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $self            = shift;
    my %OPTS            = @_;
    my ($table)         = ( $OPTS{'table'} || 'x' ) =~ /([A-Za-z_]+)/;
    my $exclude_x_table = $OPTS{'exclude_x_table'};

    my $key = ( $table eq 'x' || $table eq 'sends' ) ? 'sender' : 'email';

    # Multiple
    if ( ref $self->{'webmail'} ) {
        if ($exclude_x_table) {
            return '(' . " ( x.sender NOT IN (" . join( ',', map { $self->{'dbh'}->quote($_) } @{ $self->{'webmail'} } ) . ") ) AND  ( $table.$key IN (" . join( ',', map { $self->{'dbh'}->quote($_) } @{ $self->{'webmail'} } ) . ') ) ' . ')';
        }
        else {
            return "( $table.$key IN (" . join( ',', map { $self->{'dbh'}->quote($_) } @{ $self->{'webmail'} } ) . ") )";
        }

    }

    # Single
    if ($exclude_x_table) {
        return '(' . " ( x.sender != " . $self->{'dbh'}->quote( $self->{'webmail'} ) . ") AND  ( $table.$key = " . $self->{'dbh'}->quote( $self->{'webmail'} ) . ') ' . ')';
    }
    else {
        return "( $table.$key = " . $self->{'dbh'}->quote( $self->{'webmail'} ) . ' ) ';
    }
}

sub _hash_to_sql_str {
    my $self    = shift;
    my $opt_ref = shift;
    return join( ' ', map { $_ . '=' . ( ref $opt_ref->{$_} ? '[' . $self->_hash_to_sql_str( $opt_ref->{$_} ) . ']' : $opt_ref->{$_} ) } keys %{$opt_ref} );
}

1;
