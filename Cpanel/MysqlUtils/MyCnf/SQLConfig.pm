package Cpanel::MysqlUtils::MyCnf::SQLConfig;

# cpanel - Cpanel/MysqlUtils/MyCnf/SQLConfig.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Locale              ();
use Cpanel::MysqlUtils::MyCnf   ();
use Cpanel::Debug               ();
use Cpanel::ConfigFiles         ();
use Cpanel::Database            ();
use Cpanel::MysqlUtils::Connect ();
use Cpanel::MysqlUtils::Dir     ();
use Cpanel::Sys::Hostname       ();
use Cpanel::Version::Compare    ();

use Cpanel::Slurper ();

sub _get_defaults () {
    my $locale = Cpanel::Locale->get_handle();

    # Validation RegEx
    my $bool_re     = { type => 'bool',     pattern => '^(?:[01]|ON|OFF)$',                 flags => 'i', message => '' };
    my $bytes_re    = { type => 'bytes',    pattern => '^(([1-9][0-9]*)|0)[KMGTPE]?$',      flags => 'i', message => $locale->maketext('This value can be either be a number in bytes or a number followed by a binary prefix (KMGTPE) with no leading zeros.') };
    my $filename_re = { type => 'filename', pattern => '(?=^[^\0]+$)(?=^.*[^\/]$)',         flags => '',  message => $locale->maketext('This value can be a valid file name or a full path to a file.') };
    my $int_re      = { type => 'int',      pattern => '^((-?[1-9][0-9]*)|0)$',             flags => '',  message => $locale->maketext('This value must be an integer.') };
    my $decimal_re  = { type => 'decimal',  pattern => '^(?:0|[1-9][0-9]*)?(?:\.[0-9]+)?$', flags => '',  message => $locale->maketext('This value can be an integer or decimal.') };

    # Byte configuration fields (validation => $bytes_re) min, max, and default values that are greater than 2^53
    # (Javascript Number.MAX_SAFE_INTEGER) must be in string format to be correctly validated by the frontend.
    my $mycnf_defaults = {
        innodb_buffer_pool_size => {
            name         => 'innodb_buffer_pool_size',
            category     => 'innodb',
            subcategory  => 'buffer_pool',
            required     => 1,
            default      => 134217728,
            type         => 'number',
            min          => 5242880,
            max          => '9223372036854775807',
            validation   => $bytes_re,
            description  => $locale->maketext('The size in bytes of the buffer pool. The buffer pool is the memory area where [asis,InnoDB] caches table and index data.'),
            section      => 'mysqld',
            friendlyname => $locale->maketext('[asis,InnoDB] Buffer Pool Size'),
        },
        innodb_buffer_pool_instances => {
            name         => 'innodb_buffer_pool_instances',
            category     => 'innodb',
            subcategory  => 'buffer_pool',
            required     => 1,
            default      => 1,
            validation   => $int_re,
            type         => 'number',
            min          => 1,
            max          => 64,
            description  => $locale->maketext('The number of regions that the [asis,InnoDB] buffer pool is divided into. For systems with buffer pools in the multi-gigabyte range, dividing the buffer pool into separate instances may improve concurrency, by reducing contention as different threads read and write to cached pages.'),
            section      => 'mysqld',
            friendlyname => $locale->maketext('[asis,InnoDB] Buffer Pool Instances'),
            removed      => { mariadb => '10.5' },
        },
        innodb_buffer_pool_chunk_size => {
            name         => 'innodb_buffer_pool_chunk_size',
            category     => 'innodb',
            subcategory  => 'buffer_pool',
            required     => 1,
            default      => sub { return Cpanel::Database->new()->default_innodb_buffer_pool_chunk_size() },
            type         => 'number',
            min          => sub { return Cpanel::Database->new()->min_innodb_buffer_pool_chunk_size() },
            max          => '9223372036854775807',
            validation   => $bytes_re,
            description  => $locale->maketext('The chunk size for [asis,InnoDB] buffer pool resizing operations.'),
            section      => 'mysqld',
            friendlyname => $locale->maketext('[asis,InnoDB] Buffer Pool Chunk Size'),
            introduced   => {
                mariadb => '10.2',    # https://web.archive.org/web/20200402142124/https://mariadb.com/kb/en/innodb-system-variables/#innodb_buffer_pool_chunk_size
                mysql   => '5.7',     # https://dev.mysql.com/doc/refman/5.7/en/innodb-parameters.html#sysvar_innodb_buffer_pool_chunk_size, not present in https://downloads.mysql.com/docs/refman-5.6-en.pdf
            },
        },
        innodb_sort_buffer_size => {
            name         => 'innodb_sort_buffer_size',
            category     => 'innodb',
            default      => 1048576,
            required     => 1,
            type         => 'number',
            min          => 65536,
            max          => 67108864,
            validation   => $bytes_re,
            description  => $locale->maketext('The size of sort buffers used to sort data during creation of an [asis,InnoDB] index. A large sort buffer may lead to fewer merge phases while sorting.'),
            section      => 'mysqld',
            friendlyname => $locale->maketext('[asis,InnoDB] Sort Buffer[comment, noun - Sort Buffer is a type of database object] Size'),
        },
        join_buffer_size => {
            name         => 'join_buffer_size',
            category     => 'buffers',
            default      => 262144,
            required     => 1,
            type         => 'number',
            min          => 128,
            max          => '18446744073709547520',
            validation   => $bytes_re,
            description  => $locale->maketext('The minimum size of the buffer that is used for queries that cannot use an index and instead, perform a full table scan. Increase gradually to get potentially faster full joins when adding indexes is not possible. Best left low globally and set high in sessions that require large full joins.'),
            section      => 'mysqld',
            friendlyname => $locale->maketext('Join Buffer[comment, noun - Join Buffer is a type of database object] Size'),
        },
        read_buffer_size => {
            name         => 'read_buffer_size',
            category     => 'buffers',
            default      => 131072,
            required     => 1,
            type         => 'number',
            min          => 8200,
            max          => 2147479552,
            validation   => $bytes_re,
            description  => $locale->maketext('Each thread that does a sequential scan for a [asis,MyISAM] table allocates a buffer of this size in bytes for each table it scans. Increase this setting gradually if you perform many sequential scans.'),
            section      => 'mysqld',
            friendlyname => $locale->maketext('Read Buffer[comment, noun - Read Buffer is a type of database object] Size'),
        },
        read_rnd_buffer_size => {
            name         => 'read_rnd_buffer_size',
            category     => 'buffers',
            default      => 262144,
            required     => 1,
            type         => 'number',
            min          => 8200,
            max          => 2147483647,
            validation   => $bytes_re,
            description  => $locale->maketext('The size in bytes of the buffer used when reading rows from a [asis,MyISAM] table in sorted order after a key sort. Increasing this setting may improve [asis,ORDER BY] performance.'),
            section      => 'mysqld',
            friendlyname => $locale->maketext('Read Random Buffer[comment, noun - Read Random Buffer is a type of database object] Size'),
        },
        sort_buffer_size => {
            name         => 'sort_buffer_size',
            category     => 'buffers',
            default      => 262144,
            required     => 1,
            type         => 'number',
            min          => 32768,
            max          => '18446744073709551615',
            validation   => $bytes_re,
            description  => $locale->maketext('Each session that must perform a sort allocates a buffer of this size.'),
            section      => 'mysqld',
            friendlyname => $locale->maketext('Sort Buffer[comment, noun - Sort Buffer is a type of database object] Size'),
        },
        query_cache_size => {
            name         => 'query_cache_size',
            category     => 'query_cache',
            default      => 1048576,
            required     => 1,
            type         => 'number',
            min          => 0,
            max          => '18446744073709551615',
            validation   => $bytes_re,
            description  => $locale->maketext('The amount of memory allocated for caching query results.'),
            section      => 'mysqld',
            friendlyname => $locale->maketext('Query Cache[comment, noun - Query Cache is a type of database object] Size'),
            removed      => { mysql => '8.0' },
        },
        performance_schema => {
            name         => 'performance-schema',
            category     => '00-general',
            default      => 0,
            required     => 1,
            validation   => $bool_re,
            type         => 'boolean',
            description  => $locale->maketext('This setting enables or disables [asis,Performance Schema]. It is a feature for monitoring the performance of your server.'),
            section      => 'mysqld',
            friendlyname => $locale->maketext('Performance Schema'),
        },
        max_allowed_packet => {
            name         => 'max_allowed_packet',
            category     => '00-general',
            default      => 268435456,
            required     => 1,
            type         => 'number',
            min          => 1024,
            max          => 1073741824,
            validation   => $bytes_re,
            section      => 'mysqld',
            description  => $locale->maketext('Maximum size of a packet or a generated/intermediate string.'),
            friendlyname => $locale->maketext('Max Allowed Packet'),
        },
        open_files_limit => {
            name         => 'open_files_limit',
            category     => '00-general',
            default      => 40_000,
            required     => 1,
            type         => 'number',
            min          => 0,
            max          => 4294967295,
            validation   => $int_re,
            section      => 'mysqld',
            description  => $locale->maketext('The number of file descriptors available for use.'),
            friendlyname => $locale->maketext('Open Files Limit'),
        },
        query_cache_type => {
            name         => 'query_cache_type',
            category     => 'query_cache',
            default      => '0',
            required     => 1,
            type         => 'select',
            values       => [ '0', '1', '2' ],
            section      => 'mysqld',
            description  => $locale->maketext('If set to 0, the query cache is disabled. If set to 1, all [asis,SELECT] queries will use the query cache unless [asis,SQL_NO_CACHE] is specified. If set to 2, only queries with the [asis,SQL CACHE] clause will be cached.'),
            friendlyname => $locale->maketext('Query Cache[comment, noun - Query Cache is a type of database object] Type'),
            removed      => { mysql => '8.0' },
        },
        key_buffer_size => {
            name         => 'key_buffer_size',
            category     => 'buffers',
            default      => 134217728,
            required     => 1,
            min          => 8,
            max          => 4294967295,
            validation   => $bytes_re,
            type         => 'number',
            section      => 'mysqld',
            description  => $locale->maketext('Size of the buffer for the index blocks used by [asis,MyISAM] tables and shared for all threads.'),
            friendlyname => $locale->maketext('Key Buffer Size'),
        },
        slow_query_log => {
            name         => 'slow_query_log',
            category     => '01-logs',
            subcategory  => 'slow_queries',
            required     => 1,
            default      => 0,
            validation   => $bool_re,
            type         => 'boolean',
            section      => 'mysqld',
            description  => $locale->maketext('This setting enables or disables the slow query log.'),
            friendlyname => $locale->maketext('Slow Query Log'),
            removed      => {
                mariadb => '10.11',    # See: log_slow_query
            },
        },
        log_slow_query => {
            name         => 'log_slow_query',
            category     => '01-logs',
            subcategory  => 'slow_queries',
            required     => 1,
            default      => 0,
            validation   => $bool_re,
            type         => 'boolean',
            section      => 'mysqld',
            description  => $locale->maketext('This setting enables or disables the slow query log.'),
            friendlyname => $locale->maketext('Log Slow Queries'),
            introduced   => {
                mariadb => '10.11',    # https://mariadb.com/kb/en/server-system-variables/#log_slow_query_file
            },
        },
        max_heap_table_size => {
            name         => 'max_heap_table_size',
            category     => 'memory_tables',
            default      => 16777216,
            required     => 1,
            type         => 'number',
            min          => 16384,
            max          => 4294966272,
            validation   => $bytes_re,
            section      => 'mysqld',
            description  => $locale->maketext('The maximum size in bytes for user-created MEMORY tables.'),
            friendlyname => $locale->maketext('Max Heap Table Size'),
        },
        tmp_table_size => {
            name         => 'tmp_table_size',
            category     => 'memory_tables',
            default      => 16777216,
            required     => 1,
            type         => 'number',
            min          => 1024,
            max          => 4294967295,
            validation   => $bytes_re,
            section      => 'mysqld',
            description  => $locale->maketext('The largest size for temporary tables stored in memory. This does not include MEMORY tables. The value of [asis,max_heap_table_size] will override this setting if it is a smaller value.'),
            friendlyname => $locale->maketext('Temporary Table Size'),
        },
        log_output => {
            name         => 'log_output',
            category     => '01-logs',
            default      => 'FILE',
            required     => 1,
            type         => 'select',
            values       => [ 'FILE', 'TABLE', 'NONE' ],
            section      => 'mysqld',
            description  => $locale->maketext('How the output for the general query log and the slow query log is stored.'),
            friendlyname => $locale->maketext('Log[comment, noun - Log is a log file] Output'),
        },
        general_log => {
            name         => 'general_log',
            category     => '01-logs',
            subcategory  => '00-general',
            required     => 1,
            default      => '0',
            validation   => $bool_re,
            type         => 'boolean',
            section      => 'mysqld',
            description  => $locale->maketext('This setting enables or disables the general query log. The general query log is a general record of what the database is doing.'),
            friendlyname => $locale->maketext('General Logging'),
        },
        general_log_file => {
            name         => 'general_log_file',
            category     => '01-logs',
            subcategory  => '00-general',
            required     => 1,
            default      => sub { return _log_filename() },
            validation   => $filename_re,
            type         => 'text',
            section      => 'mysqld',
            description  => $locale->maketext('Name of the general query log file.'),
            friendlyname => $locale->maketext('General Log File Name'),
        },
        log_error => {
            name         => 'log_error',
            category     => '01-logs',
            subcategory  => '01-errors',
            required     => 1,
            default      => sub { return _log_filename('.err') },
            validation   => $filename_re,
            type         => 'text',
            section      => 'mysqld',
            description  => $locale->maketext('Specifies the name of the error log.'),
            friendlyname => $locale->maketext('Error Log File Name'),
        },
        log_error_verbosity => {
            name         => 'log_error_verbosity',
            category     => '01-logs',
            subcategory  => '01-errors',
            required     => 1,
            default      => '3',
            type         => 'select',
            values       => [ '1', '2', '3' ],
            section      => 'mysqld',
            description  => $locale->maketext('The verbosity of the server in writing various log messages. Set to 1 for error messages only, 2 for errors and warnings, and 3 for errors, warnings, and information messages.'),
            friendlyname => $locale->maketext('Error Log Verbosity'),
            introduced   => { mysql   => '5.7' },
            removed      => { mariadb => '10' },
        },
        log_warnings => {
            name         => 'log_warnings',
            category     => '01-logs',
            subcategory  => '01-errors',
            required     => 1,
            default      => '2',
            type         => 'select',
            values       => [ '1', '2', '3', '4', '9' ],
            section      => 'mysqld',
            description  => $locale->maketext('This setting determines which additional warnings are logged. Larger numbers increase verbosity.'),
            friendlyname => $locale->maketext('Log[comment, noun - Log is a log file] Warnings'),
            removed      => { mysql => '5.7' },
        },
        thread_cache_size => {
            name         => 'thread_cache_size',
            category     => '00-general',
            default      => 256,
            required     => 1,
            type         => 'number',
            min          => 0,
            max          => 16384,
            validation   => $int_re,
            section      => 'mysqld',
            description  => $locale->maketext('The number of threads the server stores in a cache for re-use.'),
            friendlyname => $locale->maketext('Thread Cache Size'),
        },
        sql_mode => {
            name         => 'sql_mode',
            category     => '00-general',
            default      => '',
            type         => 'long_text',
            section      => 'mysqld',
            validation   => { type => 'sqlmode', pattern => q{^(?:''|[A-Z0-9_]+(?:,[A-Z0-9_]+)*)$}, flags => 'i', message => 'This value can be a comma-delimited list of modes or set to \'\' to disable all modes.' },
            description  => $locale->maketext( 'The [asis,SQL] server can operate in different [asis,SQL] modes depending on the value of the [asis,sql_mode] system variable. This is a comma delimited list of modes to activate. Visit [output,url,_1,target,_blank] for more information.', 'https://go.cpanel.net/sqlmodes' ),
            friendlyname => $locale->maketext('[asis,SQL] Mode'),
        },
        long_query_time => {
            name         => 'long_query_time',
            category     => '01-logs',
            subcategory  => 'slow_queries',
            required     => 1,
            default      => 10,
            type         => 'number',
            min          => 0,
            max          => 31536000,
            validation   => $decimal_re,
            section      => 'mysqld',
            description  => $locale->maketext('This setting will log all queries that have taken more than the specified number of seconds to execute to the slow query log file. The argument will be treated as a decimal value with microsecond precision.'),
            friendlyname => $locale->maketext('Long Query Time'),
            removed      => {
                mariadb => '10.11',    # See: log_slow_query_time
            },
        },
        log_slow_query_time => {
            name         => 'log_slow_query_time',
            category     => '01-logs',
            subcategory  => 'slow_queries',
            required     => 1,
            default      => 10,
            type         => 'number',
            min          => 0,
            max          => 31536000,
            validation   => $decimal_re,
            section      => 'mysqld',
            description  => $locale->maketext('This setting will log all queries that have taken more than the specified number of seconds to execute to the slow query log file. The argument will be treated as a decimal value with microsecond precision.'),
            friendlyname => $locale->maketext('Long Query Time'),
            introduced   => {
                mariadb => '10.11',    # https://mariadb.com/kb/en/server-system-variables/#log_slow_query_time
            },
        },
        slow_query_log_file => {
            name         => 'slow_query_log_file',
            category     => '01-logs',
            subcategory  => 'slow_queries',
            required     => 1,
            default      => sub { return _log_filename('-slow.log') },
            validation   => $filename_re,
            type         => 'text',
            section      => 'mysqld',
            description  => $locale->maketext('The name or full path of the slow query log file.'),
            friendlyname => $locale->maketext('Slow Query Log File Name'),
            removed      => {
                mariadb => '10.11',    # See: log_slow_query_file
            },
        },
        log_slow_query_file => {
            name         => 'log_slow_query_file',
            category     => '01-logs',
            subcategory  => 'slow_queries',
            required     => 1,
            default      => sub { return _log_filename('-slow.log') },
            validation   => $filename_re,
            type         => 'text',
            section      => 'mysqld',
            description  => $locale->maketext('The name or full path of the slow query log file.'),
            friendlyname => $locale->maketext('Slow Query Log File Name'),
            introduced   => {
                mariadb => '10.11',    # https://mariadb.com/kb/en/server-system-variables/#log_slow_query
            },
        },
        max_connections => {
            name         => 'max_connections',
            category     => '00-general',
            default      => 151,
            required     => 1,
            type         => 'number',
            min          => 0,
            max          => 100000,
            validation   => $int_re,
            section      => 'mysqld',
            description  => $locale->maketext('The maximum permitted number of simultaneous client connections.'),
            friendlyname => $locale->maketext('Max Connections'),
        },
        max_connect_errors => {
            name         => 'max_connect_errors',
            category     => '00-general',
            default      => 100,
            required     => 1,
            type         => 'number',
            min          => 1,
            max          => 4294967295,
            validation   => $int_re,
            section      => 'mysqld',
            description  => $locale->maketext('The maximum number of aborted connection attempts per host before the host is blocked by the server. This does not protect against brute force attempts.'),
            friendlyname => $locale->maketext('Max Connect Errors'),
        },
        interactive_timeout => {
            name         => 'interactive_timeout',
            category     => '00-general',
            subcategory  => 'timeouts',
            required     => 1,
            default      => 28800,
            type         => 'number',
            min          => 1,
            max          => 31536000,
            validation   => $int_re,
            section      => 'mysqld',
            description  => $locale->maketext('The time in seconds that the server waits for an idle interactive connection to become active before closing it.'),
            friendlyname => $locale->maketext('Interactive Timeout'),
        },
        wait_timeout => {
            name         => 'wait_timeout',
            category     => '00-general',
            subcategory  => 'timeouts',
            required     => 1,
            default      => 28800,
            type         => 'number',
            min          => 1,
            max          => 31536000,
            validation   => $int_re,
            section      => 'mysqld',
            description  => $locale->maketext('The number of seconds the server waits for activity on a connection before closing it.'),
            friendlyname => $locale->maketext('Wait Timeout'),
        },
        innodb_log_buffer_size => {
            name         => 'innodb_log_buffer_size',
            category     => 'innodb',
            default      => 16777216,
            required     => 1,
            type         => 'number',
            min          => 1048576,
            max          => 4294967295,
            validation   => $bytes_re,
            section      => 'mysqld',
            description  => $locale->maketext('The size of the buffer that [asis,InnoDB] uses to write to the log files on disk. Increasing this value means larger transactions can run without needing to perform disk I/O before committing.'),
            friendlyname => $locale->maketext('[asis,InnoDB] Log Buffer[comment, noun - Log Buffer is a type of database object] Size'),
        },
        innodb_log_file_size => {
            name         => 'innodb_log_file_size',
            category     => 'innodb',
            default      => 50331648,
            required     => 1,
            type         => 'number',
            min          => 4194304,
            max          => '18446744073709551615',
            validation   => $bytes_re,
            section      => 'mysqld',
            description  => $locale->maketext('The size of each [asis,InnoDB] log file in a log group. Larger values mean less disk I/O due to less flushing, but also slower recovery from a crash.'),
            friendlyname => $locale->maketext('[asis,InnoDB] Log File Size'),
        },
    };

    return $mycnf_defaults;
}

