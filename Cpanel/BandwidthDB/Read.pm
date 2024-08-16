package Cpanel::BandwidthDB::Read;

# cpanel - Cpanel/BandwidthDB/Read.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This class is for instantiating a read-only object to access bandwidth DB
# data. It ONLY knows how to do that.
#
# If you want something that creates the DB if it doesn’t exist, then
# you probably want Cpanel::BandwidthDB, which contains factory functions for
# this class.
#
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# NOTE:
# This class internally uses the term “moniker” as a generic term for either:
#   - a domain name
#   - the “unknown-domain” category
#
# It seems best NOT to expose this term publicly.
#----------------------------------------------------------------------

=head1 NAME

Cpanel::BandwidthDB::Read

=cut

use strict;
use warnings;

use base qw(
  Cpanel::BandwidthDB::Base
);

use DBD::SQLite ();

use Try::Tiny;

use Cpanel::BandwidthDB::Constants ();
use Cpanel::Context                ();
use Cpanel::DateUtils              ();
use Cpanel::Exception              ();
use Cpanel::Time                   ();

our $VERSION = 0.060;

my $ONE_DAY_IN_UNIXTIME = 86400;

#exposed for tests; set this to 2 * time(), for instance, to
#“disable” the 5-minute data expiration.
our %EXPIRATION_FOR_INTERVAL = (
    '5min' => 31 * $ONE_DAY_IN_UNIXTIME,    #one month, roughly

    #We could remove the hourly data after a certain period
    #if these SQLite DBs start getting too big.
    #hourly => 730 * $ONE_DAY,    #two years, roughly
);

#----------------------------------------------------------------------
# Constructor

sub new {
    my ( $class, $username ) = @_;

    my $self = $class->SUPER::new($username);

    $self->_check_for_outdated_schema();

    return $self;
}

#----------------------------------------------------------------------

#subclasses can override
sub _check_for_outdated_schema {
    my ($self) = @_;

    if ( $self->_get_schema_version() < $Cpanel::BandwidthDB::Constants::SCHEMA_VERSION ) {
        die Cpanel::Exception::create_raw( 'Database::SchemaOutdated', "Bandwidth DB schema is outdated!" );
    }

    return;
}

#for subclassing
sub _dbi_attrs {
    return (
        sqlite_open_flags => DBD::SQLite::OPEN_READONLY(),
    );
}

#----------------------------------------------------------------------

