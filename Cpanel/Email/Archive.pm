package Cpanel::Email::Archive;

# cpanel - Cpanel/Email/Archive.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Time::Local                 ();
use Cpanel::Time::HTTP          ();
use Cpanel::CachedDataStore     ();
use Cpanel::Email::DiskUsage    ();
use Cpanel::FileUtils::Write    ();
use Cpanel::SafeDir::MK         ();
use Cpanel::SafeDir::RM         ();
use Cpanel::Locale              ();
use Cpanel::Locale::Utils::User ();
use MIME::Base64                ();
use Cpanel::Errors::Accumulator ();
use Cpanel::Config::FlushConfig ();

our $dovecot_acl_contents = "owner rl";
our $VERSION              = 1.4;
our $VERBOSE              = 0;
my $SECS_IN_DAY = ( 60 * 60 * 24 );

my %MEMORIZED_ARCHIVE_GMTIME;
my $locale;

our $archive_disk_usage_regex = 'incoming|mailman|outgoing';

sub fetch_email_archive_types {
    $locale ||= Cpanel::Locale->get_handle();

    my $cpconf_ref;
    if (%Cpanel::CONF) {
        $cpconf_ref = \%Cpanel::CONF;
    }
    else {
        require Cpanel::Config::LoadCpConf;
        $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();
    }
    my $skipmailman = exists $cpconf_ref->{'skipmailman'} ? int( $cpconf_ref->{'skipmailman'} ) : 0;

    ## Key names must not contain _.
    ## Key names may only contain a-z
    my %types = (
        'incoming' => $locale->maketext('Incoming'),
        'outgoing' => $locale->maketext('Outgoing'),
    );
    ( $types{'mailman'} = $locale->maketext('Mailing Lists') ) unless $skipmailman;
    return \%types;
}

sub create_archive_maildirs {    ## no critic qw(Subroutines::ProhibitExcessComplexity ProhibitManyArgs) - its own project
    my ( $user, $homedir, $domain, $email_archive_types, $epoch_start, $epoch_end, $max_failures_before_abort ) = @_;
    my $time = time();
    $epoch_start ||= $time;
    $epoch_start = _normalize_epoch($epoch_start);

    $epoch_end ||= $time;
    $epoch_end = _normalize_epoch($epoch_end);

    my $days_since = _days_since( $epoch_start, $epoch_end );
    ( $days_since, $epoch_start ) = _get_safe_days_since( $days_since, $epoch_start );

    my $err_accumulator = Cpanel::Errors::Accumulator->new( 'fatal_regex' => qr/quota\s+exceeded/i, 'max_failures' => $max_failures_before_abort );

    my $dir;
    foreach my $archive_type ( keys %$email_archive_types ) {
        for my $num_days ( -1 .. $days_since + 2 ) {
            $dir = "$homedir/mail/archive/$domain/.$archive_type" . ( $num_days == -1 ? '' : '.' . YYYYMMDDGMT( $epoch_start + ( $SECS_IN_DAY * $num_days ) ) );
            if ( !-e $dir ) {
                if ( !mkdir( $dir, 0700 ) ) {
                    return ( -1, $err_accumulator->get_fatal_failure_reason(), $err_accumulator->get_failure_count(), $err_accumulator->get_failures() )
                      if $err_accumulator->accumulate_failure_is_fatal( 'mkdir', $dir );
                }
            }
            if ( !-e "$dir/dovecot-acl" ) {
                if ( !Cpanel::SafeDir::MK::safemkdir( $dir, '0700', 0 ) ) {
                    return ( -1, $err_accumulator->get_fatal_failure_reason(), $err_accumulator->get_failure_count(), $err_accumulator->get_failures() )
                      if $err_accumulator->accumulate_failure_is_fatal( 'safemkdir', $dir );
                }

                if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( "$dir/dovecot-acl", $dovecot_acl_contents, 0600 ) ) {
                    return ( -1, $err_accumulator->get_fatal_failure_reason(), $err_accumulator->get_failure_count(), $err_accumulator->get_failures() )
                      if $err_accumulator->accumulate_failure_is_fatal( 'writefile', "$dir/dovecol-acl" );
                }
            }
            if ( -e "$dir/maildirfolder" ) {    #This turned out to not scale well so we collect them nightly
                if ( !unlink("$dir/maildirfolder") ) {
                    return ( -1, $err_accumulator->get_fatal_failure_reason(), $err_accumulator->get_failure_count(), $err_accumulator->get_failures() )
                      if $err_accumulator->accumulate_failure_is_fatal( 'unlink', "$dir/maildirfolder" );
                }

            }
            if ( !-e "$dir/cur" ) {             # We only check the cur directory since we create them all at once.  This is an optimization to reduce stat()s
                foreach my $maildir ( 'cur', 'new', 'tmp' ) {
                    mkdir( $dir . '/' . $maildir, 0700 );
                }
            }

        }
    }

    my $archive_root_dir = "$homedir/mail/archive/$domain";

    if ( !-e "$archive_root_dir/dovecot-acl" ) {
        if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( "$archive_root_dir/dovecot-acl", $dovecot_acl_contents, 0600 ) ) {

            return ( -1, $err_accumulator->get_fatal_failure_reason(), $err_accumulator->get_failure_count(), $err_accumulator->get_failures() )
              if $err_accumulator->accumulate_failure_is_fatal( 'writefile', "$archive_root_dir/dovecot-acl" );

        }

    }
    if ( !-e "$archive_root_dir/cur" ) {    # We only check the cur directory since we create them all at once.  This is an optimization to reduce stat()s
        foreach my $maildir ( 'cur', 'new', 'tmp' ) {
            mkdir( "$archive_root_dir" . '/' . $maildir, 0700 );
        }
    }

    if ( opendir( my $cur_dh, "$archive_root_dir/cur" ) ) {
        my $filename;
        my %LOCALES_PRESENT;
        for ( 0 .. 256 ) {    # should not be more then 256 messages aka MAX_README_MESSAGES
            last if ( !( $filename = readdir($cur_dh) ) );
            if ( $filename =~ m/readme_message_([^_]+)_/ ) { $LOCALES_PRESENT{$1} = 1; }
        }
        closedir($cur_dh);

        create_archive_readme_mailmessage( "$archive_root_dir/cur", \%LOCALES_PRESENT, $domain );
    }
    $locale ||= Cpanel::Locale->get_handle();

    if ( my $failcount = $err_accumulator->get_failure_count() ) {
        return ( 0, $locale->maketext( "[quant,_1,failure,failures] while creating archive files.", $failcount ), $failcount, $err_accumulator->get_failures() );
    }

    return ( 1, $locale->maketext("Created archive files."), 0, [] );
}

