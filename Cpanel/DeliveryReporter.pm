package Cpanel::DeliveryReporter;

# cpanel - Cpanel/DeliveryReporter.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::DeliveryReporter::Basic ();    # PPI USE OK - crazy but provide the method new
use Cpanel::LoadFile                ();
use Cpanel::Locale                  ();
use Cpanel::Logger                  ();

my $locale;
my $logger;

our $MAX_RESULTS_BY_TYPE_DEFAULT = 250;
our $MAX_RESULTS_BY_TYPE_MAXIMUM = 5000;

my @SEND_SIDE_KEYS = (
    'sender',
    'email',
    'user',
    'domain',
    'senderip',
    'senderhost',
    'spamscore',
    'senderauth'
);
my @DELIVERY_SIDE_KEYS = (
    'recipient',
    'deliveredto',
    'deliveryuser',
    'deliverydomain',
    'msgid',
    'ip',
    'host',
    'router',
    'transport',
    'message'
);

my $delivery_side_subquery_regex;
my $generic_subquery_regex;
my $inprogress_subquery_regex;
my $key_conversion_regex;

my %_filter_type_conversion = (
    'eq'       => 'exact',
    'exact'    => 'exact',
    'contains' => 'regex',
    'regex'    => 'regex',
    'begins'   => 'begin',
    'begin'    => 'begin',
    '=='       => 'exact',
);

sub user_stats {
    my $self = shift;

    my ( $data, $total ) = $self->group_stats(@_);
    require Cpanel::Config::LoadUserDomains;
    require Cpanel::Config::LoadUserOwners;
    my $ownermap_ref  = Cpanel::Config::LoadUserOwners::loadtrueuserowners( {}, 1, 1 );
    my $domainmap_ref = Cpanel::Config::LoadUserDomains::loaduserdomains();

    my @files;
    if ( opendir( my $email_send_limits_dh, '/var/cpanel/email_send_limits' ) ) {
        @files = readdir($email_send_limits_dh);
        closedir($email_send_limits_dh);
    }

    my %REACHED_MAXDEFERFAIL = map { /^max_deferfail_(.*)/; $1 => undef } grep ( /^max_deferfail_/, @files );
    my %REACHED_MAXEMAILS    = map { /^max_emails_(.*)/;    $1 => undef } grep ( /^max_emails_/,    @files );

    for ( 0 .. scalar $#$data ) {
        $data->[$_]->{'PRIMARY_DOMAIN'}       = exists $domainmap_ref->{ $data->[$_]->{'USER'} }        ? $domainmap_ref->{ $data->[$_]->{'USER'} }                                                              : '';
        $data->[$_]->{'OWNER'}                = exists $ownermap_ref->{ $data->[$_]->{'USER'} }         ? $ownermap_ref->{ $data->[$_]->{'USER'} }                                                               : 'root';
        $data->[$_]->{'REACHED_MAXDEFERFAIL'} = exists $REACHED_MAXDEFERFAIL{ $data->[$_]->{'DOMAIN'} } ? Cpanel::LoadFile::loadfile( "/var/cpanel/email_send_limits/max_deferfail_" . $data->[$_]->{'DOMAIN'} ) : 0;
        $data->[$_]->{'REACHED_MAXEMAILS'}    = exists $REACHED_MAXEMAILS{ $data->[$_]->{'DOMAIN'} }    ? Cpanel::LoadFile::loadfile( "/var/cpanel/email_send_limits/max_emails_" . $data->[$_]->{'DOMAIN'} )    : 0;
    }

    return ( $data, $total );
}

sub stats {
    return shift->group_stats(
        @_,
        'group'             => 'none',
        'sort'              => 'none',
        'needs_in_progress' => 1,
        'nodomain'          => 1,
        'nouser'            => 1
    )->[0];
}

