package Cpanel::MysqlUtils::MyCnf::Migrate;

# cpanel - Cpanel/MysqlUtils/MyCnf/Migrate.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::StringFunc::File          ();
use Cpanel::SafeRun::Errors           ();
use Cpanel::MysqlUtils::Logs          ();
use Cpanel::MysqlUtils::MyCnf::Full   ();
use Cpanel::DbUtils                   ();
use Cpanel::MysqlUtils::MyCnf         ();
use Cpanel::MysqlUtils::MyCnf::Modify ();
use Cpanel::MysqlUtils::Versions      ();
use Cpanel::Database                  ();
use Cpanel::Version::Compare          ();
use Cpanel::OS                        ();
use Cpanel::Autodie                   ();

=encoding utf-8

=head1 MODULE

C<Cpanel::MysqlUtils::MyCnf::Migrate>

=head1 DESCRIPTION

C<Cpanel::MysqlUtils::MyCnf::Migrate> provides functionality to migrate a my.cnf file to a different
version of MySQL or MariaDB.

=head1 FUNCTIONS

=cut

#----------------------------------------------------------------------
#NOTE: IMPORTANT - Always specify options below using dashes, not underscores.
#Dashes are a "normalized" format.
#cf. http://dev.mysql.com/doc/refman/4.1/en/program-variables.html
#----------------------------------------------------------------------

#This logic derives principally from MySQL's "what's new" documents:
#http://dev.mysql.com/doc/refman/5.5/en/mysql-nutshell.html
#http://dev.mysql.com/doc/refman/5.6/en/mysql-nutshell.html

sub _removed_keys_in_version {
    my ($version) = @_;

    if ( $version eq '5.1' ) {
        return (
            'bdb-cache-size',
            'bdb-home',
            'bdb-lock-detect',
            'bdb-log-buffer-size',
            'bdb-logdir',
            'bdb-max-lock',
            'bdb-no-recover',
            'bdb-no-sync',
            'bdb-shared-data',
            'bdb-tmpdir',
            'skip-bdb',
            'skip-sync-bdb-logs',
            'sync-bdb-logs',
        );
    }
    elsif ( $version eq '5.5' ) {
        return (
            'enable-pstack',
            'log-long-format',
            'master-connect-retry',
            'master-host',
            'master-password',
            'master-port',
            'master-ssl',
            'master-ssl-ca',
            'master-ssl-capath',
            'master-ssl-cert',
            'master-ssl-cipher',
            'master-ssl-key',
            'master-user',
            'myisam-max-extra-sort-file-size',
            'safe-show-database',
            'skip-innodb',
            'skip-safemalloc',
            'sql-bin-update-same',
            'sql-log-update',
            'table-lock-wait-timeout',

            #The docs don't SAY that 5.5 is incompatible with this option;
            #however, it actually does disable InnoDB, which, since InnoDB
            #is the default storage engine, can cause mysqld to fail to start.
            #It's best to remove this option.
            'disable-builtin-innodb',

            #Documented in 4.1 but not in 5.0 nor 5.1.
            #5.5's "what's new" doc says it (itself) removed this.
            'log-update',
        );
    }
    elsif ( $version eq '5.6' ) {
        return (
            'delayed-insert-limit',
            'delayed-insert-timeout',
            'delayed-queue-size',

            #TODO: Figure out a way to migrate this to use "optimizer-switch",
            #as per MySQL 5.6's documentation.
            'engine-condition-pushdown',

            'old-passwords',    # must be disabled in 5.6 or it won't startup
            'initial-rpl-role',
            'rpl-recovery-rank',
            'optimizer-join-cache-level',
            'safe-mode',
            'skip-thread-priority',
        );
    }
    elsif ( $version eq '5.7' ) {

        # https://mysqlserverteam.com/removal-and-deprecation-in-mysql-5-7/
        return (
            'innodb-additional-mem-pool-size',
            'innodb-use-sys-malloc',
            'innodb-mirrored-log-groups',
            'timed-mutexes',
            'storage-engine',
            'thread-concurrency',
        );
    }
    elsif ( $version eq '8.0' ) {

        # https://dev.mysql.com/doc/refman/8.0/en/added-deprecated-removed.html#optvars-removed
        return qw{Com_alter_db_upgrade Innodb_available_undo_logs
          Qcache_free_blocks Qcache_free_memory Qcache_hits Qcache_inserts
          Qcache_lowmem_prunes Qcache_not_cached Qcache_queries_in_cache
          Qcache_total_blocks Slave_heartbeat_period Slave_last_heartbeat
          Slave_received_heartbeats Slave_retried_transactions Slave_running
          bootstrap date_format datetime_format des-key-file
          group_replication_allow_local_disjoint_gtids_join have_crypt
          ignore-db-dir ignore_builtin_innodb ignore_db_dirs
          innodb_checksums innodb_disable_resize_buffer_pool_debug
          innodb_file_format innodb_file_format_check innodb_file_format_max
          innodb_large_prefix innodb_locks_unsafe_for_binlog
          innodb_scan_directories innodb_stats_sample_pages
          innodb_support_xa innodb_undo_logs internal_tmp_disk_storage_engine
          log-warnings log_builtin_as_identified_by_password
          log_error_filter_rules log_syslog log_syslog_facility
          log_syslog_include_pid log_syslog_tag max_tmp_tables
          metadata_locks_cache_size metadata_locks_hash_instances
          multi_range_count old_passwords partition query_cache_limit
          query_cache_min_res_unit query_cache_size query_cache_type
          query_cache_wlock_invalidate secure_auth show_compatibility_56
          skip-partition sync_frm temp-pool time_format tx_isolation
          tx_read_only};
    }
    elsif ( $version eq '10.3' ) {

        # https://mariadb.com/kb/en/library/innodb-system-variables/
        return (
            'innodb-instrument-semaphores',
            'innodb-safe-truncate',
            'innodb-support-xa',
            'innodb-use-fallocate',
            'innodb-use-trim',
            'innodb-large-prefix',
            'innodb-file-format',
            'innodb-file-format-check',
            'innodb-file-format-max',
            'innodb-use-mtflush',
            'innodb-mtflush-threads',
        );
    }
    elsif ( $version eq '10.11' ) {
        return (
            'innodb-log-write-ahead-size',
            'keep-files-on-create',
        );
    }
    elsif ( grep { $version == $_ } Cpanel::MysqlUtils::Versions::get_versions() ) {
        return ();
    }

    die "Bad version: $version";
}

