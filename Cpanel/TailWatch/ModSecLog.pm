package Cpanel::TailWatch::ModSecLog;

# cpanel - Cpanel/TailWatch/ModSecLog.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This module is based on modsecparse.pl from EasyApache and contains substantial
# amounts of code taken directly from modsecparse.pl.

# 2014-05-23: Do not add any 'use' lines to this file. Any module
# loads must be done via 'require' from inside init().

use strict;

use base 'Cpanel::TailWatch::Base';

our $VERSION = 0.1;

my $apacheconf;
my $INSERT_STATEMENT;

sub init {
    my ( $my_ns, $tailwatch_obj ) = @_;

    require Cpanel::ConfigFiles::Apache;
    require Cpanel::ModSecurity::DB;
    require Cpanel::TailWatch;
    require DBD::SQLite;
    require Fcntl;

    # Non-destructive setup of the database and table, in case they're not already set up.
    eval { Cpanel::ModSecurity::DB::initialize_database(); };
    if ($@) {
        $tailwatch_obj->info("Could not set up modsec database and/or hits table: $@");
    }

    $apacheconf = Cpanel::ConfigFiles::Apache->new();
    return;
}

sub is_enabled {
    my ( $my_ns, $tailwatch_obj ) = @_;

    require Cpanel::ModSecurity;    # needs to be loaded before init
    return if !Cpanel::ModSecurity::has_modsecurity_installed();

    return $my_ns->SUPER::is_enabled($tailwatch_obj);
}

sub internal_name { return 'modseclog' }

sub new {
    my ( $my_ns, $tailwatch_obj ) = @_;
    my $self = bless { 'internal_store' => {} }, $my_ns;

    my @log_files = _discover_log_files();

    # filelist can include file paths or coderefs that return lists of filepaths
    $tailwatch_obj->register_module( $self, __PACKAGE__, &Cpanel::TailWatch::PREVPNT, \@log_files );

    return $self;
}

sub process_line {
    my ( $self, $line, $tailwatch_obj, $log_file ) = @_;

    # We're no longer supporting ModSecurity 1, so only line_handler_2 is used.
    my $handler = \&line_handler_2;

    if ( ref $handler eq 'CODE' ) {
        my $request = $self->{request} ||= {};

        my $result;
        my ( $dbh, $sth );

        # - If there are 10 failures in a row, give up.
        # - If 30 seconds have elapsed since we gave up, give it another shot.
        #   - If that fails, keep the failure counter as it is and wait another 30 seconds.
        #   - If that succeeds, reset the failure counter and gave up at time.

        if ( $self->{gave_up_at} && time() - $self->{gave_up_at} < 30 ) {
            $tailwatch_obj->info("Not attempting another database connection until 30 seconds have elapsed since failure");
        }
        else {
            eval { ( $dbh, $sth ) = $self->_ensure_dbh_and_sth($tailwatch_obj); };
            if ($@) {
                if ( $self->{failures} ) {
                    $tailwatch_obj->info("Database connection failed again");    # abbreviated log message if the previous connect attempt was a failure too
                }
                else {
                    $tailwatch_obj->info("Database connection failed: $@");      # Don't make this fatal, because we can still log the SQL query
                }
                $self->{gave_up_at} = time if ++$self->{failures} >= 10;
            }
            else {
                delete @$self{qw(failures gave_up_at)};
            }
        }

        # Possible reasons for this failing include that $dbh was deliberately left undef above due to gave_up_at.
        $result = eval { $handler->( $tailwatch_obj, $line, $dbh, $sth, $request ); };
        if ($@) {
            $tailwatch_obj->info("insert failed: $@");
            delete @$self{qw(dbh sth request)};    # force reinit of dbh and sth in hope that will solve the problem. also trash any in-progress request data
        }

        return $result;
    }
    die "No line handler for '$log_file'!";
}

sub _ensure_dbh_and_sth {
    my ($self) = @_;

    if ( !$self->{dbh} || !$self->{sth} ) {    # TODO: || !ping(dbh)

        $self->{dbh} = $self->_get_dbh();

        $self->{statement} ||= INSERT_STATEMENT( $self->{dbh} );

        $self->{sth} = $self->{dbh}->prepare( $self->{statement} );
    }

    return @$self{qw(dbh sth)};
}