sub query {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::RequireArgUnpacking)
    my $self               = shift;
    my %OPTS               = @_;
    my $inprogress         = $OPTS{'inprogress'}                   ? 1 : 0;
    my $success            = $OPTS{'success'}                      ? 1 : 0;
    my $failure            = $OPTS{'failure'}                      ? 1 : 0;
    my $defer              = $OPTS{'defer'}                        ? 1 : 0;
    my $is_user_restricted = $self->{'user'} || $self->{'webmail'} ? 1 : 0;

    _convert_legacy_keys( \%OPTS );

    local $OPTS{'searchmatch'}  = $OPTS{'searchmatch'}  || q<>;
    local $OPTS{'deliverytype'} = $OPTS{'deliverytype'} || q<>;

    # These options get passed to our sub-query builder
    my %PARSED_OPTS = (

        #For now, this parameter is not variable, pending further work
        #on the database backend to avoid performance and disk usage problems.
        'max_results_by_type' => int( exists $OPTS{'max_results_by_type'} ? $OPTS{'max_results_by_type'} : $MAX_RESULTS_BY_TYPE_DEFAULT ),

        # These are special search types
        'searchmatch' => ( $OPTS{'searchmatch'} =~ /^(begin|regex)$/i ? lc $1 : 'exact' ),
        'deliverytype' => ( $OPTS{'deliverytype'} eq 'remote' ? 'remote' : $OPTS{'deliverytype'} eq 'local' ? 'local' : 0 ),
    );
    $PARSED_OPTS{'max_results_by_type'} = $MAX_RESULTS_BY_TYPE_MAXIMUM if $PARSED_OPTS{'max_results_by_type'} > $MAX_RESULTS_BY_TYPE_MAXIMUM;
    foreach my $key ( 'startdate', 'enddate', 'minsize', 'maxsize' ) {
        $PARSED_OPTS{$key} = ( $OPTS{$key} || '' );
    }

    #domain is excluded in webmail mode because it is useless as we require them to use the email
    my $parse_regex_txt = '(?:' . join(
        '|',
        map { '^' . $_ . '$', '^' . $_ . '-[0-9a-z]{1,23}$' } (
            ( $self->{'webmail'} ? () : ('domain') ),
            'user',
            'deliveryuser',
            'deliverydomain',
            'email',
            'sender',
            'deliveredto',
            'senderip',
            'senderhost',
            'spamscore',
            'senderauth',
            'ip',
            'host',
            'router',
            'message',
            'msgid',
            'recipient',
            'transport',
            'all'
        )
    ) . ')';
    my $parse_regex = qr/$parse_regex_txt/;

    _parse_opts( $parse_regex, \%OPTS, \%PARSED_OPTS );

    my %PARSED_OPTS_DELIVERYSIDE = ();
    my @deliveryside_query_parts = ();
    my $deliveryside_query_name  = '';

    if ($is_user_restricted) {
        _parse_delivery_opts(
            \%PARSED_OPTS,
            \%PARSED_OPTS_DELIVERYSIDE,
            \@deliveryside_query_parts,
            \$deliveryside_query_name
        );
    }

    my %ROWMAP = (
        'type'             => 'type',
        'sender'           => 'sender',
        'email'            => 'email',
        'size'             => 'size',
        'user'             => 'user',
        'sendunixtime'     => 'sendunixtime',
        'sendtime'         => 'sendunixtime',
        'msgid'            => 'msgid',
        'transport'        => 'transport',
        'transport_method' => 'transport',
        'recipient'        => 'recipient',
        'deliveredto'      => 'deliveredto',
        'user'             => 'user',
        'domain'           => 'domain',
        'router'           => 'router',
        'senderhost'       => 'senderhost',
        'senderip'         => 'senderip',
        'senderauth'       => 'senderauth',
        'spamscore'        => 'spamscore',
        'host'             => 'host',
        'ip'               => 'ip',
        'actionunixtime'   => 'actiontime',
        'actiontime'       => 'actiontime',
        'message'          => 'message',
    );

    my $sort       = $OPTS{'sort'} && $ROWMAP{ $OPTS{'sort'} }                      || 'sendunixtime';
    my $sortdir    = $OPTS{'dir'}  && ( lc $OPTS{'dir'} eq 'asc' ? 'ASC' : 'DESC' ) || 'DESC';
    my $startIndex = $OPTS{'startIndex'} ? int( $OPTS{'startIndex'} ) : 0;

    my $results = int( $OPTS{'results'} || $PARSED_OPTS{'max_results_by_type'} );
    $results = $MAX_RESULTS_BY_TYPE_MAXIMUM if $results > $MAX_RESULTS_BY_TYPE_MAXIMUM;

    my @searchall_keys = grep { m{\Aall(?:-[0-9a-z]{1,23})?\z} } keys %PARSED_OPTS;

    my ( @SUB_QUERIES, @COUNT_SUB_QUERIES );

    if ($success) {

        # The smtp table - we add any success (smtp table) events inside the date
        # range of the sends table
        my ( $query, $count_query ) = $self->_generate_eximstats_table_generic_subquery(
            'sortdir' => $sortdir,
            'type'    => 'success',
            'table'   => 'smtp',
            'options' => \%PARSED_OPTS,
            'name'    => 'smtp_inside_sends_window'
        );

        push @SUB_QUERIES,       $query;
        push @COUNT_SUB_QUERIES, $count_query;

    }

    if ( $success && ( !$PARSED_OPTS{'deliverytype'} || $PARSED_OPTS{'deliverytype'} eq 'local' ) ) {

        # If we are restricting by user or webmail we need to manually include
        # all user entries in the smtp table that are not in the send table
        # (ie local deliveries)
        if ($is_user_restricted) {

            # The smtp table - we add any success (smtp table) events inside
            # the date range of the sends table -- if we are restricting to
            # user we need to add the smtp.deliveryuser matches
            # (is_user_restricted will use the smtp table and exclude things we
            # have already matched in the sends table)

            # The smtp table - we add any success (smtp table) events inside
            # the date range of the sends table and they are matching the
            # query_parts
            my ( $query, $count_query ) = $self->_generate_eximstats_table_generic_subquery(
                'sortdir'          => $sortdir,
                'type'             => 'success',
                'table'            => 'smtp',
                'options'          => ( scalar keys %PARSED_OPTS_DELIVERYSIDE ? \%PARSED_OPTS_DELIVERYSIDE : \%PARSED_OPTS ),
                'is_delivery_side' => 1,
                'name'             => 'smtp_inside_sends_window_user_restricted' . ( $deliveryside_query_name ? '_' . $deliveryside_query_name : '' )
            );

            push @SUB_QUERIES,       $query;
            push @COUNT_SUB_QUERIES, $count_query;

        }
    }

    # The failures and defer table are ignored if we are asked for a
    # delivertype ($PARSED_OPTS{'deliverytype'}) as only successful messages
    # (ones that have been delivered) have a delivery type
    if ( !$PARSED_OPTS{'deliverytype'} ) {

        if ($failure) {

            # The failures table - we add any failure (failures table) events
            # inside the date range of the sends table
            my ( $query, $count_query ) = $self->_generate_eximstats_table_generic_subquery(
                'sortdir' => $sortdir,
                'type'    => 'failure',
                'table'   => 'failures',
                'options' => \%PARSED_OPTS,
                'name'    => 'failures_inside_sends_window'
            );
            push @SUB_QUERIES,       $query;
            push @COUNT_SUB_QUERIES, $count_query;
        }

        if ($defer) {

            # The defers table - we add any defer (defers table) events inside the
            # date range of the sends table
            my ( $query, $count_query ) = $self->_generate_eximstats_table_generic_subquery(
                'sortdir' => $sortdir,
                'type'    => 'defer',
                'table'   => 'defers',
                'options' => \%PARSED_OPTS,
                'name'    => 'defers_inside_sends_window'
            );
            push @SUB_QUERIES,       $query;
            push @COUNT_SUB_QUERIES, $count_query;
        }

        if ($is_user_restricted) {

            if ($failure) {

                # The failures table - we add any failure (failures table) events
                # inside the date range of the sends table

                my ( $query, $count_query ) = $self->_generate_eximstats_table_generic_subquery(
                    'sortdir'          => $sortdir,
                    'type'             => 'failure',
                    'table'            => 'failures',
                    'options'          => ( scalar keys %PARSED_OPTS_DELIVERYSIDE ? \%PARSED_OPTS_DELIVERYSIDE : \%PARSED_OPTS ),
                    'is_delivery_side' => 1,
                    'name'             => 'failures_inside_sends_window_user_restricted' . ( $deliveryside_query_name ? '_' . $deliveryside_query_name : '' )
                );
                push @SUB_QUERIES,       $query;
                push @COUNT_SUB_QUERIES, $count_query;
            }

            if ($defer) {

                # The defers table - we add any defer (defers table) events inside
                # the date range of the sends table
                my ( $query, $count_query ) = $self->_generate_eximstats_table_generic_subquery(
                    'sortdir'          => $sortdir,
                    'type'             => 'defer',
                    'table'            => 'defers',
                    'options'          => ( scalar keys %PARSED_OPTS_DELIVERYSIDE ? \%PARSED_OPTS_DELIVERYSIDE : \%PARSED_OPTS ),
                    'is_delivery_side' => 1,
                    'name'             => 'defers_inside_sends_window_user_restricted' . ( $deliveryside_query_name ? '_' . $deliveryside_query_name : '' )
                );
                push @SUB_QUERIES,       $query;
                push @COUNT_SUB_QUERIES, $count_query;
            }
        }

    }

    # Finally we have the special case of the inprogress events (events that
    # have a send but not defer, success, or failure) -- We restrict the data
    # range to NOW-2h - NOW+2h
    if ($inprogress) {
        my ( $query, $count_query ) = $self->_generate_eximstats_table_inprogress_subquery(
            'sortdir' => $sortdir,
            'type'    => 'inprogress',
            'table'   => 'x',
            'options' => \%PARSED_OPTS,
            'name'    => 'inprogress'
        );

        push @SUB_QUERIES,       $query;
        push @COUNT_SUB_QUERIES, $count_query;
    }

    # If we are searching for email
    # (recipient),deliveredto,message,ip,host,router, or transport
    # we have to omit the inprogress query as it can never match anything
    # since it's the abesense of data

    my $query = join( "\nUNION ALL\n", @SUB_QUERIES );

    # SQLite doesn't support SQL_CALC_FOUND_ROWS and FOUND_ROWS so we need to do a count query as well
    if ( !$query ) {

        # No data will be returned so just return empty
        return '' if $self->{'test_mode'};
        return ( [], 0 );
    }

    my $count_query = "select count(1) from ( " . join( "\nUNION ALL\n", @COUNT_SUB_QUERIES );
    if (@searchall_keys) {    #wrap the whole query so we can select from it

        my @TEXT_COLUMNS = (
            'user',
            'domain',
            'email',
            'sender',
            'size',
            'msgid',
            'senderhost',
            'senderip',
            'spamscore',
            'senderauth',
            'message',
            'recipient',
            'deliveredto',
            'router',
            'host',
            'ip',
            'deliveryuser',
            'deliverydomain',
            'transport'
        );

        $query = " select * from ( " . $query;
        my @searchall_clauses;
        my $right_side;
        for my $key (@searchall_keys) {
            if ( $PARSED_OPTS{"searchmatch_$key"} =~ m{exact}i ) {
                $right_side = ' = ' . $self->{'dbh'}->quote( $PARSED_OPTS{$key} );
            }
            elsif ( $PARSED_OPTS{"searchmatch_$key"} =~ m{begin}i ) {
                $right_side = ' LIKE ' . $self->{'dbh'}->quote( $PARSED_OPTS{$key} . '%' );
            }
            else {
                $right_side = ' LIKE ' . $self->{'dbh'}->quote( '%' . $PARSED_OPTS{$key} . '%' );
            }

            push @searchall_clauses, '(' . join( ') OR (', map { "$_ $right_side" } @TEXT_COLUMNS ) . ')';
        }
        $query       .= ' ) as deliveryreport WHERE ( ' . join( ') AND (', @searchall_clauses ) . ' ) ';
        $count_query .= ' ) as deliveryreport WHERE ( ' . join( ') AND (', @searchall_clauses ) . ' ); ';
    }
    else {
        $count_query .= ' );';
    }
    $query .= " ORDER BY $sort $sortdir " . ( $results ? " LIMIT $startIndex,$results" : "" ) . ";";

    return $query if $self->{'test_mode'};

    #DEBUG and PERFORMANCE TESTING:
    my $t0;
    if ( $Cpanel::Debug::level > 3 ) {

        #DEBUG and PERFORMANCE TESTING:
        print STDERR "[DeliveryReporter::query] " . $query . "\n\n\n\n";

        # This code is run uncompiled so the bare require is safe
        require Time::HiRes;
        $t0 = [ Time::HiRes::gettimeofday() ];
    }
    my $rec_ref = $self->{'dbh'}->selectall_arrayref( $query, { Slice => {} } );
    if ( $Cpanel::Debug::level > 3 ) {
        my $elapsed = Time::HiRes::tv_interval( $t0, [ Time::HiRes::gettimeofday() ] );
        print STDERR "[elapsed:$elapsed]\n";
    }

    if ($DBI::errstr) {
        $logger ||= Cpanel::Logger->new();
        $logger->warn("SQL Error in DeliveryReporter: $DBI::errstr");
    }

    my $txn_count = 0;
    my $overflowed;
    if ( $rec_ref && ref $rec_ref && @$rec_ref ) {

        if ( $Cpanel::Debug::level > 3 ) {
            print STDERR "[DeliveryReporter::count_query] " . $count_query . "\n\n\n\n";

            # This code is run uncompiled so the bare require is safe
            require Time::HiRes;
            $t0 = [ Time::HiRes::gettimeofday() ];
        }

        $txn_count = $self->{'dbh'}->selectrow_array( $count_query, { 'Slice' => {} } );
        if ( $txn_count > $MAX_RESULTS_BY_TYPE_MAXIMUM and $PARSED_OPTS{'max_results_by_type'} ) {
            $txn_count  = $MAX_RESULTS_BY_TYPE_MAXIMUM;
            $overflowed = 1;
        }

        if ( $Cpanel::Debug::level > 3 ) {
            my $elapsed = Time::HiRes::tv_interval( $t0, [ Time::HiRes::gettimeofday() ] );
            print STDERR "[elapsed:$elapsed]\n";
        }
    }

    return ( $rec_ref, $txn_count, $overflowed );
}

