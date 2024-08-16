package Cpanel::BandwidthDB::Write;

# cpanel - Cpanel/BandwidthDB/Write.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This class is for instantiating a read-write object to access bandwidth DB
# data. It ONLY knows how to do that.
#
# If you want something that creates the DB if it doesn’t exist, then
# you probably want Cpanel::BandwidthDB, which contains factory logic for
# this class.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw(
  Cpanel::BandwidthDB::Read
);

#Order is relevant to logic down below.
use constant _FIELD_NAMES => qw(
  domain_id
  protocol
  unixtime
  bytes
);

use constant {
    _FIELDS_SQL    => join( ',', _FIELD_NAMES ),
    _FIELDS_PH_SQL => '(' . join( ',', map { '?' } _FIELD_NAMES ) . ')',
};

use DBD::SQLite ();
use Time::Local ();    # Consider POSIX::mktime or Time::Moment for 11.52+ as its fast as well without the memory overhead
                       # This should be fine for 11.50 since this module is never compiled in.

use Try::Tiny;

use Cpanel::Autodie           ();
use Cpanel::Destruct          ();
use Cpanel::Exception         ();
use Cpanel::SQLite::Savepoint ();

my $FIVE_MINUTES_IN_SECONDS = 300;

# New is only added so we can setup
# _known_protocols and avoid traversing
# an array for every call to update/update_domain/enqueue_multiple_updates
#
# As in the parent class, the only argument is the username.
#
sub new {
    my ( $class, @args ) = @_;

    my $self = $class->SUPER::new(@args);

    $self->{'_known_protocols'} = { map { $_ => 1 } $self->_PROTOCOLS() };

    return bless $self, $class;
}

sub _dbi_attrs {
    my ($self) = @_;

    # Force this into a hash so our sqlite_open_flags
    # overrides the SUPER
    my %hash = (
        $self->SUPER::_dbi_attrs(),
        sqlite_open_flags => DBD::SQLite::OPEN_READWRITE(),
    );

    return %hash;
}

sub DESTROY {
    my ($self) = @_;

    #$self->{'_orig_pid'} might not be set if we failed to initialize.
    if ( $$ == ( $self->{'_orig_pid'} || 0 ) ) {
        if ( $self->{'_updates'} ) {
            my $ref = ref $self;
            warn "DESTROY on a/an $ref object that still has pending updates!";
            return if Cpanel::Destruct::in_dangerous_global_destruction();
        }
        $self->_delete_expired_data();
        if ( $self->{'_updates'} ) {
            $self->write();
        }
    }

    return;
}

#This is used in converting a given timestamp to its “boundary”.
my %first_timelocal_place_to_use = qw(
  daily   3
  hourly  2
);

#Returns whether anything was actually written or not.
#
sub write {
    my ($self) = @_;

    return 0 if !$self->{'_updates'};

    my $updates_hr = $self->{'_updates'};

    my $dbh = $self->{'_dbh'};

    my @existing_monikers = ( $Cpanel::BandwidthDB::Constants::UNKNOWN_DOMAIN_NAME, $self->list_domains() );    # PPI NO PARSE: use parent

    #XXX: An ugly hack to get around DBD::SQLite RT 106151.
    #Remove once a fix for that issue is in production.
    my $dbh_is_in_transaction = $self->get_attr('in_transaction');

    #Use save points here rather than transactions so that we get nesting.
    local $dbh->{'AutoCommit'} = 0 if !$dbh_is_in_transaction;

    my $savepoint = $dbh_is_in_transaction && Cpanel::SQLite::Savepoint->new($dbh);

    for my $moniker ( keys %{$updates_hr} ) {

        #This is in case of schema corruption or a DB rebuild.
        if ( !grep { $_ eq $moniker } @existing_monikers ) {
            my $username = $self->get_attr('username');
            warn "Initializing $moniker in the bandwidth database for the user “$username” …$/";
            $self->_create_tables_for_moniker($moniker);
        }

        for my $protocol ( keys %{ $updates_hr->{$moniker} } ) {
            for my $interval ( $self->_INTERVALS() ) {
                $self->_write_updates_for_moniker_interval_protocol(
                    $updates_hr->{$moniker}{$protocol},
                    $moniker,
                    $interval,
                    $protocol,
                );
            }
        }
    }

    $dbh->commit() if !$dbh_is_in_transaction;

    $savepoint->release() if $savepoint;

    delete $self->{'_updates'};

    return 1;
}

