package Cpanel::Update::Crontab;

# cpanel - Cpanel/Update/Crontab.pm                Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Binaries          ();
use Cpanel::Services::Enabled ();
use Cpanel::Backup::Status    ();

=encoding utf-8

=head1 NAME

Cpanel::Update::Crontab - Utility functions for managing crontab entries

=cut

use constant _SERVICES_TO_CHECK => (
    'httpd',
    'mailman',
    'mysql',
    'postgresql',
);

my $hi = 999_999;
## note: the use of the literal "/scripts/upcp" (as opposed to the full /ulc/scripts/ucp)
##   is very DELIBERATE, and is a function of the moment of conversion to an 11.30 machine.
## case 36563 and 47736: preserve previous runtimes
sub _get_cron_updates {    ## no critic(Subroutines::ProhibitExcessComplexity) - refactor is a project not a bug fix
    my ( $crontab_lines, $httpupdate, $dnsonly ) = @_;

    my $legacy_cpbackup = Cpanel::Backup::Status::is_legacy_backup_enabled() ? 1 : 0;

    ## 2010-05-19: /scripts/mailman_chown_archives is looked for and filtered, but no longer added;
    ##   the intent is to remove the script from the crontab; all reference to mailman_chown_archives
    ##   can be removed a few releases after 11.25.1

    my ( %old_lines, %has );
    my $needs_update = 0;
    my @new_lines;

    my %SERVICE_PROVIDED;
    for my $service ( _SERVICES_TO_CHECK() ) {
        $SERVICE_PROVIDED{$service} = Cpanel::Services::Enabled::is_provided($service);
    }

    my $either_db_service = $SERVICE_PROVIDED{'mysql'} || $SERVICE_PROVIDED{'postgresql'};

    # Maintain sequence of cron lines from input to output. Tho cron doesn't care,
    # it's easier to visually match in to out, even run a diff if we feel like it.
    my $n_seq = 0;
    foreach my $line (@$crontab_lines) {
        ## case 55178 (and 8514): we no longer strip comments!
        ## note: preserving previous functionality; I do not know why we strip the next $httpupdate lines

        ++$n_seq;
        if ( defined $httpupdate && $line =~ m/$httpupdate/ ) {
            $has{'httpupdate'} = 1;
        }
        elsif ( $line =~ m!/scripts/upcp! ) {
            unless ( $line =~ m!/usr/local/cpanel/scripts/upcp --cron > /dev/null! ) {
                $needs_update = 1;
            }
            unless ( $line =~ m!fix-cpanel-perl! ) {
                $needs_update = 1;
            }
            $has{'upcp'} = 1;
            $old_lines{ $n_seq . 'upcp' } = $line;
        }
        elsif ( $line =~ m!/scripts/cpbackup! ) {
            unless ( $line =~ m!/usr/local/cpanel/scripts/cpbackup! ) {
                $needs_update = 1;
            }
            $has{'cpbackup'} = 1;
            $old_lines{ $n_seq . 'cpbackup' } = $line;
        }
        elsif ( $line =~ m!/usr/local/cpanel/bin/backup! ) {
            $has{'backup'} = 1;
            $old_lines{ $n_seq . 'backup' } = $line;
        }
        elsif ( $line =~ m!/usr/local/cpanel/bin/tail-check! ) {
            $has{'tail-check'} = 1;
            $old_lines{ $n_seq . 'tail-check' } = $line;
        }

        #remove old cruft
        elsif ( $line =~ m!/usr/local/cpanel/bin/tailwatchd-chk! ) {
            $has{'tail-check'} = 0;
        }
        elsif ( $line =~ m!/scripts/mailman_chown_archives! ) {
            $has{'mailman_chown_archives'} = 1;
        }
        elsif ( $line =~ m!/usr/local/cpanel/bin/mysqluserstore! ) {
            $has{'mysqluserstore'}                  = 1;
            $needs_update                           = 1 if $line =~ /^30 /;
            $old_lines{ $n_seq . 'mysqluserstore' } = $line;
        }
        elsif ( $line =~ m!/usr/local/cpanel/bin/dbindex! ) {
            $has{'dbindex'} = 1;
            $old_lines{ $n_seq . 'dbindex' } = $line;
        }
        elsif ( $line =~ m!/usr/local/cpanel/scripts/shrink_modsec_ip_database! ) {
            $has{'shrink_modsec_ip_database'} = 1;
            $old_lines{ $n_seq . 'shrink_modsec_ip_database' } = $line;
        }
        ## from former &setupmailmancachecrontab
        elsif ( $line =~ m!/usr/local/cpanel/scripts/eximstats_spam_check! ) {
            $has{'eximstats_spam_check'} = 1;
            $old_lines{ $n_seq . 'eximstats_spam_check' } = $line;
        }
        elsif ( $line =~ m!/scripts/update_mailman_cache! ) {
            unless ( $line =~ m!/usr/local/cpanel/scripts/update_mailman_cache! ) {
                $needs_update = 1;
            }
            $has{'update_mailman_cache'} = 1;
            $old_lines{ $n_seq . 'update_mailman_cache' } = $line;
        }
        ## from former &setupdbcachecrontab
        elsif ( $line =~ m!/scripts/update_db_cache! ) {
            unless ( $line =~ m!/usr/local/cpanel/scripts/update_db_cache! ) {
                $needs_update = 1;
            }
            $has{'update_db_cache'} = 1;
            $old_lines{ $n_seq . 'update_db_cache' } = $line;
        }
        elsif ( $line =~ m!/usr/local/cpanel/bin/optimizefs! ) {    # This script needs to be removed from cron
            $has{'optimizefs'} = 1;
        }
        elsif ( $line =~ m!/usr/local/cpanel/whostmgr/docroot/cgi/cpaddons_report.pl! ) {
            $has{'cpaddons'} = 1;
            $old_lines{ $n_seq . 'cpaddons' } = $line;
        }
        elsif ( $line =~ m!/scripts/exim_tidydb! ) {
            if ( $has{'eximtidydb'} ) {
                $needs_update = 1;    ## dupe bug, per case 50359
                next;
            }

            unless ( $line =~ m!/usr/local/cpanel/scripts/exim_tidydb! ) {
                $needs_update = 1;
            }
            $has{'eximtidydb'} = 1;
            $old_lines{ $n_seq . 'eximtidydb' } = $line;
        }

        ## from former &setupdcpumoncrontab
        elsif ( $line =~ m!/usr/local/cpanel/(bin/dcpumon|scripts/dcpumon-wrapper)! ) {
            $needs_update                    = 1 if $1 =~ /bin/;
            $has{'dcpumon'}                  = 1;
            $old_lines{ $n_seq . 'dcpumon' } = $line;
        }

        ## from former &setupnsipscrontab
        elsif ( $line =~ m!/scripts/updatenameserverips! ) {
            $has{'updatenameserverips'} = 1;
        }

        elsif ( $line =~ m!/scripts/autorepair\s+recoverymgmt\b! ) {
            if ( $has{'recoverymgmt'} ) {
                $needs_update = 1;    ## potential dupe bug, per case 50359
                next;
            }

            unless ( $line =~ m!/usr/local/cpanel/scripts/autorepair! ) {
                $needs_update = 1;
            }
            $has{'recoverymgmt'} = 1;
            $old_lines{ $n_seq . 'recoverymgmt' } = $line;
        }
        elsif ( $line =~ m!/scripts/clean_user_php_sessions! ) {
            $has{'clean_php_sessions'} = 1;
        }
        elsif ( $line =~ m!/bin/process_team_queue! ) {
            $has{'process_team_queue'} = 1;
        }
        elsif ( $line =~ m!/scripts/optimize_eximstats! ) {
            $has{'optimize_eximstats'} = 1;
            $old_lines{ $n_seq . 'optimize_eximstats' } = $line;
        }
        elsif ( $line =~ m!/scripts/send_api_notifications! ) {
            $has{'non_cpanel_use_of_deprecated_apis'}                  = 1;
            $old_lines{ $n_seq . 'non_cpanel_use_of_deprecated_apis' } = $line;
            $needs_update                                              = 1;
        }
        ## c47741: this facilitates the removal of several linear scans later
        else {
            push( @new_lines, [ $n_seq, $line ] );
        }
    }

    my $seq = get_sequencing( \%old_lines );
    ## note: the conditionals are deliberate; remove httpupdate and mailman_chown_archives
    ##   lines if they are there; and add upcp and friends if not there
    ## also, adjusts for lines that are absent but are needed for $dnsonly machines, or the reverse (present
    ## but not needed)

    my %SHOULD_BE = (

        # These are no longer supposed to be in the crontab.
        httpupdate                        => 0,
        mailman_chown_archives            => 0,
        updatenameserverips               => 0,
        optimizefs                        => 0,
        non_cpanel_use_of_deprecated_apis => 0,

        # These should always be in.
        upcp                 => 1,
        'tail-check'         => 1,
        eximtidydb           => 1,
        eximstats_spam_check => 1,
        optimize_eximstats   => 1,
        recoverymgmt         => 1,
        process_team_queue   => 1,

        # These should be in if and only if we are NOT dnsonly.
        dcpumon => !$dnsonly,
        backup  => !$dnsonly,

        # These should be in if and only if !dnsonly AND a DB service is on.
        mysqluserstore  => !$dnsonly && $either_db_service,
        dbindex         => !$dnsonly && $either_db_service,
        update_db_cache => !$dnsonly && $either_db_service,

        # These should be in if and only if !dnsonly AND Mailman is on.
        update_mailman_cache => !$dnsonly && $SERVICE_PROVIDED{'mailman'},

        # These should be in if and only if !dnsonly AND httpd is on.
        clean_php_sessions        => !$dnsonly && $SERVICE_PROVIDED{'httpd'},
        cpaddons                  => !$dnsonly && $SERVICE_PROVIDED{'httpd'},
        shrink_modsec_ip_database => !$dnsonly && $SERVICE_PROVIDED{'httpd'},

        # These are deprecated but not gone and should only remain in the crontab if enabled.
        cpbackup => $legacy_cpbackup,
    );

    $needs_update ||= grep { !!$SHOULD_BE{$_} ne !!$has{$_} } keys %SHOULD_BE;

    if ($needs_update) {

        ## CPANEL-32780: Legacy backups no longer should be in the crontab
        ## CPANEL-34619: ... only when legacy cpbackup is disabled
        if ( !$legacy_cpbackup && exists $old_lines{'cpbackup'} ) {
            delete $old_lines{'cpbackup'};
        }

        ## for case 46750: ensure upcp has '--cron' option
        if ( exists $old_lines{'upcp'} ) {
            if ( $old_lines{'upcp'} !~ m!fix-cpanel-perl.+/usr/local/cpanel/scripts/upcp --cron > /dev/null! ) {
                $old_lines{'upcp'} =~ s{^(\s*\S+\s+\S+\s+\S+\s+\S+\s+\S+)\s.+}{$1 (/usr/local/cpanel/scripts/fix-cpanel-perl; /usr/local/cpanel/scripts/upcp --cron > /dev/null)};
            }
        }

        if ( exists $old_lines{'dcpumon'} ) {
            if ( $old_lines{'dcpumon'} =~ m!/bin/dcpumon! ) {
                $old_lines{'dcpumon'} =~ s!/bin/dcpumon!/scripts/dcpumon-wrapper!;
            }
        }

        # CPANEL-23812 adjust time to avoid race with update_db_cache
        if ( exists $old_lines{'mysqluserstore'} ) {
            $old_lines{'mysqluserstore'} =~ s/^30 /25 /;
        }

        ## case 47736 review note: implementing these stages of crontab manipulation as closures
        ##   for readability and brevity (i.e. don't want to pass in \%old_lines and \@new_lines
        ##   with each invocation)

        ##############################
        ## ensure scripts serve from full /ulc/scripts
        my $_ensure_ulc = sub {
            my ($key) = @_;
            if ( exists $old_lines{$key} ) {
                unless ( $old_lines{$key} =~ m!/usr/local/cpanel/scripts/$key! ) {
                    $old_lines{$key} =~ s{\x20/scripts/$key}{\x20/usr/local/cpanel/scripts/$key}gx;
                }
            }
        };
        $_ensure_ulc->('upcp');
        $_ensure_ulc->('cpbackup');

        if ( $SERVICE_PROVIDED{'mailman'} ) {
            $_ensure_ulc->('update_mailman_cache');
        }

        if ($either_db_service) {
            $_ensure_ulc->('update_db_cache');
        }

        $_ensure_ulc->('eximtidydb');
        $_ensure_ulc->('recoverymgmt');
        ##############################

        ##############################
        ## run with /usr/bin/test, if desired and available
        my $test_bin = Cpanel::Binaries::path('test');
        if ( -x $test_bin ) {
            ## if "test" binary was found on the system, but not on the old line, redo the line
            my $_ensure_test = sub {
                my ($key) = @_;
                if ( exists $old_lines{$key} && $old_lines{$key} !~ m/$test_bin/ ) {
                    delete $old_lines{$key};
                }
            };

            $_ensure_test->('tail-check');

            if ( $SERVICE_PROVIDED{'mailman'} ) {
                $_ensure_test->('update_mailman_cache');
            }

            if ($either_db_service) {
                $_ensure_test->('update_db_cache');
            }
        }
        ##############################

        ##############################
        ## restore the old line, or create the appropriate default (possibly with /usr/bin/test)
        my $_restore_or_default = sub {
            my ( $key, $time, $cmd, $test_opt ) = @_;

            if ( exists $old_lines{$key} ) {

                # Make sure that reference to "/scripts" is changed to "/usr/local/cpanel/scripts"
                ## this is already handled via $_ensure_ulc coderef
                if ( $old_lines{$key} =~ m{\x20/scripts/}gx ) {
                    $old_lines{$key} =~ s{\x20/scripts/}{\x20/usr/local/cpanel/scripts/}gx;
                }

                push( @new_lines, [ $seq->{$key} || $hi, $old_lines{$key} ] );
            }
            else {
                if ( $test_opt && $test_bin ) {
                    push( @new_lines, [ $hi, "$time $test_bin -x $cmd && $cmd" ] );
                }
                else {
                    push( @new_lines, [ $hi, "$time $cmd" ] );
                }
            }
        };

        my ( $hour, $minute ) = get_random_hr_and_min();

        ## note: the optional 3rd boolean flag on some of the below means "desires /usr/bin/test clause"
        my ( $when, $pgm ) = get_upcp_cron_entry();
        $_restore_or_default->( 'upcp', $when, $pgm );

        if ($legacy_cpbackup) {
            ( $when, $pgm ) = get_cpbackup_cron_entry();
            $_restore_or_default->( 'cpbackup', $when, $pgm );
        }

        ( $when, $pgm ) = get_backup_cron_entry();
        $_restore_or_default->( 'backup', $when, $pgm );

        $_restore_or_default->( 'tail-check', '35 * * * *', '/usr/local/cpanel/bin/tail-check', 1 );

        ( $when, $pgm ) = get_exim_tidydb_cron_entry();
        $_restore_or_default->( 'eximtidydb', $when, $pgm );

        ( $when, $pgm ) = get_exim_stats_optimize_cron_entry();
        $_restore_or_default->( 'optimize_eximstats', $when, $pgm );

        if ( !$dnsonly ) {
            $_restore_or_default->( 'eximstats_spam_check', '5,20,35,50 * * * *', '/usr/local/cpanel/scripts/eximstats_spam_check 2>&1' );

            if ( $SERVICE_PROVIDED{'mailman'} ) {
                $_restore_or_default->( 'update_mailman_cache', '45 */4 * * *', '/usr/local/cpanel/scripts/update_mailman_cache', 1 );
            }

            # mysqluserstore used to generate  /var/cpanel/databases/users.db but we stopped
            # using it so its sole remaining function is to ensure we can connect to mysql
            # and reset the password if needed
            if ($either_db_service) {
                $_restore_or_default->( 'update_db_cache', '30 */4 * * *', '/usr/local/cpanel/scripts/update_db_cache', 1 );
                $_restore_or_default->( 'mysqluserstore',  '25 */2 * * *', '/usr/local/cpanel/bin/mysqluserstore >/dev/null 2>&1' );
                $_restore_or_default->( 'dbindex',         '15 */2 * * *', '/usr/local/cpanel/bin/dbindex >/dev/null 2>&1' );
            }

            $_restore_or_default->( 'recoverymgmt', '15 */6 * * *', '/usr/local/cpanel/scripts/autorepair recoverymgmt >/dev/null 2>&1' );
            $_restore_or_default->( 'dcpumon',      '*/5 * * * *',  '/usr/local/cpanel/scripts/dcpumon-wrapper >/dev/null 2>&1' );

            if ( $SERVICE_PROVIDED{'httpd'} ) {
                $_restore_or_default->( 'shrink_modsec_ip_database', '0 */2 * * *', '/usr/local/cpanel/scripts/shrink_modsec_ip_database -x 2>&1' );

                ( $when, $pgm ) = get_cpaddons_cron_entry();
                $_restore_or_default->( 'cpaddons', $when, $pgm );

                ( $when, $pgm ) = get_php_session_cleanup_cron_entry();
                $_restore_or_default->( 'php_session_cleanup', $when, $pgm );
            }
        }

        ( $when, $pgm ) = get_process_team_queue_entry();
        $_restore_or_default->( 'process_team_queue', $when, $pgm );

        ##############################

        @new_lines = sort { ( $a->[0] || 0 ) <=> ( $b->[0] || 0 ) } @new_lines;
        @new_lines = map  { $_->[1] } @new_lines;

        # Strip removed scripts from cron
        @new_lines = grep { !m{/usr/local/cpanel/bin/optimizefs} } @new_lines;

        return \@new_lines;
    }

    return;
}