sub get_settings ( $db_type, $db_version ) {

    return unless $db_type =~ m/^(?:mariadb|mysql)$/i && $db_version =~ m/^[0-9.]+$/;

    require Clone;
    my $all_settings = Clone::clone( _get_defaults() );

    my @possible_coderefs = ( 'default', 'min' );

    my $filtered_settings = {};

    for my $setting_name ( keys %$all_settings ) {
        my $setting = $all_settings->{$setting_name};

        if ( $setting->{introduced} ) {

            if ( $setting->{introduced}{$db_type} ) {

                # Remove if setting was NOT introduced in the current version or greater
                next if _cmp_version( $setting->{introduced}{$db_type}, '>', $db_version );
            }
            else {
                # Remove if the setting was introduced only in a different db type, so not supported in the current db type.
                next;
            }
        }

        if ( $setting->{removed} && $setting->{removed}{$db_type} ) {

            # Remove if the setting was removed in a version of the current db type for the current version or earlier.
            next if _cmp_version( $setting->{removed}{$db_type}, '<=', $db_version );
        }

        for my $key (@possible_coderefs) {
            if ( $setting->{$key} && ref( $setting->{$key} ) eq 'CODE' ) {
                $setting->{$key} = $setting->{$key}->();
            }
        }

        $filtered_settings->{$setting_name} = $setting;
    }

    # The default sql_mode changes based on the database version...
    $filtered_settings->{sql_mode}{default} = get_default_sql_mode();

    return $filtered_settings;
}