sub _write_updates_for_moniker_interval_protocol {
    my ( $self, $mp_updates_hr, $moniker, $interval, $protocol ) = @_;

    return if !keys %$mp_updates_hr;

    my $dbh = $self->{'_dbh'};

    my $table_q = $dbh->quote_identifier( $self->_interval_table($interval) );

    my $moniker_id = $self->_get_id_for_moniker($moniker);
    die "Unknown domain for write: “$moniker”!" if !defined $moniker_id;

    my $replace_time;
    my $now = time;

    my %new_time_values;
    my %updates_with_normalized_time;
    my %replace_time_cache;
    my @args;
    foreach my $unixtime ( keys %{$mp_updates_hr} ) {
        if ( $interval eq '5min' ) {
            $replace_time = $unixtime - ( $unixtime % $FIVE_MINUTES_IN_SECONDS );

            #There's no point in INSERTing data that we'll just purge in a bit anyway.
            #We only have entries in EXPIRATION_FOR_INTERVAL for 5min currently
            # if we ever add them for other values, we need to move this outside of this if block
            next if $Cpanel::BandwidthDB::Read::EXPIRATION_FOR_INTERVAL{$interval} && $replace_time < ( $now - $Cpanel::BandwidthDB::Read::EXPIRATION_FOR_INTERVAL{$interval} );    # PPI NO PARSE: use parent
        }
        else {
            @args = (
                (0) x ( $first_timelocal_place_to_use{$interval} ),
                ( localtime $unixtime )[ ( $first_timelocal_place_to_use{$interval} ) .. 6 ]
            );

            $replace_time = $replace_time_cache{ join( '_', @args ) } ||= Time::Local::timelocal_nocheck(@args);
        }

        $updates_with_normalized_time{$replace_time} += $mp_updates_hr->{$unixtime};
    }

    my $query = $dbh->prepare("UPDATE $table_q SET bytes = bytes + ?1 WHERE domain_id = ?2 AND protocol = ?3 AND unixtime = ?4");
    foreach my $replace_time ( keys %updates_with_normalized_time ) {
        if (
            $query->execute(
                $updates_with_normalized_time{$replace_time},    # the bytes
                $moniker_id,
                $protocol,
                $replace_time,
            ) == 0
        ) {
            $new_time_values{$replace_time} += $updates_with_normalized_time{$replace_time};
        }
    }
    $query->finish();
    %updates_with_normalized_time = ();

    if (%new_time_values) {
        $self->_get_mass_inserter_for_table($table_q)->insert_fields_sql_ar( [ map { $moniker_id, $protocol, $_, $new_time_values{$_} } keys %new_time_values ] );
    }

    return;
}

sub _get_mass_inserter_for_table {
    my ( $self, $table_q ) = @_;
    return $self->{'_mass_inserter'}{$table_q} if $self->{'_mass_inserter'}{$table_q};
    require Cpanel::SQLite::MassInsert         if !$INC{'Cpanel/SQLite/MassInsert.pm'};
    return (
        $self->{'_mass_inserter'}{$table_q} = Cpanel::SQLite::MassInsert->new(
            'query' => qq<
            INSERT OR REPLACE INTO $table_q
            (> . _FIELDS_SQL() . qq<)
            VALUES
        >,
            'fields_sql' => _FIELDS_PH_SQL(),
            'dbh'        => $self->{'_dbh'}
        )
    );
}

