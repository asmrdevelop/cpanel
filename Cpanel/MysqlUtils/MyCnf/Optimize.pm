package Cpanel::MysqlUtils::MyCnf::Optimize;

# cpanel - Cpanel/MysqlUtils/MyCnf/Optimize.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception                    ();
use Cpanel::Locale                       ();
use Cpanel::MysqlUtils::Connect          ();
use Cpanel::MysqlUtils::MyCnf::SQLConfig ();
use Cpanel::MysqlUtils::MyCnf::Adjust    ();
use Cpanel::MariaDB                      ();
use Cpanel::MysqlUtils::Version          ();
use Cpanel::Status                       ();
use Cpanel::Debug                        ();
use Cpanel::Math                         ();
use Cpanel::Version::Compare             ();

use Clone;

=head1 NAME

Cpanel::MysqlUtils::MyCnf::Optimize

=head1 DESCRIPTION

This module is intended to provide optimizations and recommendations
for various MySQL/MariaDB settings. It is mainly used by the Edit SQL
Configuration UI in WHM.

The only public function is get_optimizations() and can be called directly:
my $opt = Cpanel::MysqlUtils::MyCnf::Optimize::get_optimizations();

=head2 get_optimizations()

Returns the available optimizations for the running server. First we get a
list of filtered settings for the running database. Then each setting is
processed by running its 'recommendation' coderef. Each 'recommendation'
coderef accepts a database handle and a statistics hashref as arguments.

The optimizations are returned in a hashref:
{
    $setting1 => {
        name => $setting_name1,
        value => $recommended_value,
        reason => $reason_as_string
    },
    $setting2 => {
        name => $setting_name2,
        value => $recommended_value,
        reason => $reason_as_string
    },
    ....
}

=cut

sub get_optimizations {
    my $settings = _get_settings();
    return _run_optimize($settings);
}

=head2 _run_optimize()

Private function that takes the list of settings that contains
the 'recommendation' coderefs as an argument.

This function obtains a database handle and the statistics of the
running server. These are passed to the recommendation coderef where
a value and reason are calculated.

It returns the list of settings along with the 'value' and 'reason'
attributes.

=cut

sub _run_optimize ($settings) {

    my $dbh = eval { Cpanel::MysqlUtils::Connect::get_dbi_handle() };
    if ( my $exception = $@ ) {
        die Cpanel::Exception::create_raw( 'Database::ConnectError', "Failed to connect to database: $exception" );
    }

    my $stats = _get_stats($dbh);

    foreach my $key ( sort keys %$settings ) {
        if ( $settings->{$key}{recommendation} && ref( $settings->{$key}{recommendation} ) eq 'CODE' ) {
            $settings->{$key}->@{ 'value', 'reason' } = eval { $settings->{$key}{recommendation}->( $dbh, $stats ) };
            delete $settings->{$key}{recommendation};
            if ( my $exception = $@ ) {
                Cpanel::Debug::log_info("Failed to create an optimization for $settings->{$key}{name}: $exception");
                delete $settings->{$key};
                next;
            }
            delete $settings->{$key} if !defined $settings->{$key}{value};
        }
    }

    return $settings;
}

=head2 _get_settings()

Private function responsible for obtaining the list of settings
we want to calculate recommendations for.

This function determines the currently running database version. Then
obtains the list of valid settings for this database version and the
list of all available settings. These two lists are compared and non-valid
settings are filtered out.

The filtered list of settings is returned.

=cut

sub _get_settings {

    my $version_info = Cpanel::MysqlUtils::Version::current_mysql_version();
    my $is_mdb       = Cpanel::MariaDB::version_is_mariadb( $version_info->{'full'} );
    my $db           = $is_mdb ? 'mariadb' : 'mysql';

    my $possible_settings = Cpanel::MysqlUtils::MyCnf::SQLConfig::get_settings( $db, $version_info->{'short'} );
    my $settings          = _settings();

    # Remove any settings that are not valid for the running database
    foreach my $opt ( keys %$settings ) {
        my $name = $settings->{$opt}{name};
        delete $settings->{$opt} if !grep { /^$name$/ } keys %$possible_settings;
    }

    return $settings;

}

=head2 _get_stats

Private function that obtains various stats about the running system.

These stats are used during the calculation of the recommendations.

=cut