sub _discover_log_files {
    my @files;
    my @regular_logs = ( $apacheconf->dir_logs() . '/modsec_audit.log' );
    push @files, grep { -f } @regular_logs;
    return @files;
}

sub _generate_insert {
    my ( $dbh, $table, $columns, $values ) = @_;

    my @quoted_columns = map           { $dbh->quote_identifier($_) } @{$columns};
    my @quoted_values  = $values ? map { $dbh->quote($_) } @{$values} : ('?') x scalar( @{$columns} );

    if ( scalar(@quoted_columns) != scalar(@quoted_values) ) {
        die "Number of values does not match number of columns in INSERT statement.";
    }

    my $insert_part = 'INSERT INTO ' . $dbh->quote_identifier($table) . ' ( ' . join( ', ', @quoted_columns ) . ' )';
    my $values_part = 'VALUES ( ' . join( ', ', @quoted_values ) . ' )';

    my $statement = "$insert_part $values_part;";
    return $statement;
}

sub _insert_table {
    return 'hits';
}

sub _insert_columns {
    my @columns = qw{
      timestamp
      timezone
      ip
      http_version
      http_method
      http_status
      host
      path
      handler
      justification
      action_desc
      meta_file
      meta_line
      meta_offset
      meta_rev
      meta_msg
      meta_id
      meta_logdata
      meta_severity
      meta_uri
    };

    return \@columns;
}

sub INSERT_STATEMENT {
    my ($dbh) = @_;

    if ( !$INSERT_STATEMENT ) {
        $INSERT_STATEMENT = _generate_insert( $dbh, _insert_table(), _insert_columns() );
    }

    return $INSERT_STATEMENT;
}

# TODO: Create database and table if they don't already exist
sub _execute_or_log {
    my ( $tailwatch_obj, $dbh, $sth, $values ) = @_;

    eval {
        die "no database connection\n" if !$dbh;
        my $cached_sth = $dbh->prepare_cached( INSERT_STATEMENT($dbh) ) or die "prepare failed\n";
        $cached_sth->execute(@$values)                                  or die "execute failed\n";
    };
    if ( my $exception = $@ ) {
        my $db_obj    = bless {}, 'DBD::SQLite::db';    # Make a faux singleton using the class provided by DBD::SQLite
        my $statement = _generate_insert( $db_obj, _insert_table(), _insert_columns(), $values );
        _ensure_proper_log_permissions();
        $tailwatch_obj->log_sql($statement);
        my $exception_str = eval { $exception->isa('Cpanel::Exception') } ? $exception->get_string() : $exception;
        die "Couldn't execute insert ($exception_str); logged query to disk...\n";    # This must die in order for the caller to properly reestablish the dbh
    }
    else {
        return 1;
    }
    return;
}

sub _ensure_proper_log_permissions {
    if ( -f '/var/cpanel/sql/modseclog.sql' ) {
        my $perms = ( stat _ )[2] & 07777;
        if ( $perms != 0600 ) {
            chmod 0600, '/var/cpanel/sql/modseclog.sql';
        }
    }
    else {

        # Touch the file with 600 permissions so there is no window of time in which a file descriptor can
        # be opened using the more permissive default permissions used by tailwatchd.
        sysopen( my $fh, '/var/cpanel/sql/modseclog.sql', Fcntl::O_WRONLY() | Fcntl::O_CREAT() | Fcntl::O_EXCL(), 0600 );
        close $fh;
    }
    return;
}