sub _delete_expired_data {
    my ($self) = @_;

    my $dbh = $self->{'_dbh'};
    return if !$dbh;

    my $savepoint;

    #If the file itself is read-only, then the DB handle will be read-only
    #as well. Prevent errors about read-only-ness from the below action
    #since they aren't useful errors. (We only really can get here as
    #read-only if an unprivileged user has tried something nefarious.)
    #
    try {
        $savepoint = Cpanel::SQLite::Savepoint->new($dbh);

        for my $interval ( keys %Cpanel::BandwidthDB::Read::EXPIRATION_FOR_INTERVAL ) {    # PPI NO PARSE: use parent
            my $table_q = $dbh->quote_identifier( $self->_interval_table($interval) );

            $dbh->do( "DELETE FROM $table_q WHERE unixtime <= ?", undef, $Cpanel::BandwidthDB::Read::EXPIRATION_FOR_INTERVAL{$interval} );    # PPI NO PARSE: use parent
        }

        $savepoint->release();
    }
    catch {
        $savepoint->rollback() if $savepoint;

        die Cpanel::Exception::get_string($_) if !try { $_->isa('Cpanel::Exception::Database::Error') };
        die Cpanel::Exception::get_string($_) if !$_->failure_is('SQLITE_READONLY');
    };

    return;
}

#NOTE: This does NOT write data permanently; instead, the write is enqueued.
#The data is written when write() is called, which can happen on object
#destruction or when write() is called manually.
#
#TODO: Benchmark this against just holding a transaction open.
#
sub update {
    my ( $self, $protocol, $unixtime, $bytes ) = @_;

    return $self->_enqueue_update(
        $Cpanel::BandwidthDB::Constants::UNKNOWN_DOMAIN_NAME,    # PPI NO PARSE: use parent
        $protocol,
        $unixtime,
        $bytes,
    );
}

#NOTE: This does NOT write data permanently; instead, the write is enqueued.
#The data is written when write() is called, which can happen on object
#destruction or when write() is called manually.
#
#TODO: Benchmark this against just holding a transaction open.
#
sub update_domain {
    my ( $self, $domain, $protocol, $unixtime, $bytes ) = @_;

    die 'Need domain!' if !length $domain;

    return $self->_enqueue_update(
        $self->_normalize_domain($domain),
        $protocol,
        $unixtime,
        $bytes,
    );
}

#----------------------------------------------------------------------
# enqueue_multiple upates
#
# Arguments:
#   $type  - The type of bandwidth data to enqueue
#             Ex: http/nick.org
#                 imap
#                 pop3
#   $source_hashref - A hashref of epoch keys and bytes values
#             Ex:
#              {
#                 12345678912 => 12332,
#                 12345678913 => 123232,
#                 12345678914 => 551232,
#                 12345678916 => 12232,
#              }
#
#XXX: It is ***ABSOLUTELY NECESSARY!!!*** that you ensure that this
#function receives valid data. In the interest of speed, THIS FUNCTION
#DOES NO VALIDATION.
#
sub enqueue_multiple_updates {
    my ( $self, $type, $source_hashref ) = @_;

    my ( $protocol, $moniker );
    if ( $type =~ m<(.+)/(.+)> ) {
        $protocol = $1;
        $moniker  = $self->_normalize_domain($2);
    }
    else {
        $protocol = $type;
        $moniker  = $Cpanel::BandwidthDB::Constants::UNKNOWN_DOMAIN_NAME;    # PPI NO PARSE: use parent
    }

    if ( !length $moniker ) {
        die Cpanel::Exception->create_raw("Implementation error: enqueue_multiple_updates requires a valid moniker");
    }
    elsif ( !$self->{'_known_protocols'}{$protocol} ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid protocol for this interface.', [$protocol] );
    }

    $self->{'_updates'}{$moniker}{$protocol} ||= {};

    my $target_hashref = $self->{'_updates'}{$moniker}{$protocol};

    @{$target_hashref}{ keys %{$source_hashref} } = values %{$source_hashref};

    return 1;
}