sub _cmp_version ( $version1, $operator, $version2 ) {
    return Cpanel::Version::Compare::compare( $version1, $operator, $version2 );
}

sub process_mycnf_changes ( $changes, $opts = {} ) {

    my $mycnf = $Cpanel::ConfigFiles::MYSQL_CNF;

    my %args = ( user => 'root', mycnf => $mycnf );

    if ( $opts->{remove} ) {
        $args{remove}     = 1;
        $args{if_present} = 1;
    }

    for my $change ( keys %$changes ) {
        my $ret = eval { Cpanel::MysqlUtils::MyCnf::update_mycnf( %args, section => $change, items => $changes->{$change} ) };
        if ( $@ || !$ret ) {
            my $err = $@ || "Unknown failure.";
            Cpanel::Debug::log_error("Failed to update $mycnf: $err");
            return;
        }
    }
    return 1;
}

sub get_mycnf ( $mycnf = $Cpanel::ConfigFiles::MYSQL_CNF ) {

    my $contents = eval { Cpanel::Slurper::read($mycnf) };
    if ($@) {
        Cpanel::Debug::log_error("Failed to read file $mycnf: $@");
        return;
    }
    return $contents;
}

sub save_mycnf ( $content, $mycnf = $Cpanel::ConfigFiles::MYSQL_CNF ) {
    eval { Cpanel::Slurper::write( $mycnf, $content ) };
    if ($@) {
        Cpanel::Debug::log_error("Failed to write file $mycnf: $@");
        return;
    }
    return 1;
}