# some of the keys in changed keys in version
# assume that the key has a value associated with it
# in older versions they do not need a value so
# the change would not work, the best thing for us
# to do in that case is to change the key in a different
# way if there is not value.
#
# example: log becomes
# general_log=1\ngeneral_log_file=filename
# this fails if log did not have a file name

sub _changed_keys_if_no_value_in_version {
    my ($version) = @_;

    if ( $version eq '5.5' ) {
        return ();
    }
    elsif ( $version eq '5.6' ) {
        return (
            'log'                => "general_log=1",
            'log-slow-queries'   => "slow_query_log=1",
            'performance-schema' => 'performance-schema=1',
        );
    }
    elsif ( grep { $version == $_ } Cpanel::MysqlUtils::Versions::get_versions() ) {
        return ();
    }

    die "Bad version: $version";
}

sub _changed_keys_in_version {
    my ($version) = @_;

    if ( $version eq '5.1' ) {
        return;
    }
    elsif ( $version eq '5.5' ) {
        return (
            #Undocumented after 4.1 (?) until 5.5 describes the removal
            'delay-key-write-for-all-tables' => 'delay-key-write=ALL',

            'default-collation'              => 'collation-server',
            'default-table-type'             => 'default-storage-engine',
            'enable-locking'                 => 'external-locking',
            'innodb-file-io-threads'         => [ 'innodb_read_io_threads', 'innodb_write_io_threads', ],
            'language'                       => 'lc-messages-dir',
            'log-bin-trust-routine-creators' => 'log-bin-trust-function-creators',
            'record-buffer'                  => 'read_buffer_size',
            'skip-locking'                   => 'skip-external-locking',
            'skip-symlink'                   => 'skip-symbolic-links',
            'use-symbolic-links'             => 'symbolic-links',
            'warnings'                       => 'log-warnings',

            #This looks like a Percona-only directive .. ?
            #http://www.percona.com/doc/percona-server/5.5/diagnostics/user_stats.html?id=percona-server:features:userstatv2
            'userstat-running' => 'userstat',
        );
    }
    elsif ( $version eq '5.6' ) {
        return (
            'log'                      => "general_log=1\ngeneral_log_file",
            'log-slow-queries'         => "slow_query_log=1\nslow_query_log_file",
            'one-thread'               => 'thread_handling=no-threads',
            'table-cache'              => 'table_open_cache',
            'sql-big-tables'           => 'big-tables',
            'sql-low-priority-updates' => 'low-priority-updates',
            'sql-max-join-size'        => 'max-join-size',
            'max-long-data-size'       => 'max-allowed-packet',
        );
    }
    elsif ( $version eq '5.7' ) {
        return (
            # Not mentioned in the release notes but 'key-buffer' is removed in 5.7 and will cause it to fail
            'key-buffer' => 'key-buffer-size',
        );
    }
    elsif ( $version eq '10.11' ) {
        return (
            'min-examined-row-limit' => 'log_slow_min_examined_row_limit',
            'slow-query-log'         => 'log_slow_query',
            'slow-query-log-file'    => 'log_slow_query_file',
            'long-query-time'        => 'log_slow_query_time',
        );
    }
    elsif ( grep { $version == $_ } Cpanel::MysqlUtils::Versions::get_versions() ) {
        return ();
    }

    die "Bad version: $version";
}