sub purge_archives_outside_retention_period {
    my ( $user, $homedir, $domain, $retention_periods_ref ) = @_;

    ## making a copy so as not to mutate the passed reference
    my %retention_periods = %$retention_periods_ref;

    # if a retention_period's value is zero, it means unlimited; ensure that archive type does
    #   not go near the actual purge
    while ( my ( $key, $val ) = each %retention_periods ) {
        if ( $val == 0 ) {
            delete $retention_periods{$key};
        }
    }

    my $retention_regex_txt = '^\.(' . join( '|', keys %retention_periods ) . ')\.([0-9]{4})-([0-9]{2})-([0-9]{2})$';
    my $retention_regex     = qr/$retention_regex_txt/;

    my $now = _normalize_epoch( time() );

    my %max_keep_time;
    foreach my $archive_type ( keys %retention_periods ) {
        $max_keep_time{$archive_type} = ( $now - ( $SECS_IN_DAY * $retention_periods{$archive_type} ) );
    }

    if ( opendir( my $dh, "$homedir/mail/archive/$domain" ) ) {
        my ( $archive_type, $year, $month, $day );
        while ( my $dir = readdir($dh) ) {
            if ( ( $archive_type, $year, $month, $day ) = ( $dir =~ $retention_regex ) ) {
                if ( memorized_archive_time_to_gmtime( $year, $month, $day ) < $max_keep_time{$1} ) {
                    print "Purging expired archive $homedir/mail/archive/$domain/$dir\n" if $VERBOSE;
                    Cpanel::SafeDir::RM::safermdir("$homedir/mail/archive/$domain/$dir");
                }
            }
        }
        closedir($dh);
    }
    return;
}

sub memorized_archive_time_to_gmtime {

    #$_[0] YYYY , $_[1] MM, $_[2] DD
    return ( $MEMORIZED_ARCHIVE_GMTIME{"$_[0]-$_[1]-$_[2]"} ||= Time::Local::timegm_nocheck( 0, 0, 0, $_[2], $_[1] - 1, $_[0] ) );
}