#%opts can be:
#
#   - grouping      array reference
#       Controls the grouping and display of data in the response.
#       Any field not given in the “grouping” is grouped together.
#       Possible values are:
#           domain
#           protocol
#           year_month_day_hour_minute
#           year_month_day_hour
#           year_month_day
#           year_month
#
#       If I give [ qw( domain protocol year_month ) ], then the structure
#       returned will have those parameters, in that grouping. If, though,
#       I give [ qw( date protocol ) ], then the query will add all domains’
#       data together--and the structure will be different.
#
#       The “year_*” parameters are MUTUALLY EXCLUSIVE.
#       They produce the respective forms in the response:
#           Y-M-D-H-M
#           Y-M-D-H
#           Y-M-D
#           Y-M
#
#       An empty arrayref will make this query total EVERYTHING together.
#
#       The byte total is always (implicitly) last in the result.
#
#   - interval      “daily” (default), “hourly”, or “5min”
#
#       This determines the resolution of the data retrieved.
#       NOTE: This is probably superfluous; we should be able to determine
#       this from the “grouping”.
#
#   - domains       optional, array reference
#   - protocols     optional, array reference
#
#       NOTE the use of the special 'UNKNOWN' “pseudo-domain”, which refers
#       to data recorded without a specific domain. (As of March 2015, all
#       non-HTTP traffic has been recorded without a specific domain
#       for many years.)
#
#   - start
#   - end
#       These are both optional and specified in one of these formats:
#           Y-M-D-H-M-S
#           Y-M-D-H-M
#           Y-M-D-H
#           Y-M-D
#           Y-M
#           Y
#
#Hashes return as:
#   (
#       $domain1 => { $proto1 => { "$year1-$month1-$mday1" => $total1, .. }, .. ) },
#       $domain2 => { $proto1 => { "$year1-$month1-$mday1" => $total1, .. }, .. ) },
#   )
#
#...or, in array structure, it would be:
#   (
#       [ $domain1, $proto1, "$year1-$month1-$mday1", $total1 ],
#       [ $domain1, $proto1, "$year1-$month1-$mday2", $total2 ],
#       ...
#   )
#
#NOTE: Again, dates are in LOCAL time.
#
#Of course, “grouping” will change the order/structure/content of the return; for
#the above, the grouping would be [ qw( domain protocol year_month_day ) ].
#
sub get_bytes_totals_as_hash {
    my ( $self, %opts ) = @_;

    my $sth = $self->_get_bytes_totals_sth(%opts);

    my %resp;

    if ( $sth->{NUM_OF_FIELDS} == 4 ) {
        while ( my @args = $sth->fetchrow_array() ) {
            $resp{ $args[0] }{ $args[1] }{ $args[2] } = $args[3];
        }
    }
    elsif ( $sth->{NUM_OF_FIELDS} == 3 ) {
        while ( my @args = $sth->fetchrow_array() ) {
            $resp{ $args[0] }{ $args[1] } = $args[2];
        }
    }
    else {
        while ( my @args = $sth->fetchrow_array() ) {
            if ( defined $args[0] ) {
                $resp{ $args[0] } = $args[1];
            }
        }
    }

    return \%resp;
}

sub get_bytes_totals_as_array {
    my ( $self, %opts ) = @_;

    return $self->_get_bytes_totals_sth(%opts)->fetchall_arrayref();
}

sub _get_bytes_totals_sth {
    my ( $self, %opts ) = @_;

    my %select_component = (
        domain   => 'domains.name',
        protocol => 'protocol',
    );

    my @key_parts = qw( year month day hour minute );
    while (@key_parts) {
        my $key = join( '_', @key_parts );
        $select_component{$key} = $self->_get_sql_date_for_mdays_mode($key), pop @key_parts;
    }

    my @grouping = @{ $opts{'grouping'} };
    if ( grep { !exists $select_component{$_} } @grouping ) {
        die "Invalid “grouping”: “@grouping”!";
    }

    my $interval = $opts{'interval'};
    if ( !length $interval ) {
        $interval = 'daily';
    }

    my $interval_table = $self->_interval_table($interval) or do {
        die "Invalid “interval”: “$interval”";
    };

    my $sql_select = join(
        ', ',
        ( map { "$select_component{$_} AS $_" } @grouping ),
        "SUM(bytes) as sum_bytes",
    );

    my $include_domains_tbl = $opts{'domains'} ? 1 : 0;
    $include_domains_tbl ||= grep { $_ eq 'domain' } @grouping;

    my $sql_where = join(
        ' AND ',
        $self->_get_where_clause_from_domains(%opts),
        $self->_get_where_clause_from_protocols(%opts),
        $self->_get_where_clause_from_start_end(%opts),
        $include_domains_tbl ? 'domain_id = domains.id' : (),
    );

    $sql_where ||= 1;    #placeholder

    my $dbh = $self->{'_dbh'};

    my $bw_table_q      = $dbh->quote_identifier($interval_table);
    my $domains_table_q = $dbh->quote_identifier('domains');

    my $tables_q = $bw_table_q;
    if ($include_domains_tbl) {
        $tables_q .= ", $domains_table_q";
    }

    my $main_query = qq<
        SELECT $sql_select
        FROM $tables_q
        WHERE $sql_where
    >;

    if (@grouping) {
        my $sql_group_and_order_by = join( ', ', @grouping );

        $main_query .= qq<
            GROUP BY $sql_group_and_order_by
            ORDER BY $sql_group_and_order_by
        >;
    }

    my $sth = $self->{'_dbh'}->prepare($main_query);
    $sth->execute();

    return $sth;
}