# There may be cases where we want to add a key that does not already exist
# due to certain special cases.
#

sub _special_case_add_keys_in_version {
    my ( $version, $cnf_file ) = @_;

    my @output;

    if ( $version eq '5.6' ) {

        # Case CPANEL-6183, if performance-schema has not been specifically
        # enabled, add a performance-schema=0 line to disable it as it
        # is enabled by default in MySQL 5.6

        my $ref = {
            'value'   => 0,
            'section' => 'mysqld',
            'key'     => 'performance-schema',
            'line'    => "performance-schema=0\n",
        };

        push( @output, $ref );
    }
    elsif ( $version eq '8.0' ) {

        # See HB-5325. Best way to ensure compatibility with supported versions
        # is to use something supported on all supported upgrade targets.
        push @output, {
            'section' => 'mysqld',
            'key'     => 'default-authentication-plugin',
            'value'   => 'mysql_native_password',
            'line'    => "default-authentication-plugin=mysql_native_password\n",
        };

        my $mycnf = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf($cnf_file);

        if ( $mycnf->{'mysqld'} && !defined $mycnf->{'mysqld'}->{'log_bin'} ) {
            push @output, {
                'section' => 'mysqld',
                'key'     => 'disable-log-bin',
                'value'   => '1',
                'line'    => "disable-log-bin=1\n",
            };
        }
    }
    elsif ( $version eq '10.1' ) {

        my $error_log_file = Cpanel::MysqlUtils::Logs::get_mysql_error_log_file();

        if ($error_log_file) {

            my $ref = {
                'section' => 'mysqld',
                'key'     => 'log-error',
                'line'    => "log-error=$error_log_file\n",
            };

            push( @output, $ref );
        }
    }

    return @output;
}

sub _section_specific_keys_in_version {
    my ($version) = @_;

    if ( $version eq '5.1' ) {
        return;
    }
    elsif ( $version eq '5.5' ) {
        return (
            'mysqld' => {
                'default-character-set' => 'character-set-server',
            },
            'mysql' => {
                'no-named-commands' => 'skip-named-commands',
                'no-pager'          => 'skip-pager',
                'no-tee'            => 'skip-tee',
            },
            'mysqlbinlog' => {
                'position' => 'start-position',
            },
            'mysqldump' => {
                'all'         => 'create-options',
                'first-slave' => 'lock-all-tables',
            },
            'mysqld_multi' => {
                'default-character-set' => 'character-set-server',
                'config-file'           => 'defaults-extra-file',
            },
        );
    }
    elsif ( grep { $version == $_ } Cpanel::MysqlUtils::Versions::get_versions() ) {
        return ();
    }

    die "Bad version: $version";
}