sub _generate_eximstats_table_inprogress_subquery {
    my $self = shift;
    my %OPTS = @_;

    _generate_generic_subquery_regex();
    my $opt_str = $self->{'dbh'}->quote( $self->_hash_to_sql_str( \%OPTS ) );

    my $query = "\n-- $OPTS{'name'} query $opt_str\nSELECT * FROM (
SELECT
'inprogress' as type,
x.user as user,
x.domain as domain,
x.email as email,
x.sender as sender,
x.size as size,
x.msgid as msgid,
x.host as senderhost,
x.ip as senderip,
x.auth as senderauth,
x.spamscore as spamscore,
x.sendunixtime as sendunixtime,
'In progress' as message,
'unknown' as recipient,
'unknown' as deliveredto,
'unknown' as router,
'unknown' as host,
'unknown' as ip,
NULL as deliveryuser,
NULL as deliverydomain,
'unknown' as transport,
datetime( $OPTS{'table'}.sendunixtime, 'unixepoch', 'localtime') as actiontime,
x.sendunixtime as actionunixtime,
" . map_eximstats_tblcolumn_transport_is_remote_target( $OPTS{'table'} ) . " as transport_is_remote
";

    my $joins_and_where = "from sends $OPTS{'table'}
LEFT JOIN failures ON ($OPTS{'table'}.msgid=failures.msgid)
LEFT JOIN defers ON ($OPTS{'table'}.msgid=defers.msgid)
LEFT JOIN smtp ON ($OPTS{'table'}.msgid=smtp.msgid)
" . $self->_generate_search_where(
        'inprogress' => 1,

        # should not include dates or restrictions as we are looking for
        # 'NOT IN smtp,defers,failures' only search terms
        'table' => $OPTS{'table'},
        ( map { $_ =~ $generic_subquery_regex ? ( $_ => $OPTS{'options'}->{$_} ) : () } keys %{ $OPTS{'options'} } ),
        ( map { exists $OPTS{'options'}->{$_} ? ( $_ => $OPTS{'options'}->{$_} ) : () } ( 'minsize', 'maxsize', 'searchmatch' ) ),
        ( map { $_ => $OPTS{'options'}->{$_} } grep ( m/^searchmatch_/, keys %{ $OPTS{'options'} } ) )
      )

      # We restrict the time to startdate (or two hours before now() if no
      # startdate) and after now. If there is no event in side that block,
      # there never will be.
      . " AND  " . "(x.sendunixtime >= " . ( ( $OPTS{'options'}->{'startdate'} && ( $OPTS{'options'}->{'startdate'} > ( time() - 7200 ) ) ) ? " " . int( $OPTS{'options'}->{'startdate'} ) . " " : " strftime('%s', 'now', '-2 HOUR') " ) . " AND " . " x.sendunixtime <= strftime('%s', 'now', '+2 HOUR')) " . " AND " . " (failures.msgid IS NULL and defers.msgid IS NULL and smtp.msgid IS NULL) ";

    $query .= $joins_and_where;
    my $count_query = $query;

    $query .= " ORDER BY sendunixtime $OPTS{'sortdir'} ";
    $query .= ( $OPTS{'options'}->{'max_results_by_type'} ? " LIMIT $OPTS{'options'}->{'max_results_by_type'} " : '' ) . " )\n-- end $OPTS{'name'} query\n";

    $count_query .= " )\n-- end $OPTS{'name'} count query\n";

    return ( $query, $count_query );
}