sub _enqueue_update {
    my ( $self, $moniker, $protocol, $unixtime, $bytes ) = @_;

    if ( !length $moniker ) {
        die Cpanel::Exception->create_raw("Implementation error: enqueue_multiple_updates requires a valid moniker");
    }
    elsif ( !$self->{'_known_protocols'}{$protocol} ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid protocol for this interface.', [$protocol] );
    }

    # Don't allow timestamps that are invalid, too small, or greater than 32 bits.
    elsif ( $unixtime =~ tr<0-9><>c || $unixtime < $Cpanel::BandwidthDB::Constants::MIN_ACCEPTED_TIMESTAMP || $unixtime > $Cpanel::BandwidthDB::Constants::MAX_ACCEPTED_TIMESTAMP ) {    # PPI NO PARSE: use parent

        die Cpanel::Exception::create( 'InvalidParameter', "“[_1]” is not a valid timestamp for this interface.", [$unixtime] );
    }

    elsif ( !$bytes || $bytes =~ tr<0-9><>c ) {
        die Cpanel::Exception::create( 'InvalidParameter', "“[_1]” is not a valid byte count for this interface.", [$bytes] );
    }

    $self->{'_updates'}{$moniker}{$protocol}{$unixtime} += $bytes;
    return;
}

sub _create_tables_for_moniker {
    my ( $self, $moniker ) = @_;

    my $dbh = $self->{'_dbh'};

    $moniker = $self->_normalize_domain($moniker);

    ( $self->{'_create_tables_for_moniker_insert_statement'} ||= $dbh->prepare('INSERT INTO domains (name) VALUES (?)') )->execute($moniker);

    return $dbh->sqlite_last_insert_rowid();
}

#NOTE: Should we ever want to validate the actual domain here...
*initialize_domain = *_create_tables_for_moniker;

#----------------------------------------------------------------------
#NOTE: This will initialize any passed-in domains without warning.
#(The presumption is that this is happening during an account restoration,
#so we need to recreate the domain tables as a matter of course.)
#
sub restore_backup {
    my ( $self, $backup_hr, $work_dir ) = @_;

    my $version     = $backup_hr->{'version'};
    my $method_name = "_restore_backup_v$version";
    my $method_cr   = $self->can($method_name);

    die "Unknown version: “$version”" if !$method_cr;

    return $method_cr->( $self, $backup_hr, $work_dir );
}

sub _restore_backup_v3 {
    my ( $self, $backup_manifest_hr, $work_dir ) = @_;

    my $data_hr = $backup_manifest_hr->{'domains'};

    my %current_domains = map { $_ => $self->_get_id_for_moniker($_) } $self->list_domains();
    my %id_lookup_table = ( 1 => 1 );                                                           # UNKNOWN_DOMAIN_NAME is always 1

    {
        my $dbh = $self->{_dbh};

        local $dbh->{AutoCommit} = 0;

        # Write all the domain ids in one shot
        # as its much faster
        $dbh->do('BEGIN TRANSACTION');

        for my $moniker ( keys %$data_hr ) {
            next if $Cpanel::BandwidthDB::Constants::UNKNOWN_DOMAIN_NAME eq $moniker;

            if ( !$current_domains{$moniker} ) {
                $id_lookup_table{ $data_hr->{$moniker} } = $self->initialize_domain($moniker);
            }
            else {
                $id_lookup_table{ $data_hr->{$moniker} } = $self->_get_id_for_moniker($moniker);
            }
        }
        $dbh->do('END TRANSACTION');

    }

    if ( -e "$work_dir/bandwidth_db_data.json" && -s _ > 0 ) {
        my $dbh = $self->{_dbh};

        Cpanel::Autodie::open( my $fh, '<', "$work_dir/bandwidth_db_data.json" );
        require Cpanel::Finally;
        require Cpanel::AdminBin::Serializer;      # PPI USE OK: Used in the called subroutine
        $dbh->do('PRAGMA synchronous = OFF;');
        $dbh->do('PRAGMA cache_size = -6144;');    # approximately abs(N*1024) bytes of memory
        my $finally = Cpanel::Finally->new( sub { $dbh->do('PRAGMA synchronous = ON;'); } );
        local $dbh->{AutoCommit} = 0;
        $dbh->do('BEGIN TRANSACTION');

        while ( my $line = readline($fh) ) {
            chomp($line);

            $self->_process_json_line( \%id_lookup_table, \$line );
        }
        $dbh->do('END TRANSACTION');
        close($fh);
    }

    if ( %{ $backup_manifest_hr->{'metadata'} } ) {
        $self->write_metadata( %{ $backup_manifest_hr->{'metadata'} } );
    }

    return;
}