sub _get_stats ($dbh) {

    my %stats = ();

    $stats{low_ram} = 2 * ( 1024**2 );    # 2 GiB
    $stats{med_ram} = 8 * ( 1024**2 );    # 8 GiB

    # These values are in kb.
    ( $stats{mem_used}, $stats{mem_total}, $stats{swap_used}, $stats{swap_total} ) = Cpanel::Status::memory_totals();

    if ( $stats{mem_total} <= $stats{low_ram} ) {
        $stats{is_low_ram} = 1;
    }
    elsif ( $stats{mem_total} <= $stats{med_ram} ) {
        $stats{is_med_ram} = 1;
    }
    else {
        $stats{is_high_ram} = 1;
    }

    my %status          = map { $_->{Variable_name} => $_->{Value} } values( _get_all_status_variables($dbh)->%* );
    my %storage_engines = ( 'storage_engines' => _get_storage_engine_stats($dbh) );

    my $version_info = Cpanel::MysqlUtils::Version::current_mysql_version();
    $stats{db_version} = $version_info->{short};
    $stats{db_name}    = Cpanel::MariaDB::version_is_mariadb( $version_info->{'full'} ) ? 'mariadb' : 'mysql';

    return { %stats, %status, %storage_engines };
}

#################
# Private Helpers
sub _get_storage_engine_stats ($dbh) {
    return $dbh->selectall_hashref(
        q{SELECT ENGINE AS engine,
        SUM(DATA_LENGTH+INDEX_LENGTH) AS total_size,
        COUNT(ENGINE) AS table_count,
        SUM(DATA_LENGTH) AS data_size,
        SUM(INDEX_LENGTH) AS index_size
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql') AND
        ENGINE IS NOT NULL
        GROUP BY ENGINE}, 'engine'
    );
}

sub _get_all_status_variables ($dbh) {
    return $dbh->selectall_hashref( 'SHOW GLOBAL STATUS', 'Variable_name' );
}

sub _get_status_variable ( $dbh, $variable ) {
    return ( $dbh->selectrow_array( 'SHOW GLOBAL STATUS WHERE Variable_name = ?', undef, $variable ) )[1];
}

sub _get_current_value ( $dbh, $setting ) {
    return ( $dbh->selectrow_array("SELECT @\@GLOBAL.$setting") )[0];
}

sub _bytes_to_kibibytes ($bytes) {
    return $bytes / 1024;
}

sub _bytes_to_mebibytes ($bytes) {
    return $bytes / 1024**2;
}

sub _bytes_to_gibibytes ($bytes) {
    return $bytes / 1024**3;
}

sub _kibibytes_to_bytes ($kibibytes) {
    return int( $kibibytes * 1024 );
}

sub _mebibytes_to_bytes ($mebibytes) {
    return int( $mebibytes * 1024**2 );
}

sub _gibibytes_to_bytes ($gibibytes) {
    return int( $gibibytes * 1024**3 );
}

sub _dec_remainder ( $a, $b ) {
    return $b ? $a / $b - int( $a / $b ) : 0;
}

sub _format_bytes ($bytes) {
    my ( $GiB, $MiB, $KiB ) = ( _bytes_to_gibibytes($bytes), _bytes_to_mebibytes($bytes), _bytes_to_kibibytes($bytes) );
    return $GiB . 'G' if int($GiB) && !_dec_remainder( $GiB, 1 );
    return $MiB . 'M' if int($MiB) && !_dec_remainder( $MiB, 1 );
    return $KiB . 'K' if int($KiB) && !_dec_remainder( $KiB, 1 );
    return $bytes;
}

sub _profile_dispatch ( $stats, %dispatch_table ) {
    my $ref;
    $ref = $dispatch_table{low}  if $stats->{is_low_ram};
    $ref = $dispatch_table{med}  if $stats->{is_med_ram};
    $ref = $dispatch_table{high} if $stats->{is_high_ram};
    $ref //= $dispatch_table{default};

    return unless $ref;

    if ( ref $ref eq 'CODE' ) {
        return $ref->();
    }
    else {
        # E.g. med => 'low',
        return $dispatch_table{$ref}->();
    }

}

sub _is_in_my_cnf ($setting) {
    require Cpanel::MysqlUtils::MyCnf::Basic;
    my $cnf = Cpanel::MysqlUtils::MyCnf::Basic::get_mycnf();
    return exists $cnf->{$setting} ? 1 : 0;
}