sub recalculate_disk_usage {
    my ( $user, $homedir, $domain, $epoch_start, $epoch_end ) = @_;
    my $time = time();
    $epoch_start ||= $time;
    $epoch_start = _normalize_epoch($epoch_start);

    $epoch_end ||= $time;
    $epoch_end = _normalize_epoch($epoch_end);

    my $days_since = _days_since( $epoch_start, $epoch_end );
    ( $days_since, $epoch_start ) = _get_safe_days_since( $days_since, $epoch_start );

    my $retention_regex_txt = '^\.(' . $archive_disk_usage_regex . ')\.([0-9]{4})-([0-9]{2})-([0-9]{2})$';
    my $retention_regex     = qr/$retention_regex_txt/;
    my $now                 = _normalize_epoch( time() );

    my $max_check_time = ( $now - ( $SECS_IN_DAY * ( $days_since + 1 ) ) );    #we do not recalculate disk usage
                                                                               # for any folder older then this
    if ( opendir( my $dh, "$homedir/mail/archive/$domain" ) ) {
        my $disk_usage_db_file    = "$homedir/mail/archive/$domain/diskusage.db";
        my $disk_usage_total_file = "$homedir/mail/archive/$domain/diskusage_total";

        # No need to lock since only one can run at once
        my $diskusage_db_ref = Cpanel::CachedDataStore::load_ref( $disk_usage_db_file, undef, { 'enable_memory_cache' => '0' } );
        my $modified         = 0;
        my ( $diskused, $diskcount );
        my %SEEN;
        if ( !exists $diskusage_db_ref->{'usage'} || $diskusage_db_ref->{'VERSION'} != $VERSION ) {

            # For incompatible changes
            # $diskusage_db_ref={} if $diskusage_db_ref->{'VERSION'} < $VERSION;
            $max_check_time = 0;
            $modified       = 1;
        }

        my ( $root_diskused, $root_diskcount ) = Cpanel::Email::DiskUsage::recalculate_email_account_disk_usage( $homedir, "_archive", $domain, "$homedir/mail/archive/$domain/maildirsize", 0, "$homedir/mail/archive/$domain", { 'create_maildirfolder' => 0 } );
        if ( !defined $diskusage_db_ref->{'root_usage'} || $diskusage_db_ref->{'root_usage'} != $root_diskused ) {
            $diskusage_db_ref->{'root_usage'} = $root_diskused;
            $modified = 1;
        }

        my ( $archive_type, $month, $day, $year, $dirtime );
        while ( my $dir = readdir($dh) ) {
            if ( ( $archive_type, $year, $month, $day ) = ( $dir =~ $retention_regex ) ) {
                $SEEN{$archive_type}{"$year-$month-$day"} = undef;
                if (
                    ( $dirtime = memorized_archive_time_to_gmtime( $year, $month, $day ) ) < $now
                    && ( $dirtime >= $max_check_time
                        || !exists $diskusage_db_ref->{'usage'}->{$archive_type}->{"$year-$month-$day"} )
                ) {
                    ( $diskused, $diskcount ) = Cpanel::Email::DiskUsage::recalculate_email_account_disk_usage( $homedir, "_archive", $domain, "$homedir/mail/archive/$domain/$dir/maildirsize", 0, "$homedir/mail/archive/$domain/$dir", { 'create_maildirfolder' => 0 } );
                    if ( !defined $diskusage_db_ref->{'usage'}->{$archive_type}->{"$year-$month-$day"} || $diskusage_db_ref->{'usage'}->{$archive_type}->{"$year-$month-$day"} != $diskused ) {
                        $diskusage_db_ref->{'usage'}->{$archive_type}->{"$year-$month-$day"} = $diskused;
                        $modified = 1;
                    }
                }
            }

        }
        closedir($dh);
        foreach my $archive_type ( keys %{ $diskusage_db_ref->{'usage'} } ) {
            $modified = 1 if delete @{ $diskusage_db_ref->{'usage'}->{$archive_type} }{ grep { !exists $SEEN{$archive_type}{$_} } keys %{ $diskusage_db_ref->{'usage'}->{$archive_type} } };
        }
        if ($modified) {
            print "Writing $disk_usage_db_file as it has been updated\n" if $VERBOSE;
            my $disk_usage_total = $root_diskused;
            foreach my $archive_type ( keys %{ $diskusage_db_ref->{'usage'} } ) {

                # unpack %128d* calculates the 128bit checksum by summing numeric values of expanded values -- see perldoc -f unpack
                $disk_usage_total += $diskusage_db_ref->{'totals'}->{$archive_type} = unpack "%128d*", pack( "d*", values %{ $diskusage_db_ref->{'usage'}->{$archive_type} } );    #http://www.perlmonks.org/?node_id=17352
            }
            $diskusage_db_ref->{'total'}   = $disk_usage_total;
            $diskusage_db_ref->{'VERSION'} = $VERSION;
            Cpanel::CachedDataStore::store_ref( $disk_usage_db_file, $diskusage_db_ref, { 'enable_memory_cache' => '0' } );
            Cpanel::FileUtils::Write::overwrite_no_exceptions( $disk_usage_total_file, $disk_usage_total, 0644 );
        }
    }

    return;
}