#This will update all old my.cnf versions iteratively until the
#passed-in version. As of this writing, that means if you pass in 5.6,
#we first update for 5.5, then do 5.6. When/if 5.7 gets added, we'll do
#5.5, 5.6, then 5.7.
#
#NOTE: $path defaults to $Cpanel::ConfigFiles::MYSQL_CNF.
#
sub migrate_for_version {
    my ( $path, $mysql_version ) = @_;

    for my $version ( Cpanel::MysqlUtils::Versions::get_versions() ) {
        next if Cpanel::Version::Compare::compare( $version, '>', $mysql_version );
        next if $version == '8.0';                                                    # We can only upgrade TO 8.0, there are no paths from it yet (21-04-2020).

        my @removed             = _removed_keys_in_version($version);
        my %changed             = _changed_keys_in_version($version);
        my %changed_if_no_value = _changed_keys_if_no_value_in_version($version);
        my %section_changes     = _section_specific_keys_in_version($version);

        Cpanel::MysqlUtils::MyCnf::Modify::modify(
            sub {
                return _to_modify(
                    \@removed,
                    \%changed,
                    \%section_changes,
                    \%changed_if_no_value,
                    @_,    #section, key, value
                );
            },
            $path,
        );
    }

    my @special_cases = _special_case_add_keys_in_version( $mysql_version, $path );
    Cpanel::MysqlUtils::MyCnf::Modify::add( $path, @special_cases );

    # The 'pid-file' directive doesn't fit any of the buckets above
    # but still needs to be checked/adjusted - as certain upgrade paths will result
    # in the location being unreachable, because the directory they are
    # configured to be in doesn't exist, etc.
    #
    # For example, MySQL 5.7 sets the 'pid-file' to '/var/run/mysqld/mysqld.pid'
    # however upon upgrading to mariadb, the package that owns the '/var/run/mysqld'
    # directory is removed, which makes this location unreachable.
    if ( !is_pidfile_valid($path) ) {
        Cpanel::MysqlUtils::MyCnf::Modify::modify(
            sub {
                my ( $section, $key, $value ) = @_;

                return ['COMMENT']
                  if $section eq 'mysqld' && $key eq 'pid-file';

                return;
            },
            $path,
        );
    }

    return;
}

sub _to_modify {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $removed_ref, $changed_ref, $section_specific_ref, $changed_if_no_value_ref, $section, $key, $value ) = @_;

    #NOTE: No MySQL versions that we care about need "set-variable",
    #and 5.5 actually removes support for it.
    #cf. http://dev.mysql.com/doc/refman/4.1/en/program-variables.html
    if ( $key =~ m<\Aset[_-]variable\z> ) {
        ( $key, $value ) = split /=/, $value, 2;
    }

    #MySQL allows using dashes in place of underscores.
    #cf. http://dev.mysql.com/doc/refman/4.1/en/program-variables.html
    my $key_with_dashes = $key;
    $key_with_dashes =~ tr<_><->;

    #----------------------------------------------------------------------
    #XXX And as a special bonus just for playing "How Stupid Can Our
    #Configuration File Format Be?", MySQL will, for free, interpret
    #any "unambiguous prefix" for a configuration directive as that directive.
    #So if you write "max_a=5M", MySQL reads that as "max_allowed_packet=5M".
    #...at least, until they add "max_annoyance_factor" as a variable, in which
    #case MySQL will whine about an ambiguous option.
    #
    #There's no way we can feasibly accommodate this (right?), so hopefully
    #no customers are actually using it.
    #cf. http://dev.mysql.com/doc/refman/4.1/en/program-variables.html
    #----------------------------------------------------------------------

    if ( grep { $_ eq $key_with_dashes } @{$removed_ref} ) {
        return [ 'COMMENT', $key, $value ];
    }

    # the distinction here, is the value is in the changed_if_no_value and the
    # key does not have a value, that is log vs log=/tmp/mysql.log

    if ( exists $changed_if_no_value_ref->{$key_with_dashes} && ( !defined $value || $value eq "" ) ) {
        my %new_values;

        if ( 'ARRAY' eq ref $changed_if_no_value_ref->{$key_with_dashes} ) {
            @new_values{ @{ $changed_if_no_value_ref->{$key_with_dashes} } } = ($value) x @{ $changed_if_no_value_ref->{$key_with_dashes} };
        }
        else {
            $new_values{ $changed_if_no_value_ref->{$key_with_dashes} } = $value;
        }

        return \%new_values;
    }

    if ( exists $changed_ref->{$key_with_dashes} ) {
        my %new_values;

        if ( 'ARRAY' eq ref $changed_ref->{$key_with_dashes} ) {
            @new_values{ @{ $changed_ref->{$key_with_dashes} } } = ($value) x @{ $changed_ref->{$key_with_dashes} };
        }
        else {
            $new_values{ $changed_ref->{$key_with_dashes} } = $value;
        }

        return \%new_values;
    }

    foreach my $mysql_section ( keys %{$section_specific_ref} ) {
        if ( $section eq $mysql_section ) {
            foreach my $old_key ( keys %{ $section_specific_ref->{$mysql_section} } ) {
                if ( $key_with_dashes eq $old_key ) {
                    return { $section_specific_ref->{$mysql_section}{$old_key}, $value };
                }
            }
        }
    }

    #Always return in case we removed "set-variable".
    return { $key, $value };
}