sub _process_json_line {
    my ( $self, $id_converter, $json_line_ref ) = @_;

    my $entries = Cpanel::AdminBin::Serializer::Load($$json_line_ref);    # PPI NO PARSE - loaded above

    my %interval_groups;

    # Perl seems to be able to optimize this better with the trailing for.
    push @{ $interval_groups{ $_->{interval} } }, $id_converter->{ $_->{domain_id} }, @{$_}{qw( protocol unixtime bytes )} for @$entries;

    foreach my $interval ( keys %interval_groups ) {
        my $table_q = $self->_quoted_interval_table($interval);
        $self->_get_mass_inserter_for_table($table_q)->insert_fields_sql_ar( $interval_groups{$interval} );
    }

    return;
}

sub _restore_backup_v2 {
    my ( $self, $backup_hr ) = @_;

    $self->_restore_backup_v1($backup_hr);

    if ( %{ $backup_hr->{'metadata'} } ) {
        $self->write_metadata( %{ $backup_hr->{'metadata'} } );
    }

    return;
}

sub _restore_backup_v1 {
    my ( $self, $backup_hr ) = @_;

    my $data_hr = $backup_hr->{'domain_protocol_updates'};

    local $self->{'_updates'} = {};

    my $updates_hr = $self->{'_updates'};

    my @existing_monikers = ( $Cpanel::BandwidthDB::Constants::UNKNOWN_DOMAIN_NAME, $self->list_domains() );    # PPI NO PARSE: use parent

    for my $moniker ( keys %$data_hr ) {
        if ( !grep { $_ eq $moniker } @existing_monikers ) {
            $self->initialize_domain($moniker);
        }

        my $store = $data_hr->{$moniker};
        for my $protocol ( keys %{$store} ) {
            my $entries = $store->{$protocol};
            foreach my $entry ( @{$entries} ) {

                #($unix_time, $bytes) = @{ $entry };
                $updates_hr->{$moniker}{$protocol}{ $entry->[0] } += $entry->[1];
            }
        }
    }

    $self->write();

    return;
}

#----------------------------------------------------------------------
# If we ever get to a point where we stop caring about importing
# from pre-11.52, then we can probably delete this logic
# and everything that calls it.
#
# The start and end times in here are literal and refer to periods
# that the relevant DB entries encompass *entirely*. If, for example,
# you delete from 3:01:00 - 5:01:30, this will:
#
#   - delete 5-minute data entries from 3:05 - 4:59:59
#   - subtract the data for 3:05 - 3:59:59 from the 3:00 - 3:59:59 hour
#   - delete the 4:00 - 4:59:59 hour
#
sub delete_data_in_range {
    my ( $self, $moniker, $protocol, $starttime, $endtime ) = @_;

    my $dbh = $self->{'_dbh'};

    for my $interval ( $self->_INTERVALS() ) {
        $self->_remove_entry_from_interval_table_and_propagate_to_larger_interval_tables(
            $moniker,
            $interval,
            $protocol,
            $starttime,
            $endtime,
        );

        my $tbl_q = $self->_quoted_interval_table($interval);

        #Clear out any zero-valued entries. This is, arguably, work left
        #“undone” by _remove_entry_from_interval_table_and_propagate_to_larger_interval_tables(),
        #but hey.
        $dbh->do(
            qq<
            DELETE FROM $tbl_q
            WHERE
                domain_id = ?1
                AND protocol = ?2
                AND bytes = 0
            >,
            undef,
            $self->_get_id_for_moniker($moniker),
            $protocol,
        );
    }

    return;
}