sub get_sequencing {

    # Strip the numeric seq prefix from each key of the old_lines hash,
    # transfer the sequencing intelligence to a separate hash.

    my $old_lines = shift;

    my %seq;

    for my $k ( keys %$old_lines ) {
        my ( $seq_prefix, $newk ) = $k =~ / ^ (\d+) (.*) /x;
        $seq{$newk} = $seq_prefix || $hi;
        $old_lines->{$newk} = $old_lines->{$k};
        delete $old_lines->{$k};
    }

    return \%seq;
}

sub get_upcp_cron_entry {
    my $pgm = "(/usr/local/cpanel/scripts/fix-cpanel-perl; /usr/local/cpanel/scripts/upcp --cron > /dev/null)";
    my ( $hour, $minute ) = get_random_hr_and_min();
    my $when = "$minute $hour * * *";
    return wantarray ? ( $when, $pgm ) : "$when $pgm";
}

sub get_cpbackup_cron_entry {
    my $pgm  = "/usr/local/cpanel/scripts/cpbackup";
    my $when = '0 1 * * *';
    return wantarray ? ( $when, $pgm ) : "$when $pgm";
}

sub get_backup_cron_entry {
    my $pgm  = "/usr/local/cpanel/bin/backup";
    my $when = '0 2 * * *';
    return wantarray ? ( $when, $pgm ) : "$when $pgm";
}