sub get_default_sql_mode {
    return Cpanel::Database->new()->default_sql_mode;
}

sub get_current_sql_mode {
    my $dbh = eval { Cpanel::MysqlUtils::Connect::get_dbi_handle() };
    if ($@) {
        Cpanel::Debug::log_info("Unable to query for the current SQL mode value: $@.");
        Cpanel::Debug::log_info("Continuing with the default SQL mode value for this database version.");
    }
    return get_default_sql_mode() if !$dbh;
    return ( $dbh->selectrow_array('SELECT @@GLOBAL.sql_mode') )[0] // "''";
}

sub _log_filename ( $postfix = ".log" ) {

    my $datadir      = Cpanel::MysqlUtils::Dir::getmysqldir() || '/var/lib/mysql/';
    my $default_name = $datadir . Cpanel::Sys::Hostname::shorthostname() . $postfix;

    return $default_name;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::MyCnf::SQLConfig

=head1 SYNOPSIS

This module contains some convenience methods and data related to the SQL Config UI in WHM.

=head1 METHODS

=over

=item * process_mycnf_changes -- Applies some changes to the system database configuration, /etc/my.cnf

=over

Arguments:

$changes -- Required -- hashref, each hash key is the "section" within the configuration, ie "mysqld". The key and value pairs are the desired settings within the seciton. It should be in this form:

{
    'mysqld' => [
        { max_allowed_packet => 40000 },
        { innodb_file_per_table => 1 },
    ]
}

$opts -- Optional -- hashref of optional options. Only current value is 'remove'. When remove is set to a true value, the values in the $changes hashref will be removed.

=back

=item * get_mycnf -- returns the contents of the default my.cnf file.

=over

Assumptions:

The mycnf contains only properties known for the database type and version. There is a conversion process that runs elsewhere that handles this conversion.

Arguments:

$my_cnf -- Optional -- The file to load. Default: /etc/my.cnf

=back

=item * save_mycnf -- writes a new my.cnf to disk.

=over

Arguments:

$content -- Required -- The exact content to write to disk.

$my_cnf -- Optional -- The file to write to. Default: /etc/my.cnf

=back

=item * get_default_sql_mode -- returns the default SQL mode for the currently running database as a string.

=over

Arguments:

None.

=back

=item * get_current_sql_mode -- returns the current SQL mode for the running database as a string. If it can not be found, returns empty quotations, ''. This does not return a quoted string if the current sql mode is successfully found.

=over

Arguments:

None.

=back

=item * get_settings -- returns a hash_ref of curated SQL settings to be consumed by the SQL Configuration UI in WHM.

=over

Arguments:

$db - The database to retrieve settings for. This can currently be 'mysql' or 'mariadb'.

$version - The database version to retrieve settings for. This can be in major.minor version form. Example: "10.5", "8.0"

=back

=back