sub _quoted_interval_table {
    my ( $self, $interval ) = @_;
    return ( $self->{'_quoted_interval_table_cache'}{$interval} ||= $self->{'_dbh'}->quote_identifier( $self->_interval_table($interval) ) );
}

sub _get_first_unixtime_in_range_for_domain_interval_protocol {
    my ( $self, $starttime, $moniker_id, $interval, $protocol ) = @_;

    my $tbl_q = $self->_quoted_interval_table($interval);

    my ($v) = $self->{'_dbh'}->selectrow_array(
        qq[
            SELECT unixtime
            FROM $tbl_q
            WHERE
                domain_id = ?1
                AND protocol = ?2
                AND unixtime >= (0 + ?3)
            ORDER BY unixtime
            LIMIT 1
        ],
        undef,
        $moniker_id,
        $protocol,
        $starttime,
    );

    return $v;
}

my %INTERVAL_LENGTH = qw(
  5min    300
  hourly  3600
  daily   86400
);

#This is actually finding the unixtime that corresponds to a particular
#*period*, which is why the SQL query here adds an %INTERVAL_LENGTH value.
#But it’s already an unwieldy name as-is.
sub _get_last_unixtime_in_range_for_domain_interval_protocol {
    my ( $self, $endtime, $moniker_id, $interval, $protocol ) = @_;

    my $tbl_q = $self->_quoted_interval_table($interval);

    my ($v) = $self->{'_dbh'}->selectrow_array(
        qq[
            SELECT unixtime
            FROM $tbl_q
            WHERE
                domain_id = ?1
                AND protocol = ?2
                AND unixtime + $INTERVAL_LENGTH{$interval} - 1 <= (0 + ?3)
            ORDER BY unixtime DESC
            LIMIT 1
        ],
        undef,
        $moniker_id,
        $protocol,
        $endtime,
    );

    return $v;
}

sub _get_sth_for_range_domain_interval_protocol {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $self, $min_included, $max_included, $moniker_id, $interval, $protocol ) = @_;

    my $tbl_q = $self->_quoted_interval_table($interval);

    my $entries_sth = $self->{'_dbh'}->prepare(
        qq[
            SELECT unixtime, bytes
            FROM $tbl_q
            WHERE
                domain_id = ?1
                AND protocol = ?2
                AND unixtime BETWEEN (0 + ?3) AND (0 + ?4)
        ],
    );

    $entries_sth->execute(
        $moniker_id,
        $protocol,
        $min_included,
        $max_included,
    );

    return $entries_sth;
}