sub get_cpaddons_cron_entry {
    my $pgm = "/usr/local/cpanel/whostmgr/docroot/cgi/cpaddons_report.pl --notify";
    my ( $hour, $minute ) = get_random_hr_and_min();
    my $when = "$minute $hour * * *";
    return wantarray ? ( $when, $pgm ) : "$when $pgm";
}

sub get_exim_tidydb_cron_entry {

    # note no randomization of time here; we maintain the historical precedent
    my $when = "0 6 * * *";
    my $pgm  = "/usr/local/cpanel/scripts/exim_tidydb > /dev/null 2>&1";
    return wantarray ? ( $when, $pgm ) : "$when $pgm";
}

sub get_exim_stats_optimize_cron_entry {

    # note no randomization of time here; we want stats on when this happens
    my $when = "30 5 * * *";
    my $pgm  = "/usr/local/cpanel/scripts/optimize_eximstats > /dev/null 2>&1";
    return wantarray ? ( $when, $pgm ) : "$when $pgm";
}

sub get_php_session_cleanup_cron_entry {
    my $when = "09,39 * * * *";
    my $pgm  = '/usr/local/cpanel/scripts/clean_user_php_sessions > /dev/null 2>&1';
    return wantarray ? ( $when, $pgm ) : "$when $pgm";    ## no critic qw(Wantarray)
}