sub possible_to_migrate_my_cnf_file {
    my ( $cnf_file, $mysql_version, $current_version ) = @_;

    # Being that we can only check against the currently installed mysqld,
    # we will only check if the target and installed versions match.
    return 1 unless $mysql_version == $current_version;

    return 1 if !-e $cnf_file;

    # mysqld in these versions doesn't fail on invalid options.
    return 1 if $current_version <= 5.1;

    require Cpanel::TempFile;
    my $tmp_obj          = Cpanel::TempFile->new();
    my $temp_my_cnf_file = $tmp_obj->file();

    Cpanel::SafeRun::Errors::saferunnoerror( '/bin/cp', '-f', '--', $cnf_file, $temp_my_cnf_file );
    if ($?) {
        die "Failed to copy “$cnf_file” to temporary location because of an error: $!.\n";
    }

    migrate_my_cnf_file( $temp_my_cnf_file, $mysql_version );

    # We need to ensure the tmp file created above can be read by the database user
    # before sending it off to _check_for_config_errors().
    require Cpanel::PwCache;
    my $uid = ( Cpanel::PwCache::getpwnam( Cpanel::Database->new()->user ) )[2];
    chown( $uid, 0, $temp_my_cnf_file );

    my $check = _check_for_config_errors($temp_my_cnf_file);
    die "Failed to validate my.cnf file for version $mysql_version:\n$check" if length $check;

    return 1;
}

sub migrate_my_cnf_file {
    my ( $cnf_file, $mysql_version ) = @_;

    symlink_additional_conf_files();

    my $empty = !( -e $cnf_file && -s _ );

    if ( Cpanel::Version::Compare::compare( $mysql_version, '>', '5.1' ) ) {

        # all that removal logic is now useless when upgrading
        #   keep it as a security if a user add some deprecated directives to its my.cnf file
        Cpanel::StringFunc::File::remlinefile( $cnf_file, 'plugin-load=innodb=ha_innodb_plugin.so' );
        Cpanel::StringFunc::File::remlinefile( $cnf_file, 'plugin-load=innodb=ha_innodb_plugin.so;innodb_trx=ha_innodb_plugin.so;innodb_locks=ha_innodb_plugin.so;innodb_lock_waits=ha_innodb_plugin.so;innodb_cmp=ha_innodb_plugin.so;innodb_cmp_reset=ha_innodb_plugin.so;innodb_cmpmem=ha_innodb_plugin.so;innodb_cmpmem_reset=ha_innodb_plugin.so' );

        foreach my $avail_mysql_version ( Cpanel::MysqlUtils::Versions::get_versions() ) {
            last if ( Cpanel::Version::Compare::compare( $avail_mysql_version, '>', $mysql_version ) );
            next if $avail_mysql_version == '8.0';                                                        # We can only upgrade TO 8.0, there are no paths from it yet (21-04-2020).

            Cpanel::MysqlUtils::MyCnf::Migrate::migrate_for_version( $cnf_file, $avail_mysql_version );
        }

        Cpanel::MysqlUtils::MyCnf::Migrate::migrate_for_version( $cnf_file, $mysql_version );
    }

    if ( Cpanel::Version::Compare::compare( $mysql_version, '>', '5.1' ) ) {
        enable_innodb_file_per_table($cnf_file);
    }
    if ( $empty && Cpanel::Version::Compare::compare( $mysql_version, '>', '5.5' ) ) {
        disable_performance_schema($cnf_file);
    }

    if ( Cpanel::Version::Compare::compare( $mysql_version, '>', '5.1' ) ) {    # according to a comment above, mysqld does not fail on invalid options in 5.1 and lower
        scrub_invalid_values($cnf_file);
    }

    if ( Cpanel::Version::Compare::compare( $mysql_version, '>=', '8.0' ) && Cpanel::Version::Compare::compare( $mysql_version, '<', '10.0' ) ) {
        disable_mysqlx($cnf_file);
    }

    if ( Cpanel::Version::Compare::compare( $mysql_version, '>=', '10.4' ) ) {
        disable_socket_auth($cnf_file);
    }

    return 1;
}