sub _generate_eximstats_table_generic_subquery {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $self = shift;
    my %OPTS = @_;
    _generate_generic_subquery_regex();
    my $opt_str = $self->{'dbh'}->quote( $self->_hash_to_sql_str( \%OPTS ) );

    my $query = "\n-- $OPTS{'name'} query $opt_str\nSELECT * FROM (SELECT\n"
      . (
          $OPTS{'type'} eq 'success' ? ("CASE WHEN $OPTS{'table'}.transport_method='**bypassed**' THEN 'filtered' ELSE CASE WHEN SUBSTR($OPTS{'table'}.transport_method,1,9) = 'archiver_' THEN 'archive' ELSE 'success' END END")
        : $OPTS{'type'} eq 'failure' ? ("CASE WHEN $OPTS{'table'}.transport_method='**rejected**' THEN 'rejected' ELSE 'failure' END")
        :                              ( $self->{'dbh'}->quote( $OPTS{'type'} ) )
      )
      . " as type,\n"
      . "x.user as user,
x.domain as domain,
x.sender as sender,
x.email as email,
x.size as size,
x.msgid as msgid,
x.host as senderhost,
x.ip as senderip,
x.auth as senderauth,
x.spamscore as spamscore,
x.sendunixtime as sendunixtime,
" . $self->map_eximstats_tblcolumn_message_target( $OPTS{'table'} ) . " as message,
$OPTS{'table'}.email as recipient,
" . map_eximstats_tblcolumn_deliveredto_target( $OPTS{'table'} ) . " as deliveredto,
$OPTS{'table'}.deliveryuser as deliveryuser,
$OPTS{'table'}.deliverydomain as deliverydomain,
$OPTS{'table'}.router as router,
$OPTS{'table'}.host as host,
$OPTS{'table'}.ip as ip,
$OPTS{'table'}.transport_method as transport,
datetime( $OPTS{'table'}.sendunixtime, 'unixepoch', 'localtime') as actiontime,
$OPTS{'table'}.sendunixtime as actionunixtime,
" . map_eximstats_tblcolumn_transport_is_remote_target( $OPTS{'table'} ) . " as transport_is_remote
";

    my $joins_and_where = "from sends x
    " . "INNER JOIN $OPTS{'table'} on (x.msgid=$OPTS{'table'}.msgid) " . $self->_generate_search_where(
        'table' => $OPTS{'table'},
        ( map { $_ =~ $generic_subquery_regex ? ( $_ => $OPTS{'options'}->{$_} ) : () } keys %{ $OPTS{'options'} } ),
        ( map { exists $OPTS{'options'}->{$_} ? ( $_ => $OPTS{'options'}->{$_} ) : () } ( 'startdate', 'enddate', 'minsize', 'maxsize', 'searchmatch' ) ),
        ( 'is_delivery_side' => $OPTS{'is_delivery_side'} ? 1 : 0 ),
        ( map { $_ => $OPTS{'options'}->{$_} } grep ( m/^searchmatch_/, keys %{ $OPTS{'options'} } ) )
    );

    $query .= $joins_and_where;
    my $count_query = $query;

    $query .= " ORDER BY $OPTS{'table'}.sendunixtime $OPTS{'sortdir'} ";

    $query .= ( $OPTS{'options'}->{'max_results_by_type'} ? " LIMIT $OPTS{'options'}->{'max_results_by_type'} " : '' ) . "  )\n-- end $OPTS{'name'} query\n";

    $count_query .= " )\n-- end $OPTS{'name'} count query\n";

    return ( $query, $count_query );
}