sub get_process_team_queue_entry {
    my $when = "4 * * * *";
    my $pgm  = '/usr/local/cpanel/bin/process_team_queue > /dev/null 2>&1';
    return wantarray ? ( $when, $pgm ) : "$when $pgm";    ## no critic qw(Wantarray)
}

=head2 $minute = get_random_min()

Gets a random minute for usage in creating a crontab entry.

=over

=item Input

None.

=item Output

=over

Returns a scalar value representing an random minute value.

=back

=back

=cut

sub get_random_min {
    return int rand 60;
}

=head2 ( $hour, $minute ) = get_random_hr_and_min

Gets a random hour and minute for usage in creating a crontab entry.

This is legacy code much cleaned up. The intent evidently is to run two
thirds of the time run between midnite and 6am, and the other third of the
time between 8pm and midnite.

This results in values that are not necessarily truly random, but are weighted
towards running in the early morning or late night.

=over

=item Input

None.

=item Output

=over

Returns an hour and minute value as a list.

=back

=back

=cut

sub get_random_hr_and_min {

    my ( $hour, $minute );

    if ( int rand 3 ) {
        $hour = int rand 6;
    }
    else {
        my $before_midnite = int rand 4;
        $hour = $before_midnite ? ( 24 - $before_midnite ) : 0;
    }

    $minute = get_random_min();

    return ( $hour, $minute );
}

## case 48308
1;