sub line_handler_2 {
    my ( $tailwatch_obj, $line, $dbh, $sth, $request ) = @_;
    return if !$line;

    if (
        my ($lookup_path) =
        $line =~ m{
        \s
        / ([\w-]+ / [0-9]{8} / [0-9]{8}-[0-9]{4} / [0-9]{8}-[0-9]{6}-[a-zA-Z0-9@\-_]+) # path
        \s+
        \d+ # number
        \s+
        \d+ # number
        \s+
        \S+ # non-whitespace string
        \s*
        (?: \) \s* )? # trailing junk
        $ # Looking up with the pattern anchored to the righthand side is important so that we can be
          # assured that our match is not part of the farther-left request path, which could otherwise
          # provide bogus data.
    }x
    ) {
        open my $fh, '<', _full_lookup_path($lookup_path) or die "Couldn't open $lookup_path: $!";
        my %detail_request;
        while ( my $detail_line = <$fh> ) {
            line_handler_2( $tailwatch_obj, $detail_line, $dbh, $sth, \%detail_request );
        }
        close $fh;
    }

    # http://www.modsecurity.org/documentation/modsecurity-apache/2.1.0/modsecurity2-apache-reference.html#N10216
    # modsec2.user.conf.default:
    #    SecAuditLogParts "ABIFHZ"
    if ( $line =~ m{\A [-][-] (\w+) [-] A [-] [-] }xms ) {
        delete @{$request}{ keys %{$request} };    # clear it just in case
        $request->{'_token_id'} = $1;
        $request->{'_i_am_in'}  = 'A';

        return;
    }
    elsif ( defined( $request->{'_token_id'} ) && $line =~ m{--$request->{'_token_id'}-(\w)--} ) {
        $request->{'_i_am_in'} = $1;

        if ( $request->{'_i_am_in'} eq 'Z' ) {
            my ( $date_str, $time_str, $tz_offset, $ip ) = $request->{'_data'}{'A'} =~ m{ \[ ([^:]*) : (\S+) \s+ (\S+) \] \s+ \S+ \s+ (\S+) \s+ }xms;

            my ( $mday, $mon_name, $year ) = split /\//, $date_str;
            my $mon = _month_by_name($mon_name);
            my ( $h, $m, $s ) = split /:/, $time_str;
            my $tz_offset_mins = _tz_offset_to_mins($tz_offset);

            my $timestamp = sprintf( "%04d-%02d-%02d %02d:%02d:%02d", $year, $mon, $mday, $h, $m, $s );

            my ($res_num) = $request->{'_data'}{'F'} =~ m{ \A \S+ \s+ (\d+) \s+ }xms;
            my ( $method, $path, $http_vers ) = $request->{'_data'}{'B'} =~ m{ \A (\w+) \s+ (\S+) \s+ (\S+) }xms;

            my %headers;
            for my $l (qw( B F H )) {
                my @found = $request->{'_data'}{$l} =~ m{ ^ ([\w\-]+) : \s+ ([^\n\r]*) }xmsg;
                while ( my ( $name, $value ) = splice @found, 0, 2 ) {
                    push @{ $headers{$l}{$name} }, $value;
                }
            }

            # Strategy:
            #   - Begin by peeling off bracketed metadata from the right side piece by piece. (Problem: What if the metadata contains brackets?)
            #   - Once there isn't any more, split the remaining portion into:
            #     - A sentence containing no periods on the left.
            #     - A sentence which may contain periods on the right.

            my $messages = $headers{'H'}{'Message'};
            my @message_data;
            for my $i ( 0 .. $#$messages ) {

                # If the overall data in the Message section reaches 1024 bytes, it will be truncated in
                # a way that causes the syntax of the metadata fields to not necessarily remain valid
                # (could have an unclosed bracket). We need to try to salvage as much of the data as we
                # can in such a case.
                if ( length( $messages->[$i] ) == 1023 && $messages->[$i] !~ m{\]\s*$} ) {
                    $messages->[$i] =~ s{ \s* \[ (\w+) \s "((?:[^"]|\\")*) (?:" (?:\])?)? \s* $ }
                                        { [$1 "$2"]}x    # repair
                }

                while (
                    $messages->[$i] =~ s{ \s* \[  (\w+)  # metadata key
                                          \s "((?:[^"]|\\")*)" \]  # metadata value
                                          \s* $ }{}x
                ) {
                    $message_data[$i]{metadata}{$1} = $2;
                }

                @{ $message_data[$i] }{qw(action_desc justification)} = $messages->[$i] =~ m{ ^ (.*?\.) \s (.*\.) }xm;

            }

            # It's possible to have more than one 'Message' if more than one rule produced a hit
            # (including rules that don't actually reject the request), so we need to try to decide
            # which information is most relevant to this log event. Rejection messages are likely
            # going to be more interesting than random warnings produced by ModSecurity about things
            # like look-up tables being unreadable from disk. Even with this filtering, it's possible
            # for there to be more than one legitimate rule hit message, and if that's the case,
            # the deliberate design of this module is that each message's information should be
            # recorded as a separate table row, even though they were produced by a single hit
            # to the server.

            for my $i ( 0 .. $#message_data ) {
                my ( $metadata, $action_desc, $justification ) = @{ $message_data[$i] }{qw(metadata action_desc justification)};

                # Our criterion for judging whether this message is worthy of a record is whether it contained a rule id
                # (meaning that some sort of rule hit is what produced the message, which is not always the case).
                next if !defined $metadata->{id};

                eval {
                    _execute_or_log(
                        $tailwatch_obj,
                        $dbh, $sth,
                        [
                            # The name passed as the first argument to validate here should match the column
                            # name for which the value is being validated.
                            validate( 'timestamp',     $timestamp ),
                            validate( 'timezone',      $tz_offset_mins ),
                            validate( 'ip',            $ip ),
                            validate( 'http_version',  $http_vers ),
                            validate( 'http_method',   $method ),
                            validate( 'http_status',   $res_num ),
                            validate( 'host',          $headers{'B'}{'Host'}[0] ),
                            validate( 'path',          $path ),
                            validate( 'handler',       $headers{'H'}{'Apache-Handler'}[0] ),
                            validate( 'justification', $justification ),
                            validate( 'action_desc',   $action_desc ),
                            validate( 'meta_file',     $metadata->{file} ),
                            validate( 'meta_line',     $metadata->{line} ),
                            validate( 'meta_offset',   $metadata->{offset} ),
                            validate( 'meta_rev',      $metadata->{rev} ),
                            validate( 'meta_msg',      $metadata->{msg} ),
                            validate( 'meta_id',       $metadata->{id} ),
                            validate( 'meta_logdata',  $metadata->{logdata} || $metadata->{data} ),
                            validate( 'meta_severity', $metadata->{severity} ),
                            validate( 'meta_uri',      $metadata->{uri} ),
                        ]
                    );
                };
                my $err = $@;

                delete @{$request}{ keys %{$request} };    # clear it
                die $err if $err;
            }
        }

        return;
    }

    if ( $request->{'_i_am_in'} ) {
        return if $request->{'_i_am_in'} eq 'C' || $request->{'_i_am_in'} eq 'I';    # currently no need to use memory for request body
        $request->{'_data'}{ $request->{'_i_am_in'} } .= "$line\n";
    }
    return;
}