sub _generate_search_where {    ## no critic qw(Subroutines::RequireArgUnpacking Subroutines::ProhibitExcessComplexity)
    my $self       = shift;
    my $dbh        = $self->{'dbh'};
    my %OPTS       = @_;
    my $inprogress = $OPTS{'inprogress'};
    my @search_queries;
    push @search_queries, ( $OPTS{'deliverytype'} eq 'remote' ? q{(transport_is_remote='1')} : q{(transport_is_remote='0')} ) if $OPTS{'table'} eq 'smtp' && $OPTS{'deliverytype'};
    push @search_queries, $self->_build_user_query( 'table' => $OPTS{'is_delivery_side'} ? $OPTS{'table'} : '', 'exclude_x_table' => $OPTS{'is_delivery_side'} ? 1 : 0 )    if $self->{'user'};
    push @search_queries, $self->_build_webmail_query( 'table' => $OPTS{'is_delivery_side'} ? $OPTS{'table'} : '', 'exclude_x_table' => $OPTS{'is_delivery_side'} ? 1 : 0 ) if $self->{'webmail'};

    my $searchmatch;

    # Previously we did not set the user field if $self->{'user'} was set,
    # however if they are a reseller in whm $self->{'user'} is set to the list
    # of users they are allowed to access and they may want to drill down to a
    # specific user
    my %SEARCH_TARGETS = (
        'user'           => { 'dbtarget' => 'x.user' },
        'domain'         => { 'dbtarget' => 'x.domain' },
        'sender'         => { 'dbtarget' => 'x.sender' },
        'email'          => { 'dbtarget' => 'x.email' },
        'senderip'       => { 'dbtarget' => 'x.ip' },
        'senderhost'     => { 'dbtarget' => 'x.host' },
        'senderauth'     => { 'dbtarget' => 'x.auth' },
        'spamscore'      => { 'dbtarget' => 'x.spamscore' },
        'deliveredto'    => { 'dbtarget' => map_eximstats_tblcolumn_deliveredto_target( $OPTS{'table'} ) },
        'message'        => { 'dbtarget' => $self->map_eximstats_tblcolumn_message_target( $OPTS{'table'} ) },
        'deliveryuser'   => { 'dbtarget' => "$OPTS{'table'}.deliveryuser" },
        'deliverydomain' => { 'dbtarget' => "$OPTS{'table'}.deliverydomain" },
        'host'           => { 'dbtarget' => "$OPTS{'table'}.host" },
        'router'         => { 'dbtarget' => "$OPTS{'table'}.router" },
        'transport'      => { 'dbtarget' => "$OPTS{'table'}.transport_method" },
        'ip'             => { 'dbtarget' => "$OPTS{'table'}.ip" },
        'recipient'      => { 'dbtarget' => "$OPTS{'table'}.email" },
        'msgid'          => { 'dbtarget' => "$OPTS{'table'}.msgid" },
    );

    # Searching our static data that we use as a filler from the
    # _generate_eximstats_table_inprogress_subquery function
    if ($inprogress) {
        $SEARCH_TARGETS{'message'}->{'dbtarget'} = "'In Progress'";
        foreach my $col ( 'recipient', 'deliveredto', 'router', 'host', 'ip', 'deliveryuser', 'deliverydomain', 'transport' ) {
            $SEARCH_TARGETS{$col}->{'dbtarget'} = "'unknown'";
        }
    }

    my ( $truekey, $searchcfg );
    foreach my $searchkey ( keys %OPTS ) {
        $truekey     = ( split( m/-/, $searchkey, 2 ) )[0];
        $searchmatch = $OPTS{ 'searchmatch_' . $searchkey } || $OPTS{'searchmatch'} || '' || next;
        $searchcfg   = $SEARCH_TARGETS{$truekey} || next;

        if ( $searchmatch =~ /^(?:regex|begin)$/ ) {
            push @search_queries, '(' .

              join(
                ' AND ',

                ( $searchcfg->{'dbtarget'}  ? "$searchcfg->{'dbtarget'} LIKE " . $dbh->quote( ( $searchmatch eq 'regex'      ? '%' : '' ) . $OPTS{$searchkey} . '%' ) : () ),
                ( $searchcfg->{'dbexclude'} ? "$searchcfg->{'dbexclude'} NOT LIKE " . $dbh->quote( ( $searchmatch eq 'regex' ? '%' : '' ) . $OPTS{$searchkey} . '%' ) : () )

              ) . ')';

        }
        else {
            push @search_queries,
              '(' . join(
                ' AND ',
                ( $searchcfg->{'dbtarget'}  ? "$searchcfg->{'dbtarget'} = " . $dbh->quote( $OPTS{$searchkey} )   : () ),
                ( $searchcfg->{'dbexclude'} ? "$searchcfg->{'dbexclude'} != " . $dbh->quote( $OPTS{$searchkey} ) : () )
              ) . ')';

        }
    }

    push @search_queries, '(x.size >= ' . int( $OPTS{'minsize'} ) . ')' if $OPTS{'minsize'};
    push @search_queries, '(x.size <= ' . int( $OPTS{'maxsize'} ) . ')' if $OPTS{'maxsize'};

    push @search_queries, (
        ( $OPTS{'startdate'} ? "($OPTS{'table'}.sendunixtime >= " . int( $OPTS{'startdate'} ) . ")" : () ),    # action can never be before send
        ( $OPTS{'startdate'} ? "(x.sendunixtime >= " . int( $OPTS{'startdate'} ) . ")"              : () ),
        ( $OPTS{'enddate'}   ? "(x.sendunixtime <= " . int( $OPTS{'enddate'} ) . ")"                : () )
    );

    @search_queries = ('1') if !@search_queries;                                                               # 1 in case we are joining an AND on the WHERE

    return ' WHERE ( ' . join( ' AND ', @search_queries ) . ' ) ';
}