my %strftime_template_piece = (
    year   => '%Y',
    month  => '%m',
    day    => '%d',
    hour   => '%H',
    minute => '%M',
);

#NOTE: *This* function could accept e.g., 'minute_hour_day',
#but for now there’s no need for it, so let’s not expose it publicly.
#
sub _get_sql_date_for_mdays_mode {
    my ( $self, $time_format ) = @_;

    my @time_format_split        = split m<_>, $time_format;
    my @template_split           = map { $strftime_template_piece{$_} } @time_format_split;
    my $sqlite_strftime_template = join( '-', @template_split );

    $sqlite_strftime_template = $self->{'_dbh'}->quote($sqlite_strftime_template);

    return qq{
        strftime(
            $sqlite_strftime_template,
            unixtime,
            'unixepoch',
            'localtime'
        )
    };
}

sub _get_where_clause_from_domains {
    my ( $self, %opts ) = @_;

    if ( $opts{'domains'} ) {
        my @domains = @{ $opts{'domains'} };

        my $ids_q = join ',', map { $self->_get_id_for_moniker($_) } @domains;
        return "domain_id IN ($ids_q)";
    }

    return;
}

sub _get_where_clause_from_protocols {
    my ( $self, %opts ) = @_;

    if ( $opts{'protocols'} ) {
        my $protocols_q = join ',', map { $self->{'_dbh'}->quote($_) } @{ $opts{'protocols'} };
        return "protocol IN ($protocols_q)";
    }

    return;
}

sub _get_where_clause_from_start_end {
    my ( $self, %opts ) = @_;

    my ( $start, $end ) = @opts{ 'start', 'end' };

    if ($start) {
        my @start_ymd = $self->_split_and_validate_ymd_start_end( $start, 'start' );

        $_ ||= 1 for @start_ymd[ 1, 2 ];

        $_ ||= 0 for @start_ymd[ 3, 4, 5 ];

        $start = Cpanel::Time::timelocal( reverse @start_ymd );
    }
    if ($end) {
        my @end_ymd = $self->_split_and_validate_ymd_start_end( $end, 'end' );
        $end = Cpanel::DateUtils::get_last_second_of_ymdhm(@end_ymd);
    }

    if ($start) {
        if ($end) {
            if ( $start eq $end ) {
                return "unixtime = $start";
            }
            else {
                die '“start” must be at or before “end”!' if $start > $end;

                return "unixtime BETWEEN $start AND $end";
            }
        }
        else {
            return "unixtime >= $start";
        }
    }
    elsif ($end) {
        return "unixtime <= $end";
    }

    return;
}

sub _split_and_validate_ymd_start_end {
    my ( $self, $opt, $param ) = @_;
    my @ymd = split m<[^0-9]+>, $opt;

    if ( $ymd[6] ) {
        die "“$param” must be Y(-M(-D(-H(-M(-S))))), not “$opt”!";
    }

    return @ymd;
}

#----------------------------------------------------------------------

sub domain_exists {
    my ( $self, $domain ) = @_;

    return ( $self->{'_dbh'}->selectrow_array( 'SELECT COUNT(*) FROM domains WHERE name = ?', undef, $domain ) )[0];
}

#Returns an array of "updates" to the datastore.
#
#Each "update" is represented as an arrayref: [ unixtime, bytes ]
#The updates are sorted by unixtime.
#
#NOTE: It may be possible to remove this function once RRDTool is gone.
#
sub get_updates_list_for_domain {
    my ( $self, $interval, $protocol, $domain ) = @_;

    die "Must have domain!" if !$domain;

    return $self->_get_updates_list_backend(
        $interval,
        $protocol,
        $self->_normalize_domain($domain),
    );
}

