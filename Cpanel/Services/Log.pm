package Cpanel::Services::Log;

# cpanel - Cpanel/Services/Log.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

# No use statements for ChkServd.pm compat
# No Cpanel::Exceptions for ChkServd.pm compat

use Cpanel::RestartSrv::Systemd ();
use Cpanel::Validate::Service   ();    # this use statement is ok for ChkServd.pm
use Cpanel::OS                  ();

# because it does not use in anything else

our $LOG_READ_BYTES   = 8192;                            #failures should be in the last
                                                         # 8192 bytes
our $LOG_DIR          = '/var/log';
our $STARTUP_LOG_DIR  = '/var/run/restartsrv/startup';
our $MAX_LOG_MESSAGES = 5;

sub _os_logs_to_check {
    require Cpanel::OS;
    Cpanel::OS::maillog_path() =~ m{/([^/]+)};
    return $1 || die("Unable to parse Cpanel::OS::maillog_path");
}

sub logs_to_check {
    state @logs_to_check = qw/ secure messages/, _os_logs_to_check();
    return @logs_to_check;
}

sub _systemctl_status {
    my $service = shift;
    return undef unless defined $service;
    open( my $systemctl_fh, '-|', '/usr/bin/systemctl', 'status', $service ) or do {
        return undef;
    };
    return $systemctl_fh;
}