sub _if_first {
    return $_[0] == 1 ? $_[1] : '';
}

sub map_eximstats_tblcolumn_deliveredto_target {
    my $table = shift;
    $table eq 'smtp' ? $table . '.deliveredto' : 'NULL';                                                       #only for the smtp table
}

sub map_eximstats_tblcolumn_transport_is_remote_target {
    my $table = shift;
    $table eq 'smtp' ? $table . '.transport_is_remote' : '0';                                                  #only for the smtp table
}

sub map_eximstats_tblcolumn_message_target {
    my ( $self, $table ) = @_;

    if ( $table eq 'smtp' ) {

        #only static for the smtp table
        $locale ||= Cpanel::Locale->get_handle();
        my $quoted_filtered_text = $self->{'dbh'}->quote( $locale->maketext('Filtered') );
        my $quoted_archived_text = $self->{'dbh'}->quote( $locale->maketext('Archived') );
        my $quoted_accepted_text = $self->{'dbh'}->quote( $locale->maketext('Accepted') );

        return q{CASE WHEN smtp.transport_method='**bypassed**' THEN } . $quoted_filtered_text . q{ELSE CASE WHEN SUBSTR(smtp.transport_method,1,9) = 'archiver_' THEN } . $quoted_archived_text . " ELSE " . $quoted_accepted_text . q{ END END };
    }

    return $table . '.message';
}