# End Private Helpers
#####################

=head2 _settings

Private function that returns the list of settings we
want to give optimizations for. Each setting must contain
'name' and 'recommendation' attributes.

=cut

sub _settings {    ## no critic(Subroutines::ProhibitExcessComplexity)

    my $locale = Cpanel::Locale->get_handle();

    my $settings = {
        innodb_buffer_pool_instances => {
            name           => 'innodb_buffer_pool_instances',
            recommendation => sub ( $dbh, $stats ) {

                # MariaDB no longer supports this option on the latest versions.
                return if $stats->{db_name} && $stats->{db_name} eq 'mariadb' && Cpanel::Version::Compare::compare( $stats->{db_version}, '>=', '10.5' );

                my $pool_instances = $stats->{'innodb_buffer_pool_instances'} //= _get_current_value( $dbh, 'innodb_buffer_pool_instances' );
                my $reason         = $locale->maketext('For best efficiency, you should configure as many buffer pool instances so that each is about 1GB in size.');

                # recommend 1 if the server has low/medium total ram
                if ( $stats->{is_low_ram} || $stats->{is_med_ram} ) {
                    if ( $pool_instances != 1 ) {
                        return ( 1, $reason );
                    }
                    return;
                }

                my $pool_size;

                if ( $stats->{'recommended_innodb_buffer_pool_size'} ) {
                    $pool_size = $stats->{'recommended_innodb_buffer_pool_size'};
                    $reason .= ' ';
                    my $pretty_pool_size = _format_bytes($pool_size);
                    $reason .= $locale->maketext( 'This calculation is based on the recommended value of “[_1]” for “[_2]”.', $pretty_pool_size, 'InnoDB Buffer Pool Size' );
                }
                else {
                    $pool_size = $stats->{'innodb_buffer_pool_size'} //= _get_current_value( $dbh, 'innodb_buffer_pool_size' );
                }
                $pool_size = int( $pool_size / 1024**3 );    #convert to GiB

                if ( $pool_size >= 2 && $pool_instances < $pool_size ) {
                    return ( $pool_size, $reason );
                }

                return;
            },
        },
        read_buffer_size => {
            name           => 'read_buffer_size',
            recommendation => sub ( $dbh, $stats ) {

                my $read_buffer_size = $stats->{'read_buffer_size'} //= _get_current_value( $dbh, 'read_buffer_size' );
                $read_buffer_size = int( $read_buffer_size / 1024**2 );

                if ( $read_buffer_size > 2 ) {
                    return (
                        '2M',
                        $locale->maketext('Every thread that scans a table allocates this buffer. We recommend setting this value small, as the database server can create several buffers simultaneously.')
                    );
                }

                return;
            },
        },
        join_buffer_size => {
            name           => 'join_buffer_size',
            recommendation => sub ( $dbh, $stats ) {
                my $join_buffer_size      = $stats->{'join_buffer_size'} //= _get_current_value( $dbh, 'join_buffer_size' );
                my $indexless_joins       = $stats->{'Select_range_check'} + $stats->{'Select_full_join'};
                my $daily_indexless_joins = $indexless_joins / ( $stats->{'Uptime'} / 86400 );

                return unless $daily_indexless_joins > 250;

                my $reason = $locale->maketext('Your database is reporting a high number of JOINs performed without indexes. The best way to get faster JOINs is to add indexes. The system will recommend a higher or lower Join Buffer Size based on the size of your system memory. We do not recommend exceeding 2M.');

                my $recommend = _profile_dispatch(
                    $stats,
                    low     => sub { return _kibibytes_to_bytes(512) },
                    default => sub { return _mebibytes_to_bytes(1) },
                );
                return if $recommend == $join_buffer_size;

                return ( _format_bytes($recommend), $reason, );
            },
        },
        sort_buffer_size => {
            name           => 'sort_buffer_size',
            recommendation => sub ( $dbh, $stats ) {
                my $sort_buffer_size = $stats->{'sort_buffer_size'} //= _get_current_value( $dbh, 'sort_buffer_size' );
                my $total_sorts      = $stats->{'Sort_scan'} + $stats->{'Sort_range'};

                if ( $total_sorts > 0 ) {
                    my $ratio = int( ( $stats->{'Sort_merge_passes'} / $total_sorts ) * 100 );
                    if ( $ratio > 10 ) {
                        my $rec = $sort_buffer_size + _kibibytes_to_bytes(128);
                        $rec -= int( $rec % _kibibytes_to_bytes(1) );

                        my $two_mib = _mebibytes_to_bytes(2);
                        return (
                            _format_bytes( $rec > $two_mib ? $two_mib : $rec ),
                            $locale->maketext('The best way to get faster sorts is through indexing or query optimization. However, gradually increasing the size of this buffer may help. We do not recommend exceeding 2M.'),
                        );
                    }
                    else {
                        return;
                    }
                }
                else {
                    return;
                }
            },
        },
        '01_innodb_buffer_pool_size' => {
            name           => 'innodb_buffer_pool_size',
            recommendation => sub ( $dbh, $stats ) {

                my $pool_size    = $stats->{'innodb_buffer_pool_size'} //= _get_current_value( $dbh, 'innodb_buffer_pool_size' );
                my $pool_size_mb = _bytes_to_mebibytes($pool_size);

                if ( $stats->{is_low_ram} || $stats->{is_med_ram} ) {
                    my $reason;

                    # On low and medium ram systems, if they are using something larger or smaller than the default, recommend the default.
                    if ( $pool_size_mb > 128 ) {
                        $reason = $locale->maketext( 'To lower the database server’s memory usage, we recommend using the default value for [_1].', 'InnoDB Buffer Pool Size' );
                    }
                    elsif ( $pool_size_mb < 128 ) {
                        $reason = $locale->maketext( 'To increase the database server’s performance, we recommend using the default value for [_1].', 'InnoDB Buffer Pool Size' );
                    }

                    $stats->{recommended_innodb_buffer_pool_size} = _mebibytes_to_bytes(128) if $reason;
                    return ( '128M', $reason )                                               if $reason;
                }
                elsif ( $stats->{is_high_ram} ) {

                    # on high ram systems, we'll recommend 10% of total ram.
                    my $mem_bytes              = _kibibytes_to_bytes( $stats->{mem_total} );
                    my $rough_recommendation   = int( $mem_bytes / 10 );
                    my $has_set_pool_instances = _is_in_my_cnf('innodb_buffer_pool_instances');
                    my $has_set_chunk_size     = _is_in_my_cnf('innodb_buffer_pool_chunk_size');

                    # innodb_buffer_pool_chunk_size will be auto adjusted to be equal to innodb_buffer_pool_size
                    # if innodb_buffer_pool_size is less than 128M.
                    #
                    # Since this recommendation will increase the pool size over 128M we should consider the chunk
                    # size to be 128M if it is not set in my.cnf and is less than 128M.
                    my $chunk_size = $stats->{'innodb_buffer_pool_chunk_size'} //= _get_current_value( $dbh, 'innodb_buffer_pool_chunk_size' );
                    if ( _bytes_to_mebibytes($chunk_size) < 128 && !$has_set_chunk_size ) {
                        $chunk_size = _mebibytes_to_bytes(128);
                    }

                    # If innodb_buffer_pool_instances is not explictly set in my.cnf it will dynamicly change the number
                    # of instances based on the size of the buffer pool. We need to take this into consideration when calculating
                    # large buffer pools.
                    #
                    # When the buffer pool is set to > 1G it will auto-set the pool instances to 8
                    # ( https://github.com/mysql/mysql-server/commit/45d6fe5f2682 ).
                    #
                    # MariaDB 10.5 and higher no longer use innodb_buffer_pool_instances so we'll need to account for that also.
                    my $pool_instances;
                    if ( $stats->{db_name} && $stats->{db_name} eq 'mariadb' && Cpanel::Version::Compare::compare( $stats->{db_version}, '>=', '10.5' ) ) {
                        $pool_instances = 1;
                    }
                    else {
                        $pool_instances = $stats->{'innodb_buffer_pool_instances'} //= _get_current_value( $dbh, 'innodb_buffer_pool_instances' );
                        if ( _bytes_to_gibibytes($rough_recommendation) > 1 && !$has_set_pool_instances ) {
                            $pool_instances = 8;
                        }
                    }

                    # It needs to be a multiple of innodb_buffer_pool_chunk_size * innodb_buffer_pool_instances
                    my $pool_step_size = $chunk_size * $pool_instances;

                    #Using ceil here because that's how mysql/mariadb handle buffer pool sizes that aren't integer multiples of the pool step size
                    my $recommendation = Cpanel::Math::ceil( $rough_recommendation / $pool_step_size ) * $pool_step_size;

                    # Only provide a recommendation if it will increase more than 128M.
                    my $diff_mb = _bytes_to_mebibytes( $recommendation - $pool_size );
                    if ( $diff_mb > 128 ) {
                        $stats->{recommended_innodb_buffer_pool_size} = $recommendation;
                        return (
                            _format_bytes($recommendation),
                            $locale->maketext('A larger buffer pool allows the database to hold more data structures in memory. A large value will reduce disk I/O on systems with high available RAM.')
                        );
                    }

                }
                return;
            },
        },
        innodb_log_buffer_size => {
            name           => 'innodb_log_buffer_size',
            recommendation => sub ( $dbh, $stats ) {

                my $log_waits              = $stats->{'Innodb_log_waits'};
                my $innodb_log_buffer_size = $stats->{'innodb_log_buffer_size'} //= _get_current_value( $dbh, 'innodb_log_buffer_size' );

                # suggest the default if they are low on memory and using something larger than the default.
                if ( $stats->{is_low_ram} && $innodb_log_buffer_size > _mebibytes_to_bytes(128) ) {
                    return (
                        '128M',
                        $locale->maketext( 'To control the database’s memory usage, we recommend using the default value for [_1].', 'InnoDB Log Buffer Size' )
                    );
                }

                # if we have reasonable amount of log waits, recommend double the default value
                elsif (( $stats->{is_med_ram} || $stats->{is_high_ram} )
                    && $log_waits > 5_000
                    && $innodb_log_buffer_size < _mebibytes_to_bytes(256) ) {
                    return (
                        '256M',
                        $locale->maketext('Increase the log buffer size to improve disk [asis,I/O] on servers that run many large transactions. A larger log buffer allows these transactions to run without writing to disk.')
                    );
                }

                return;
            }
        },
        key_buffer_size => {
            name           => 'key_buffer_size',
            recommendation => sub ( $dbh, $stats ) {
                my $engine_stats    = $stats->{'storage_engines'};
                my $key_buffer_size = $stats->{'key_buffer_size'} //= _get_current_value( $dbh, 'key_buffer_size' );
                my $default_value   = _mebibytes_to_bytes(8);

                my $has_myisam = ( $engine_stats->{'MyISAM'} && ref( $engine_stats->{'MyISAM'} ) eq 'HASH' );

                # Make sure MyISAM and the key buffer are in use.
                if ( !$has_myisam ) {
                    if ( $key_buffer_size > _kibibytes_to_bytes(64) ) {
                        return ( '64K', $locale->maketext('Your database does not appear to use the [asis,MyISAM] storage engine. We recommend lowering the key buffer size to save memory.') );
                    }
                    return;
                }

                my $total_size = 0;
                $total_size += $_->{'total_size'} foreach values( $engine_stats->%* );
                my $index_size = $engine_stats->{'MyISAM'}{'index_size'};

                my $is_myisam_primary = ( $engine_stats->{'MyISAM'}{'total_size'} / $total_size ) > 0.75;
                my $physical_memory   = _kibibytes_to_bytes( $stats->{'mem_total'} );
                my $rec_value         = int( 1.05 * $index_size );

                my ( @reasons, $max_value );

                # The documentation from MySQL and MariaDB both recommend ~25%, but we're going to err on the lower end.
                _profile_dispatch(
                    $stats,
                    low => sub {
                        push( @reasons, $locale->maketext('To prevent system instability, we recommend that the database server’s memory usage be relatively low.') );
                        $max_value = int( $physical_memory / 16 );
                    },
                    med => sub {
                        push( @reasons, $locale->maketext('To prevent system instability, we recommend that the database server’s memory usage be relatively moderate.') );
                        $max_value = int( $physical_memory / 8 );
                    },
                    high => sub {
                        push( @reasons, $locale->maketext('To prevent system instability, we recommend that the database server’s memory usage be relatively moderate.') );
                        $max_value = int( $physical_memory / 4 );
                    },
                );

                unless ($is_myisam_primary) {
                    push( @reasons, $locale->maketext('Since [asis,MyISAM] is not your primary storage engine, you should keep memory usage balanced between storage engines.') );
                    $max_value /= 2;
                }

                if ( $key_buffer_size == $default_value ) {
                    return if $rec_value <= $default_value;
                }
                elsif ( $key_buffer_size < $default_value ) {
                    unless ( $rec_value > $default_value ) {
                        push( @reasons, $locale->maketext('We recommend that you return this value to its default setting until the total size of your [asis,MyISAM] indexes increases.') );
                        $rec_value = $default_value;
                    }
                }
                else {
                    # 'Key_blocks_used' is a high-water mark that indicates the maximum number of blocks that have ever been in use at one time.
                    my $key_cache_block_size = $stats->{'key_cache_block_size'} //= _get_current_value( $dbh, 'key_cache_block_size' );
                    my $max_key_buffer_used  = $stats->{'Key_blocks_used'} * $key_cache_block_size;
                    my $current_used_ratio   = $max_key_buffer_used / $key_buffer_size;

                    # Suggest an increase of 5% if the high-water mark has reached at least 95% of the key buffer
                    if ( $current_used_ratio >= 0.95 ) {
                        $rec_value = $rec_value > $key_buffer_size ? $rec_value : int( $key_buffer_size * 1.05 );
                        push( @reasons, $locale->maketext('Your key buffer has come under heavy use historically. We recommend increasing this value to facilitate the increased load.') );
                    }
                    else {
                        # Suggest either the normal recommended value of 105% index_length or
                        # 105% max key buffer used if it's larger for some reason.
                        $rec_value = int( $max_key_buffer_used * 1.05 ) if $max_key_buffer_used > $rec_value;
                    }

                    if ( $rec_value > $max_value ) {
                        $rec_value = $max_value;
                        push( @reasons, $locale->maketext('Your key buffer’s size is larger than our recommended maximum. You should reduce the size to avoid paging.') );
                    }
                }

                if ( !defined $rec_value || $rec_value < $default_value ) {
                    return;
                }

                # Ensure we return a value in M/G
                my $one_mebibyte = _mebibytes_to_bytes(1);
                $rec_value -= int( $rec_value % $one_mebibyte );
                $max_value -= int( $max_value % $one_mebibyte );

                my $value  = _format_bytes( $rec_value > $max_value ? $max_value : $rec_value );
                my $reason = join( ' ', @reasons );

                return if $value eq _format_bytes($key_buffer_size);
                return ( $value, $reason );
            },
        },
        innodb_log_file_size => {
            name           => 'innodb_log_file_size',
            recommendation => sub ( $dbh, $stats ) {

                my $innodb_log_file_size = $stats->{'innodb_log_file_size'} //= _get_current_value( $dbh, 'innodb_log_file_size' );

                my $innodb_buffer_pool_size;
                my $rec_reason;
                if ( $stats->{'recommended_innodb_buffer_pool_size'} ) {
                    $innodb_buffer_pool_size = $stats->{'recommended_innodb_buffer_pool_size'};
                    my $pretty_pool_size = _format_bytes($innodb_buffer_pool_size);
                    $rec_reason = $locale->maketext( 'This calculation is based on the recommended value of “[_1]” for “[_2]”.', $pretty_pool_size, 'InnoDB Buffer Pool Size' );
                }
                else {
                    $innodb_buffer_pool_size = $stats->{'innodb_buffer_pool_size'} //= _get_current_value( $dbh, 'innodb_buffer_pool_size' );
                }

                # recommend 25% of the pool size
                my $rec = ( $innodb_buffer_pool_size / 4 );
                $rec -= ( $rec % _mebibytes_to_bytes(1) );

                # Only recommend a lower value if the current value is greater than the entire buffer pool size.
                if ( $innodb_log_file_size > $innodb_buffer_pool_size ) {

                    my $reason = $locale->maketext( 'Decreasing [_1] improves startup times when recovering from a crash. We recommend this value to be 25% of [_2].', 'InnoDB Log File Size', 'InnoDB Buffer Pool Size' );
                    $reason .= ' ' . $rec_reason if $rec_reason;

                    return (
                        _format_bytes($rec),
                        $reason
                    );
                }

                if ( $rec > $innodb_log_file_size ) {

                    my $reason = $locale->maketext( 'To reduce disk [asis,I/O] caused by flushing checkpoint activity, increase [_1].', 'InnoDB Log File Size' );
                    $reason .= ' ' . $rec_reason if $rec_reason;

                    return (
                        _format_bytes($rec),
                        $reason
                    );
                }

                return;
            },
        },
        max_heap_table_size => {
            name           => 'max_heap_table_size',
            recommendation => sub ( $dbh, $stats ) {
                my $max_heap_table_size = $stats->{'max_heap_table_size'} //= _get_current_value( $dbh, 'max_heap_table_size' );
                my $physical_memory     = _kibibytes_to_bytes( $stats->{'mem_total'} );

                my $default = _mebibytes_to_bytes(16);          # Default
                my $value   = int( $physical_memory / 100 );    # 1% is generally recommended
                $value = $default > $value ? $default : $value;

                # return early if we are already using the recommendation.
                return if $max_heap_table_size == $value;

                # Ensure we return a value in M/G
                $value -= $value % _mebibytes_to_bytes(1);

                my $reason;
                if ( $value > $max_heap_table_size && $value != $default ) {
                    $reason = $locale->maketext('We recommend raising this setting’s value to 1% of your total physical memory. It will better accommodate MEMORY tables as they become necessary.');
                }
                elsif ( $value < $max_heap_table_size && $value != $default ) {
                    $reason = $locale->maketext('We recommend lowering this setting’s value to 1% of your total physical memory. It prevents MEMORY tables from allocating too much memory, leading to paging.');
                }
                elsif ( $value != $max_heap_table_size && $value == $default ) {
                    $reason = $locale->maketext('We recommend using this setting’s default value for optimal performance and stability.');
                }
                else {
                    return;
                }

                $value = _format_bytes($value);

                return ( $value, $reason );
            },
        },
        tmp_table_size => {
            name           => 'tmp_table_size',
            recommendation => sub ( $dbh, $stats ) {
                my $tmp_table_size  = $stats->{'tmp_table_size'} //= _get_current_value( $dbh, 'tmp_table_size' );
                my $physical_memory = _kibibytes_to_bytes( $stats->{'mem_total'} );

                my $default = _mebibytes_to_bytes(16);          # Default
                my $value   = int( $physical_memory / 100 );    # 1% is generally recommended
                $value = $default > $value ? $default : $value;

                # return early if we are already using the recommendation.
                return if $tmp_table_size == $value;

                # Ensure we return a value in M/G
                $value -= $value % _mebibytes_to_bytes(1);

                my $reason;
                if ( $value > $tmp_table_size && $value != $default ) {
                    $reason = $locale->maketext('We recommend raising this setting’s value to 1% of your total physical memory. It prevents temporary table creation, leading to slower performance.');
                }
                elsif ( $value < $tmp_table_size && $value != $default ) {
                    $reason = $locale->maketext('We recommend lowering this setting’s value to 1% of your total physical memory. It prevents temporary tables from allocating too much memory, leading to paging.');
                }
                elsif ( $value != $tmp_table_size && $value == $default ) {
                    $reason = $locale->maketext('We recommend using this setting’s default value for optimal performance and stability.');
                }
                else {
                    return;
                }

                $value = _format_bytes($value);

                return ( $value, $reason );
            },
        },
        max_allowed_packet => {
            name           => 'max_allowed_packet',
            recommendation => sub ( $dbh, $stats ) {

                my $max_allowed_packet = $stats->{'max_allowed_packet'} //= _get_current_value( $dbh, 'max_allowed_packet' );

                # keep this in sync with the cronjob adjustment.
                my $adjustment       = $Cpanel::MysqlUtils::MyCnf::Adjust::module_config->{MaxAllowedPacket}{recommend}->();
                my $adjustment_bytes = _mebibytes_to_bytes( $adjustment =~ s/M$//r );

                if ( $max_allowed_packet < $adjustment_bytes ) {
                    return (
                        $adjustment,
                        $locale->maketext( 'Increase [_1] to provide better compatibility with [asis,cPanel] account transfers.', 'Max Allowed Packet' ),
                    );
                }

                return;
            }
        }
    };

    return Clone::clone($settings);
}

1;