sub create_archive_readme_mailmessage {
    my ( $target_maildir_cur_folder, $existing_locales, $domain ) = @_;

    my $email_archive_types = fetch_email_archive_types();

    my %MESSAGE_LOCALES;
    $MESSAGE_LOCALES{'en'}                                                          = 1;
    $MESSAGE_LOCALES{ Cpanel::Locale::Utils::User::get_user_locale($Cpanel::user) } = 1;
    $MESSAGE_LOCALES{ Cpanel::Locale->get_handle()->get_language_tag() }            = 1;

    my $final_status = 1;

    foreach my $locale ( keys %MESSAGE_LOCALES ) {
        next if ( $existing_locales->{$locale} );
        my $readme_mail_message      = get_readme_mailmessage( $email_archive_types, $locale, $domain );
        my $readme_mail_message_size = length $readme_mail_message;

        my $status = Cpanel::FileUtils::Write::overwrite_no_exceptions( "$target_maildir_cur_folder/readme_message_${locale}_,S=" . $readme_mail_message_size, $readme_mail_message, 0600 );
        $final_status = 0 if !$status;
    }
    return $final_status;
}

sub get_readme_mailmessage {
    my ( $email_archive_types, $locale, $domain ) = @_;
    my $locale_handle = Cpanel::Locale->get_handle($locale);
    my $msg           = 'MIME-Version: 1.0' . "\n" . 'Content-type: text/plain; charset=UTF-8' . "\n";
    $msg .= 'To: "' . $locale_handle->maketext('Email Archive') . '"' . " <_archive\@$domain>\n";
    $msg .= 'From: "' . $locale_handle->maketext('Archive Administrator') . '" ' . "<_archive\@$domain>\n";
    $msg .= 'Date: ' . Cpanel::Time::HTTP::time2http( time() ) . "\n";
    if ( $locale_handle->tag_is_default_locale() ) {
        $msg .= 'Subject: ' . $locale_handle->maketext('Archived Email ([get_locale_name] Version)') . "\n";
    }
    else {
        my $encoded_subject = MIME::Base64::encode_base64( $locale_handle->maketext('Archived Email ([get_locale_name] Version)') );
        $encoded_subject =~ s/\n//g;
        $msg .= 'Subject: =?UTF-8?B?' . $encoded_subject . "=?=\n";
    }
    $msg .= 'X-Locale: "' . $locale . '"' . "\n\n";
    $msg .= $locale_handle->maketext("You are now using the [output,class,Email Archiving,title] feature.") . "\n\n";
    $msg .= $locale_handle->maketext("You can find your archives in the following subfolders of your [output,class,INBOX,code]:") . "\n\n";
    foreach my $archive_type ( keys %{$email_archive_types} ) {
        $msg .= "\t\t$archive_type:\t$email_archive_types->{$archive_type}\n";
    }
    $msg .= "\nSome mail clients (Roundcube and others) require you to subscribe to each folder you wish to view, please follow the instructions at https://go.cpanel.net/webmailarchive in order to setup subscriptions for the folders.\n";
    return $msg;
}

sub YYYYMMDDGMT {
    my ( $sec, $min, $hour, $mday, $mon, $year ) = gmtime( $_[0] || time() );
    return sprintf( '%04d-%02d-%02d', $year + 1900, $mon + 1, $mday );
}