sub _parse_opts {
    my ( $parse_regex, $opts_ref, $parsed_opts_ref ) = @_;
    foreach my $key ( keys %{$opts_ref} ) {
        next if ( $key !~ $parse_regex );

        $parsed_opts_ref->{$key} = $opts_ref->{$key} || '';

        # no need to create a searchmatch for a key that does not exist
        return if !$parsed_opts_ref->{$key};

        local $opts_ref->{"searchmatch_$key"} = $opts_ref->{"searchmatch_$key"} || q<>;

        my $type = $opts_ref->{"searchmatch_$key"} =~ /^(eq|contains|begins|==|begin|regex)$/ ? $1 : ( $key =~ m/^all$|^all-[0-9a-z]{1,23}$/ ? 'regex' : 'exact' );

        if ( $type eq '==' ) {

            #We can assume that what we get back from MySQL will not have
            #leading or trailing zeros. So we prepare our filter term the same way.
            $parsed_opts_ref->{$key} += 0;
        }

        $parsed_opts_ref->{ 'searchmatch_' . $key } = $_filter_type_conversion{$type};
    }
}

sub _parse_delivery_opts {
    my ( $parsed_opts_ref, $parsed_opts_deliveryside_ref, $deliveryside_query_parts_ref, $deliveryside_query_name_ref ) = @_;

    my $newkey;
    foreach my $delivery_side_type ( 'user', 'domain' ) {
        foreach my $key ( sort grep ( m/(?:^searchmatch_${delivery_side_type}$|^searchmatch_${delivery_side_type}-[0-9a-z]{1,23}$|^${delivery_side_type}$|^${delivery_side_type}-[0-9a-z]{1,23}$)/, keys %{$parsed_opts_ref} ) ) {
            %{$parsed_opts_deliveryside_ref} = %{$parsed_opts_ref} if !scalar keys %{$parsed_opts_deliveryside_ref};

            $newkey = $key;
            $newkey =~ s/$delivery_side_type/delivery$delivery_side_type/;    # convert user to deliveryuser etc

            $parsed_opts_deliveryside_ref->{$newkey} = $parsed_opts_deliveryside_ref->{$key};

            delete $parsed_opts_deliveryside_ref->{$key};

            push @{$deliveryside_query_parts_ref}, $newkey if $newkey !~ m/^searchmatch_/;
        }
    }

    $$deliveryside_query_name_ref = join( '_', @{$deliveryside_query_parts_ref} );
    return 1;
}