#This totals together the bytes for the given interval/protocol,
#including all domains and when the domain is unknown. Entries are
#sorted by unixtime.
#
#NOTE: It may be possible to remove this function once RRDTool is gone.
#
sub get_updates_list {
    my ( $self, $interval, $protocol ) = @_;

    return $self->_get_updates_list_backend(
        $interval,
        $protocol,
        $Cpanel::BandwidthDB::Constants::UNKNOWN_DOMAIN_NAME,
        $self->list_domains(),
    );
}

#cf. note above about “moniker”s
sub _get_updates_list_backend {
    my ( $self, $interval, $protocol, @monikers ) = @_;

    Cpanel::Context::must_be_list();

    $self->_validate_interval_and_protocol( $interval, $protocol );

    my @protocols = ( $protocol eq 'all' ) ? $self->_PROTOCOLS() : ($protocol);

    my @m_i_p_list;

    for my $m (@monikers) {
        for my $p (@protocols) {
            push @m_i_p_list, [ $m, $interval, $p ];
        }
    }

    #This assembles the array-of-arrays that this function returns,
    #combining data from the passed-in protocol and monikers.
    my $result_ar = $self->_combine_updates_for_moniker_interval_protocol( \@m_i_p_list );

    return @$result_ar;
}

sub _validate_interval_and_protocol {
    my ( $self, $interval, $protocol ) = @_;

    if ( !grep { $_ eq $protocol } $self->_PROTOCOLS(), 'all' ) {
        die $self->_make_protocol_err($protocol);
    }

    if ( !grep { $_ eq $interval } $self->_INTERVALS() ) {
        die $self->_make_interval_err($interval);
    }

}

sub _make_protocol_err {
    my ( $self, $protocol ) = @_;

    return Cpanel::Exception::create( 'InvalidParameter', "“[_1]” is not a valid protocol for this interface. This value should be one of the following: [join,~, ,_2]", [ $protocol, [ sort( $self->_PROTOCOLS() ) ] ] );
}

sub _make_interval_err {
    my ( $self, $interval ) = @_;

    return Cpanel::Exception::create( 'InvalidParameter', "“[_1]” is not a valid interval for this interface. This value should be one of the following: [join,~, ,_2]", [ $interval, [ $self->_INTERVALS() ] ] );
}

#cf. note above about “moniker”s
sub _combine_updates_for_moniker_interval_protocol {
    my ( $self, $m_i_p_lists_ar, $where_sql ) = @_;

    my %ts_bytes;

    if ( !defined $where_sql ) {
        $where_sql = q<>;
    }

    for my $m_i_p_ar (@$m_i_p_lists_ar) {
        my $sth = $self->_get_updates_list_sth(
            @$m_i_p_ar,
            $where_sql || (),
        );

        while ( my ( $ts, $bytes ) = $sth->fetchrow_array() ) {
            $ts_bytes{$ts} += $bytes;
        }
    }

    return [ map { [ $_ => $ts_bytes{$_} ] } sort { $a <=> $b } keys %ts_bytes ];
}

#cf. note above about “moniker”s
sub _get_updates_list_sth {
    my ( $self, $moniker, $interval, $protocol, @extra_where ) = @_;

    my $domain_id = $self->_get_id_for_moniker($moniker);

    my @where_clauses = (
        "domain_id = $domain_id",
        "protocol = " . $self->{'_dbh'}->quote($protocol),
        @extra_where,
    );

    my $where_sql = join( ' AND ', @where_clauses );

    my $table_q = $self->{'_dbh'}->quote_identifier(

        #        $self->_moniker_interval_protocol_table( $moniker, $interval, $protocol, $where_sql ),
        $self->_interval_table($interval),
    );

    my $sth = $self->{'_dbh'}->prepare(
        qq<
            SELECT unixtime, bytes
            FROM $table_q
            WHERE $where_sql
            ORDER BY unixtime
        >
    );
    $sth->execute();

    return $sth;
}

=head2 get_backup_manifest()

This function generates and returns the backup manifest. It also
generates the SQLite statements to back up the current bandwidth database,
to be used via the C<generate_backup_data()> method.

=head3 Arguments

None

=head3 Returns