sub symlink_additional_conf_files {

    if ( my @conf_files = Cpanel::OS::db_additional_conf_files()->@* ) {

        my $mycnf = $Cpanel::MysqlUtils::MyCnf::Basic::_SYSTEM_MY_CNF;

        foreach my $file (@conf_files) {
            lstat $file;    # Must use lstat here otherwise symlinks will look like flat files.
            if ( -f _ ) {
                require Cpanel::FileUtils::Move;
                if ( Cpanel::OS::db_mariadb_default_conf_file() eq $file ) {
                    Cpanel::FileUtils::Move::safemv( '-f', $file, $mycnf );
                }
                else {
                    Cpanel::FileUtils::Move::safemv( $file, $file . '.' . time );
                }

                unlink $file;
                Cpanel::Autodie::symlink( $mycnf, $file );
            }
            elsif ( -l _ ) {
                my $link_target = Cpanel::Autodie::readlink($file);
                if ( $link_target ne $mycnf ) {
                    unlink $file;
                    Cpanel::Autodie::symlink( $mycnf, $file );
                }
            }
        }
    }

    return 1;
}

#
# NOTE: This function is heavily dependent upon the installed MySQL/MariaDB
# server binary for configuration file validation.  However, only later
# versions of the MySQL/MariaDB server binary have the --validate-config flag.
# This function is sometimes used to validate statements only available in
# later versions, while an earlier version is installed.  This will result
# in unintended false positives.
#
sub _check_for_config_errors {
    my ($cnf_file) = @_;

    my $binary = Cpanel::DbUtils::find_mysqld() or return;

    my $db = Cpanel::Database->new();

    require Cpanel::AccessIds;
    my $output = Cpanel::AccessIds::do_as_user(
        $db->user,
        sub {
            my $out = Cpanel::SafeRun::Errors::saferunonlyerrors( $binary, @{ $db->validate_config_options($cnf_file) } );
            if ($?) {
                return $out;
            }
            return;
        }
    );

    return $output;
}

=head2 _scrub_invalid_value($cnf_file)

=head3 Purpose

Comments out an invalid setting in the passed in configuration file.

=head3 Arguments

=over 3

=item C< $cnf_file >

STRING - The path to the mysql configuration file

=back

=head3 Returns

The invalid key found as a string if something was scrubbed, C<undef> if nothing was scrubbed.

=cut

sub _scrub_invalid_value {
    my ($cnf_file) = @_;

    my $check       = _check_for_config_errors($cnf_file);
    my $invalid_key = _parse_mysql_error_output($check);

    return unless $invalid_key;

    Cpanel::MysqlUtils::MyCnf::Modify::modify(
        sub {
            my ( $section, $key, $value ) = @_;

            # Any invalid directives we are interested in this phase
            # will be in the 'mysqld' section
            return ['COMMENT']
              if $section eq 'mysqld' && $key eq $invalid_key;

            return;
        },
        $cnf_file,
    );
    return $invalid_key;
}