# Handle legacy key conversions
sub _convert_legacy_keys {
    my $opt_ref          = shift;
    my %_key_conversions = (
        'transport_method'  => 'transport',
        'starttime'         => 'startdate',
        'endtime'           => 'enddate',
        'startunixtime'     => 'startdate',
        'endunixtime'       => 'enddate',
        'startsendunixtime' => 'startdate',
        'endsendunixtime'   => 'enddate',
        'minsendunixtime'   => 'startdate',    # for Cpanel::DeliveryReport::Utils
        'maxsendunixtime'   => 'enddate',
    );

    if ( !$key_conversion_regex ) {
        my $key_conversion_regex_txt = '(' . join( '|', ( map { '^' . $_ . '$', '^searchmatch_' . $_ . '$', '^' . $_ . '-', '^searchmatch_' . $_ . '-' } keys %_key_conversions ) ) . ')';
        $key_conversion_regex = qr/$key_conversion_regex_txt/;
    }

    my $orig_key;
    %{$opt_ref} = map {
        $orig_key = $_;
        if ( $_ =~ $key_conversion_regex ) {
            my $old_key = $1;
            $old_key =~ s/^searchmatch_//;
            $old_key = ( split( /-/, $old_key ) )[0];
            s/$old_key/$_key_conversions{$old_key}/;
        }
        $_ => $opt_ref->{$orig_key}
    } keys %{$opt_ref};

    return 1;
}

sub _generate_generic_subquery_regex {
    if ( !$generic_subquery_regex ) {
        my $generic_subquery_regex_txt = '(?:' . join(
            '|',
            map { '^' . $_ . '$', '^' . $_ . '-[0-9a-z]{1,23}$' } (
                'searchmatch',
                'deliverytype',
                @SEND_SIDE_KEYS,
                @DELIVERY_SIDE_KEYS
            )
        ) . ')';
        $generic_subquery_regex = qr/$generic_subquery_regex_txt/;
    }
    return 1;
}

sub _generate_delivery_side_subquery_regex {
    if ( !$delivery_side_subquery_regex ) {
        my $delivery_side_subquery_regex_txt = '(?:' . join(
            '|',
            map { '^' . $_ . '$', '^' . $_ . '-[0-9a-z]{1,23}$' } (@DELIVERY_SIDE_KEYS)
        ) . ')';
        $delivery_side_subquery_regex = qr/$delivery_side_subquery_regex_txt/;
    }
    return 1;
}

1;