sub _full_lookup_path {
    my $lookup_path = shift;
    return $apacheconf->dir_logs() . '/modsec_audit/' . $lookup_path;
}

my $monthlist;

sub _month_by_name {
    my ($month_name) = @_;
    $monthlist ||= {
        'Jan' => 1, 'Feb' => 2, 'Mar' => 3, 'Apr' => 4,  'May' => 5,  'Jun' => 6,
        'Jul' => 7, 'Aug' => 8, 'Sep' => 9, 'Oct' => 10, 'Nov' => 11, 'Dec' => 12,
    };
    return $monthlist->{$month_name};
}

sub colon_sep_hh_mm_ss_plus_tzoffset {
    my ( $time, $tz_offset, $date_sr ) = @_;    # $time is 'hh:mm:ss'

    my $safe_tz_offset = $tz_offset =~ m{ \A .*? ( [-+]? \d+ ) \z .*?  }xms;    # yes the .*? are necessary
    return if !$safe_tz_offset;

    # TODO: (pseudo) $time += $safe_tz_offset; # case 1981
    if ( ref $date_sr eq 'SCALAR' && ${$date_sr} =~ m{ \A \d{4} [-] \d{2} [-] \d{2} \z }xms ) {

        # TODO: may need to +/- one day on the date as well if it goes into the prev or next day, case 1981
    }

    return $time;
}

sub _tz_offset_to_mins {
    my ($tz_offset) = @_;
    if ( my ( $direction, $hours, $minutes ) = $tz_offset =~ m{([\-\+])([0-9]{2})-?([0-9]{2})} ) {
        my $mins = $hours * 60 + $minutes;
        $mins *= -1 if $direction eq '-';
        return $mins;
    }
    die "Couldn't understand tz offset '$tz_offset'\n";
}

*validate = \&Cpanel::ModSecurity::DB::validate;
*_get_dbh = \&Cpanel::ModSecurity::DB::get_dbh;

# Our tailwatch driver is called 'modseclog', but the database is a SQLite file,
# so we need to tell tailwatchd about it, so that the 'alert' it issues has the proper info.
*get_database_name = \&Cpanel::ModSecurity::DB::DB_FILE;

1;