sub _remove_entry_from_interval_table_and_propagate_to_larger_interval_tables {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $self, $moniker, $interval, $protocol, $starttime, $endtime ) = @_;

    my $dbh = $self->{'_dbh'};

    my $moniker_id = $self->_get_id_for_moniker($moniker);

    #Find all entries whose total “span” lies between
    #the start and end dates.
    #NOTE: We could do these two queries and the finding of actual
    #[ unixtime => bytes ] entries as a single, combined thing with a
    #subquery, but that would make the SQL pretty unwieldy. This seems
    #simpler and easier to maintain.
    my $min_included = $self->_get_first_unixtime_in_range_for_domain_interval_protocol(
        $starttime,
        $moniker_id,
        $interval,
        $protocol,
    );
    return if !$min_included;

    my ($max_included) = $self->_get_last_unixtime_in_range_for_domain_interval_protocol(
        $endtime,
        $moniker_id,
        $interval,
        $protocol,
    );
    return if !$max_included;

    my $entries_sth = $self->_get_sth_for_range_domain_interval_protocol(
        $min_included,
        $max_included,
        $moniker_id,
        $interval,
        $protocol,
    );

    my $savepoint = Cpanel::SQLite::Savepoint->new($dbh);

    #i.e., the intervals that are of longer duration than the given “interval”.
    #That we will delete entries from $interval’s table is plain, but we
    #also need to decrement entries in the tables whose intervals are of longer
    #duration.
    #
    #For example, if 02:00:00-02:04:59 contains 25 bytes and I remove that
    #5-minute period, I need to decrement the byte total for the 02 hour
    #by 25 bytes. I also need to decrement the day that contains that hour,
    #again, by 25 bytes.
    #
    my %intervals_above = (
        '5min'   => [qw( hourly daily )],
        'hourly' => [qw( daily )],
        'daily'  => [],
    );

    while ( my ( $unixtime, $bytes ) = $entries_sth->fetchrow_array() ) {
        for my $intvl_above ( @{ $intervals_above{$interval} } ) {

            my $TABLE_WITH_DATA_INSIDE_THE_INTERVAL_WE_ARE_UPDATING = $self->_quoted_interval_table($intvl_above);

            #This query decrements the larger-interval-table entry whose
            #timestamp makes it match up with $unixtime.
            #
            $dbh->do(
                qq[
                    UPDATE $TABLE_WITH_DATA_INSIDE_THE_INTERVAL_WE_ARE_UPDATING
                    SET bytes = bytes - ?1
                    WHERE
                        domain_id = ?2
                        AND protocol = ?3
                        AND unixtime = (

                            -- Find the latest entry that begins a period
                            -- that contains the given $unixtime. Usually
                            -- there is only one such entry, but DST shifts
                            -- (“fall back”) produce cases where >1 entry
                            -- contains the same unixtime.

                            -- For example, in Houston, DST started on 8 March 2015.
                            -- That, thus, is a 23-hour day. Going strictly by
                            -- 86400-second “days”, then, midnight on 9 March 2015
                            -- would also be “part of” the day before since it
                            -- occurred only 23 hours after midnight of the
                            -- day before. That, of course, is wrong!

                            -- In these cases, we take the *latter* day so that
                            -- our “days” line up with the actual calendar.

                            SELECT unixtime
                            FROM $TABLE_WITH_DATA_INSIDE_THE_INTERVAL_WE_ARE_UPDATING
                            WHERE
                                domain_id = ?2
                                AND protocol = ?3
                                AND (0 + ?4)
                                    BETWEEN unixtime
                                    AND (unixtime + $INTERVAL_LENGTH{$intvl_above} - 1)
                            ORDER BY unixtime DESC
                            LIMIT 1
                        )
                ],
                undef,
                $bytes,
                $moniker_id,
                $protocol,
                $unixtime,
            );
        }
    }

    #NOTE: At this point, we may well have 0-byte entries in the
    #longer-interval table(s). We will need to clear those out!!

    my $tbl_q = $self->_quoted_interval_table($interval);

    #Having decremented entries for longer-interval periods that
    #“contain” the $interval entries, we can now remove
    #the $interval entries themselves safely.
    $dbh->do(
        qq<
            DELETE FROM $tbl_q
            WHERE
                domain_id = ?1
                AND protocol = ?2
                AND unixtime BETWEEN (0 + ?3) AND (0 + ?4)
        >,
        undef,
        $moniker_id,
        $protocol,
        $min_included,
        $max_included,
    );

    $savepoint->release();

    return;
}

#----------------------------------------------------------------------

sub write_metadata {    #NOTE: This will NOT overwrite!
    my ( $self, %new_metadata ) = @_;

    my $placeholders = join( ',', ('(?,?)') x keys %new_metadata );
    return undef if !$placeholders;

    return $self->{'_dbh'}->do(
        "INSERT INTO metadata (key,value) VALUES $placeholders",
        undef,
        %new_metadata,
    );
}

#----------------------------------------------------------------------
1;