sub apply_archiving_default_configuration {
    my ( $domain, $user, $homeDir ) = @_;

    # Doing this for Cpanel::ParkAdmin called from WHM to park domains
    $user    ||= $Cpanel::user;
    $homeDir ||= $Cpanel::homedir;

    my $defaultConfig = _get_archiving_default_configuration($homeDir);
    if ( !$defaultConfig || !( keys %{$defaultConfig} ) ) {
        return;
    }

    my $email_archive_types = fetch_email_archive_types();

    # this method needs to avoid the ownership domain check because $Cpanel::DOMAINS does
    # not get updated by the time it's called after subdomain or parked domain creation.

    my @RETURN;
    _set_archiving_configuration( $domain, $email_archive_types, $defaultConfig, \@RETURN, $user, $homeDir );
    return \@RETURN;
}

sub _get_archiving_default_configuration {
    my ($homeDir) = @_;

    my $configFilePath = get_archiving_default_config_file_path($homeDir);

    if ( -e $configFilePath ) {
        return Cpanel::CachedDataStore::load_ref($configFilePath);
    }

    return;
}

sub get_archiving_default_config_file_path {
    my ($homeDir) = @_;

    # Doing this for Cpanel::ParkAdmin called from WHM to park domains
    $homeDir ||= $Cpanel::homedir;

    return "$homeDir/.cpanel/email_archiving_defaults.yaml";
}

## normalize to 4 A.M., so that there are not problems on days of DST change when
##   incrementing by 60 * 60 * 24 seconds
sub _normalize_epoch {
    my ($epoch) = @_;
    my @lt = gmtime($epoch);
    @lt[ 0, 1, 2 ] = ( 0, 0, 4 );
    return Time::Local::timegm_nocheck(@lt);
}

## note: assumes two epochs have been "normalized" (per _normalize_epoch)
sub _days_since {
    my ( $epoch_start, $epoch_end ) = @_;
    my $days_since = int( ( $epoch_end - $epoch_start ) / $SECS_IN_DAY );
    return $days_since;
}

sub _get_safe_days_since {
    my ( $days_since, $epoch_start ) = @_;
    ## safeguard against bad "last run" values
    if ( $days_since < 0 || $days_since > 100 ) {
        $days_since  = 3;
        $epoch_start = _normalize_epoch( time() );
    }
    return ( $days_since, $epoch_start );
}

sub _set_archiving_configuration {
    my ( $domain, $email_archive_types, $OPTS, $RETURN, $user, $homeDir ) = @_;

    # Doing this for Cpanel::ParkAdmin called from WHM to park domains
    $user    ||= $Cpanel::user;
    $homeDir ||= $Cpanel::homedir;

    Cpanel::SafeDir::MK::safemkdir( "$homeDir/etc/$domain/archive", '0755' ) if !-e "$homeDir/etc/$domain/archive";

    my %create_email_archive_types;

    foreach my $direction ( keys %{$email_archive_types} ) {
        if ( exists $OPTS->{$direction} ) {
            if ( !length $OPTS->{$direction} ) {
                unlink "$homeDir/etc/$domain/archive/$direction";
                push @{$RETURN}, { 'direction' => $direction, 'domain' => $domain, 'retention_period' => -1, 'enabled' => 0, 'status' => 1 };
            }
            else {
                $locale ||= Cpanel::Locale->get_handle();
                if ( Cpanel::Config::FlushConfig::flushConfig( "$homeDir/etc/$domain/archive/$direction", { 'retention_period' => int $OPTS->{$direction} }, ': ' ) ) {
                    $create_email_archive_types{$direction} = $email_archive_types->{$direction};
                    push @{$RETURN}, { 'direction' => $direction, 'domain' => $domain, 'retention_period' => int $OPTS->{$direction}, 'enabled' => 1, 'status' => 1, 'statusmsg' => $locale->maketext( 'Updated archive configuration for “[_1]”.', $domain ) };
                }
                else {
                    push @{$RETURN}, { 'direction' => $direction, 'domain' => $domain, 'retention_period' => int $OPTS->{$direction}, 'enabled' => 1, 'status' => 0, 'statusmsg' => $locale->maketext( 'Write failure: “[_1]”: [_2]', "~/etc/$domain/archive/$direction", $! ) };
                }
            }
        }
    }
    if (%create_email_archive_types) {
        create_archive_maildirs( $Cpanel::user, $Cpanel::homedir, $domain, \%create_email_archive_types );
    }
    return $RETURN;
}

1;