=head2 scrub_invalid_values($cnf_file)

=head3 Purpose

Comments out multiple invalid settings in the passed in configuration file.

=head3 Arguments

=over 3

=item C< $cnf_file >

STRING - The path to the mysql configuration file

=back

=head3 Returns

An arrayref of invalid keys found if something was scrubbed, C<undef> if nothing was scrubbed.

=cut

sub scrub_invalid_values {
    my ($cnf_file) = @_;

    my $keys = [];

    # keep scrubbing until we no longer find any errors we can fix
    while ( my $invalid_key = _scrub_invalid_value($cnf_file) ) {
        push( @$keys, $invalid_key );
    }

    return @$keys ? $keys : undef;
}

=head2 _parse_mysql_error_output($error)

=head3 Purpose

Parse the invalid value/key from the error string.
MySQL will output errors for invalid values, like so:

    2019-10-09T19:39:02.021670Z 0 [ERROR] unknown variable 'dude=wheresmycar'
    2019-10-09T19:39:02.026826Z 0 [ERROR] Aborting

=head3 Arguments

=over 3

=item C< $error >

STRING - The error output

=back

=head3 Returns

The invalid key parsed from the error output.

=cut

sub _parse_mysql_error_output {
    my ($error) = @_;

    return unless length $error;

    my $key = undef;
    if ( $error =~ m/\[ERROR\].*unknown variable '([^=]+)=.*'/ ) {
        $key = $1;
    }
    elsif ( $error =~ m/\[ERROR\].*unknown option '--(.*)'/ ) {
        $key = $1;
    }

    return $key;
}

# if innodb_file_per_table is set we are in mysql 5.5
sub enable_innodb_file_per_table {
    my ($cnf_file) = @_;

    return update_configuration(
        $cnf_file,
        {
            'innodb_file_per_table' => 1,
        }
    );
}

sub disable_performance_schema {
    my ($cnf_file) = @_;

    return update_configuration(
        $cnf_file,
        {
            'performance-schema' => 0,
        }
    );
}

sub disable_mysqlx {
    my ($cnf_file) = @_;

    return update_configuration(
        $cnf_file,
        {
            'mysqlx' => 0,
        }
    );
}

sub disable_socket_auth {
    my ($cnf_file) = @_;

    return update_configuration(
        $cnf_file,
        Cpanel::OS::db_disable_auth_socket(),
    );
}

sub update_configuration {
    my ( $cnf_file, $items ) = @_;

    my $section = 'mysqld';
    my $my_cnf  = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf($cnf_file);
    my @keys    = keys %$items;

    # Don't set a value if there's already one in the file.
    foreach my $key (@keys) {
        delete $items->{$key} if exists $my_cnf->{$section}->{$key};
    }

    return Cpanel::MysqlUtils::MyCnf::update_mycnf(
        'user'    => 'root',
        'mycnf'   => $cnf_file,
        'section' => 'mysqld',
        'items'   => [$items],
    );
}

=head2 is_pidfile_valid($cnf_file)

=head3 Purpose

Determine if the 'pid-file' value is valid

=head3 Arguments

=over 3

=item C< $cnf_file >

STRING - The path to the mysql configuration file

=back

=head3 Returns

C<1> if 'pid-file' is valid. C<0> if 'pid-file' is invalid.

=cut

sub is_pidfile_valid {
    my $cnf_file = shift;

    my $mycnf_parsed       = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf($cnf_file);
    my $configured_pidfile = $mycnf_parsed->{'mysqld'}->{'pid-file'};

    # Do nothing if 'pid-file' isn't set
    return 1 if !defined $configured_pidfile;

    # Do nothing if the currently configured pid-file exists.
    # Since it already exists, it can obviously be created.
    return 1 if -f $configured_pidfile;

    require Cpanel::FileUtils::Path;
    my ( $dir, $file ) = Cpanel::FileUtils::Path::dir_and_file_from_path($configured_pidfile);

    # if the directory does not exist, then 'pid-file' can't be created
    return 0 if !-d $dir;

    return 1;
}

1;