This function returns a hashref of the metadata for the current bandwidth function to be used/saved by the caller,
and generates the SQLite statements to be used in C<generate_backup_data()>, to generate 'bandwidth_db_data.json'.

=head3 Exceptions

Anything DBD::SQLite can throw

=cut

sub get_backup_manifest {
    my ($self) = @_;

    my $dbh = $self->{_dbh};

    my %backup_manifest = (
        version  => $self->_get_schema_version(),
        metadata => { $self->read_metadata() },
        tables   => {},
        domains  => {},
    );

    $self->{'_sqlite_commands_for_backup_data'} = [
        '.separator |',
        '.mode list',
    ];

    my $columns_list = join( ',', ( map { ( "'$_'", $_ ) } @Cpanel::BandwidthDB::Constants::REPORT_TABLE_COLUMNS ) );
    for my $interval ( $self->_INTERVALS() ) {
        my $table   = $self->_interval_table($interval);
        my $table_q = $dbh->quote_identifier($table);

        push @{ $self->{'_sqlite_commands_for_backup_data'} }, "SELECT json_object($columns_list,'interval','$interval') FROM $table_q;";

        $backup_manifest{tables}{$table} = 1;
    }
    push @{ $self->{'_sqlite_commands_for_backup_data'} }, '.exit';    # exit as soon as the dump is complete so we don't have to wait for EOF

    $backup_manifest{domains} = $self->get_domain_id_map();

    return \%backup_manifest;
}

=head2 generate_backup_data( SCALAR )

This function generates a JSON file, C<bandwidth_db_data.json>, using the SQLite commands generated
by C<get_backup_manifest()>. This method must be called B<after> C<get_backup_manifest()> has been invoked.

=head3 Arguments

=over 4

=item work_dir    - required SCALAR - The work directory to output the bandwidth database backup file to.

=back

=head3 Returns

This function returns 1 on success.

=head3 Exceptions

Anything DBD::SQLite can throw
Anything Cpanel::Autodie::open() can throw
Anything Cpanel::SafeRun::Object can throw

=cut

sub generate_backup_data {
    my ( $self, $work_dir ) = @_;

    require Cpanel::Autodie;
    Cpanel::Autodie::open( my $json_fh, '>', "$work_dir/bandwidth_db_data.json" );

    require Cpanel::BandwidthDB::Read::BackupParser;
    my $parser = Cpanel::BandwidthDB::Read::BackupParser->new( stream_fh => $json_fh );

    require Cpanel::FastSpawn::InOut;

    my ( $write_fh, $read_fh );
    my $pid = Cpanel::FastSpawn::InOut::inout( $write_fh, $read_fh, '/usr/local/cpanel/3rdparty/bin/sqlite3', scalar $self->_name_to_path( $self->get_attr('username') ) );
    if ( !$pid ) {
        die "Failed to execute “/usr/local/cpanel/3rdparty/bin/sqlite3”: $!";
    }
    print {$write_fh} join( "\n", @{ $self->{'_sqlite_commands_for_backup_data'} } ) . "\n";
    my $data = '';
    require Cpanel::LoadFile::ReadFast;
    while ( Cpanel::LoadFile::ReadFast::read_fast( $read_fh, $data, Cpanel::LoadFile::ReadFast::READ_CHUNK(), length $data ) ) {
        if ( length $data >= Cpanel::LoadFile::ReadFast::READ_CHUNK() ) {
            $parser->process_data($data);
            $data = '';
        }
    }
    $parser->process_data($data) if length $data;
    waitpid( $pid, 0 );
    $parser->finish();
    close($read_fh);

    return 1;
}

sub read_metadata {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    return map { @$_ } @{ $self->{'_dbh'}->selectall_arrayref('SELECT key, value FROM metadata') };
}

sub get_domain_id_map {
    my ($self) = @_;
    return { map { $_->[0], $_->[1] } @{ $self->{'_dbh'}->selectall_arrayref('select name,id from domains;') } };
}

1;