sub fetch_service_startup_log {
    my ( $service, $service_via_systemd ) = @_;

    if ( !Cpanel::Validate::Service::is_valid($service) ) {
        return ( 0, "“$service” is not a valid service name." );
    }

    my $startup_log_fh;

    if ( Cpanel::OS::is_systemd() && ( $service_via_systemd ||= Cpanel::RestartSrv::Systemd::has_service_via_systemd($service) ) ) {
        $startup_log_fh = _systemctl_status($service);
        return ( 0, "Could not read log: $!" ) if !defined $startup_log_fh;

        # "eat" all the info lines #
        while (<$startup_log_fh>) {
            last if m/^\s*$/;
        }
    }
    else {

        # lookup legacy service name for the requested service #
        my $service_name = get_service_name_from_legacy_name($service);

        my $log_path = "$STARTUP_LOG_DIR/$service_name";
        return ( 0, 'No startup log' ) if !-s $log_path;
        open( $startup_log_fh, '<', $log_path ) or do {
            return ( 0, "The system failed to open $log_path for reading because of an error: $!" );
        };
    }

    if ($startup_log_fh) {
        my $startup_log = do { local $/; readline($startup_log_fh) // '' };
        if ($!) {
            return ( 0, "The system failed to fetch the startup_log file for “$service” because of an error: $!" );
        }
        close($startup_log_fh);

        _decruft_log_for_service( $service, \$startup_log );

        return ( 1, $startup_log );
    }
    else {
        return ( 0, 'No startup log found.' );
    }
}

sub fetch_service_log_messages {
    my ( $services_to_match, $command ) = @_;

    my @log_names = split( m/[\|\&]+/, $services_to_match );
    my %log_map   = map { $_ => { 'max_messages' => $MAX_LOG_MESSAGES, 'read_bytes' => $LOG_READ_BYTES } } logs_to_check();

    if ( $services_to_match =~ m{ftp} ) {
        @log_names = qw(pure-ftpd pureftpd proftpd);
    }
    elsif ( $services_to_match =~ m{syslogd} && $command ) {
        @log_names = ($command);
    }
    elsif ( $services_to_match =~ m{exim}i ) {

        # Cpanel::Exim is too heavy to load here
        $log_map{'exim_mainlog'} = { 'max_messages' => 64, 'read_bytes' => $LOG_READ_BYTES };
    }
    elsif ( $services_to_match =~ m{cpanel_php_fpm}i ) {
        $log_map{'/usr/local/cpanel/logs/php-fpm/error.log'} = { 'max_messages' => 64, 'read_bytes' => $LOG_READ_BYTES };
    }
    elsif ( $services_to_match =~ m{httpd}i ) {

        #  Cpanel::Logs::Find is too heavy to load here
        require Cpanel::ConfigFiles::Apache;

        my $apacheconf = Cpanel::ConfigFiles::Apache->new();
        $log_map{ $apacheconf->file_error_log() } = { 'max_messages' => 4096, 'read_bytes' => 32768 };
        @log_names = qw(httpd apache);
    }
    elsif ( $services_to_match =~ m{mysql}i ) {
        require Cpanel::MysqlUtils::Logs;    # heavy, but no choice
        my $error_log_file = Cpanel::MysqlUtils::Logs::get_mysql_error_log_file();
        $log_map{$error_log_file} = { 'max_messages' => 128, 'read_bytes' => $LOG_READ_BYTES };
        @log_names = qw(mysqld);
    }

    foreach my $service (@log_names) {
        if ( !Cpanel::Validate::Service::is_valid($service) ) {
            return ( 0, "“$service” is not a valid service name." );
        }
    }

    my $log_messages   = '';
    my $log_regex_text = join( '|', map { quotemeta($_) } @log_names );

    if ($log_regex_text) {
        my @errors;

        my $log_regex = qr{(?:
                [\s\/]+(?:$log_regex_text)[\[:] # Syslog line style - Aug 11 15:27:04 sin pure-ftpd:  ....

                |

                ^[0-9-]+\s[0-9:]+\s$log_regex_text # Exim log line style - 2014-08-10 04:02:05 exim 4.82 daemon started: pid=15173, ...

                |

                \s+(?:$log_regex_text)\/ # Apache log line style - [Mon Aug 11 15:25:05 2014] [notice] Apache/2.2.25 mo...
            )}ix;
        my $read_ok = 0;

      LOG_FILE:
        foreach my $file ( keys %log_map ) {
            local $!;
            $log_map{$file}->{'path'} = $file =~ m{^/} ? $file : "$LOG_DIR/$file";

            my ( $read_log, $error_ref ) = _read_log( \$log_messages, 'file' => $file, %{ $log_map{$file} }, 'log_regex' => $log_regex );
            $read_ok += $read_log;
            push @errors, @{$error_ref};
        }

        if ( !$read_ok ) {
            return ( 0, "The system could not provide log messages for “$services_to_match” because it failed to read all of the potential log files with the following errors: " . join( ', ', map { "Error while attempting to $_->{'op'} “$_->{'path'}”: “$_->{'error'}”" } @errors ) );
        }

    }

    return ( 1, $log_messages );
}

sub _read_log {
    my ( $log_messages_ref, %opts ) = @_;

    my $log_file_path = $opts{'path'};
    my $file          = $opts{'file'}         || $log_file_path;
    my $read_bytes    = $opts{'read_bytes'}   || $LOG_READ_BYTES;
    my $max_messages  = $opts{'max_messages'} || $MAX_LOG_MESSAGES;
    my $log_regex     = $opts{'log_regex'}    || qr/./;
    my $read_ok       = 0;
    my @errors;

    if ( open( my $log_fh, '<', $log_file_path ) ) {

        my $size    = ( stat($log_fh) )[7];
        my $seekpnt = ( $size - $read_bytes );

        if ( $seekpnt > 0 ) {
            seek( $log_fh, $seekpnt, 0 ) || do {
                push @errors, { 'op' => 'seek', 'file' => $file, 'path' => $log_file_path, 'error' => scalar $! };
                return ( 0, \@errors );
            };
        }
        my $msgs;
        read( $log_fh, $msgs, $read_bytes ) || do {
            if ($!) {
                push @errors, { 'op' => 'read', 'file' => $file, 'path' => $log_file_path, 'error' => scalar $! };
            }
            else {
                push @errors, { 'op' => 'read', 'file' => $file, 'path' => $log_file_path, 'error' => "Empty File" };
            }
            return ( 0, \@errors );
        };
        my @msgs = split( /\n/, $msgs );

        if ( length $msgs == $read_bytes ) {
            shift @msgs if $seekpnt > 0;    #If we read the maximum number of
                                            # bytes, we want to discard the first line
                                            # as it may be a partial line and we already have
                                            # read back enough lines that its likely
                                            # not going to be useful anyways.
        }

        $read_ok++;

        splice( @msgs, 0, scalar @msgs - $max_messages ) if scalar @msgs > $max_messages;    # remove everything but the last $max_messages mesages as they are probably not relevant

        my $new_messages = join( "\n", grep { $_ =~ $log_regex } reverse @msgs );
        if ($new_messages) {
            $$log_messages_ref .= length $$log_messages_ref ? "\n$new_messages" : $new_messages;    #present the newest first (we want them to see t: Fatal: Time just moved backwards by 10811 seconds. first)
        }
    }
    else {
        push @errors, { 'op' => 'open', 'file' => $file, 'path' => $log_file_path, 'error' => scalar $! };
    }

    return ( $read_ok, \@errors );
}

# This is to handle legacy chkservd.d files
# from pre 11.30 machines (yes they still exist in 2014)
sub get_service_name_from_legacy_name {
    my ($service) = @_;

    if    ( $service =~ m{ftp}i )    { return 'ftpserver'; }
    elsif ( $service =~ m{exim}i )   { return 'exim'; }
    elsif ( $service eq 'chkservd' ) { return 'tailwatchd'; }

    # Cpanel::ServiceManager::Services need to have the service name normalized #
    return 'dovecot' if ( $service eq 'imap' || $service eq 'pop' );

    return $service;
}

sub _decruft_log_for_service {
    my ( $service, $startup_log_ref ) = @_;

    if ( $service eq 'httpd' && length $$startup_log_ref > $LOG_READ_BYTES ) {
        substr( $$startup_log_ref, 0, 0, "\n" );    # Insert a \n at the beginning of the string without rebuidling it

        $$startup_log_ref =~ s/\n[ \t]*Warning:[^\n]+//sg;          # Remove warnings as they can be megabytes
        $$startup_log_ref =~ s/\n\S+[ \t]*Warning:[^\n]+//sg;       # Remove warnings like AH00112: Warning: DocumentRoot [/dev/null] does not exist
        $$startup_log_ref =~ s/\n\[[^\]]+\] \[warn\] [^\n]+//sg;    # and they obsurce the useful errors.

        $$startup_log_ref =~ s/^\n//s;                              # Remove extra new line
    }

    return;
}

sub fetch_log_tail {
    my ( $logfile, $max_messages ) = @_;

    my $log_messages = '';
    my ( $read_log, $error_ref ) = _read_log( \$log_messages, 'path' => $logfile, 'max_messages' => $max_messages );

    if ( !$read_log ) {
        return ( 0, "The system could not provide log messages for “$logfile” because it failed to read all of the potential log files with the following errors: " . join( ', ', map { "Error while attempting to $_->{'op'} “$_->{'path'}”: “$_->{'error'}”" } @{$error_ref} ) );
    }

    return ( 1, $log_messages );
}

1
