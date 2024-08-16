package Cpanel::Backup::Transport::History;

# cpanel - Cpanel/Backup/Transport/History.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#XXX the serializer returns BLANK data unless we do this song & dance
use Cpanel::LoggerAdapter ();
use Cpanel::TaskQueue::Loader();

our $logfile;
our $logger;

BEGIN {
    $logfile = "/usr/local/cpanel/logs/cpbackup_transport_history.log";
    $logger  = Cpanel::LoggerAdapter->new( { alternate_logfile => $logfile } );
    Cpanel::TaskQueue::Loader::load_taskqueue_modules($logger);
    require Cpanel::TaskQueue::PluginManager;
}

my ($caller) = caller();
my $in_transporter = $caller eq '/usr/local/cpanel/Cpanel/Backup/Queue.pm';
$in_transporter ||= $caller eq 'Cpanel::Backup::Queue::transport_backup';
Cpanel::TaskQueue::PluginManager::load_plugin_by_name('Cpanel::Backup::Queue') unless $in_transporter;

use Try::Tiny;
use Cpanel::Backup::Transport::DB ();
use Cpanel::PIDFile               ();
use Cpanel::PsParser              ();
use Cpanel::TaskQueue             ();
use Cpanel::JSON                  ();
use Cpanel::Backup::Transport     ();
use Cpanel::Time::ISO             ();

our $vacuum_pid_file = '/var/cpanel/vacuum_transport_history.pid';

# Note to future people:  I am not batching SELECTs, but instead slurping with selectall_arrayref.
# Given the number of backups retained is rarely over 365,
# Given the number of users is rarely over 20k on a cpanel box
# Given the number of transports is rarely over 10-20, but even if users could have their own transports this would *still* be small
# We likely will only end up recieving ~30 million records in get_all in the absolute worst case scenario.  As such this has been paginated.
# All other gets of the sub-tables will only recieve their thousands of rows, which is unlikely to be a memory issue.

=head1 CONSTRUCTOR

=head2 new

Ensure the Transport History database has proper schema and so forth after securing a connection.

=cut

sub new {
    my ($class) = @_;
    my $self = {
        dbh => Cpanel::Backup::Transport::DB->dbconnect(),
    };
    $self->{dbh}->do("PRAGMA foreign_keys = ON");
    $self->{chunk_size} = 333;
    return bless( $self, $class );
}

=head1 METHODS

=head2 record($transport,$date,$user)

Records in the database that the provided user has been transported via the provided transport on the provided date.

When this is called, the clock starts ticking on 'how long' this transport is going to take to finish.
The caller must next call finish() for the relevant values when the transport completes its actions.

=cut

sub record {
    my ( $self, $transport, $date, $user ) = @_;

    #TODO validate input/output

    #First, ensure the entry in transports exists, and create it if not
    my $insert = "INSERT OR IGNORE INTO transports (transport) VALUES (?)";
    $self->{dbh}->prepare($insert)->execute($transport);

    #Next, Insert an entry in users recording the relevant user if they are not already present.
    my $insert1 = "INSERT OR IGNORE INTO users (user) VALUES (?)";
    $self->{dbh}->prepare($insert1)->execute($user);

    #Next, Insert an entry in occurrences recording the date if not already present.
    my $insert2 = "INSERT OR IGNORE INTO occurrences (date) VALUES (?)";
    $self->{dbh}->prepare($insert2)->execute($date);

    #Finally, record an entry into transport_history.
    my $insert3 = "
        INSERT OR IGNORE INTO
            transport_history (
                user_id,
                occurrence_id,
                transport_id
            )
        SELECT
            user_id,
            occurrence_id,
            transport_id
        FROM
            transport_import
        WHERE
            transport=? AND
            date=? AND
            user=?";
    my $smt = $self->{dbh}->prepare($insert3) or die "Could not prepare statement!";
    $smt->execute( $transport, $date, $user );

    return 1;
}

=head2 finish($transport,$date,$user)

Mark a particular transport operation as having completed by recording the current timestamp.

=cut

sub finish {
    my ( $self, $transport, $date, $user ) = @_;

    my $insert = qq{
        UPDATE
            transport_history
        SET
            end_timestamp=CURRENT_TIMESTAMP
        WHERE
            transport_id IN ( SELECT id FROM transports WHERE transport=?) AND
            occurrence_id IN ( SELECT id FROM occurrences WHERE date=?) AND
            user_id IN ( SELECT id FROM users WHERE user=?)
    };

    my $smt = $self->{dbh}->prepare($insert) or die "Could not prepare statement!";
    $smt->execute( $transport, $date, $user );

    return 1;
}

=head2 get(%options)

Return all relevant backup transport history.

Paginate this call, Filter, and order it like so:

    sort_order   => 'DESC',
    sort_key     => 'user',
    search_field => 'transport',
    search_term  => 'transport_abc123',
    unique_field => 'date',
    limit        => 0,
    offset       => 0,
    elapsed      => 1, #Return things like when the transport started/finished
    count        => 0, #Set high to return the total rows from your query as second param

Search term is an equivelance check, not a LIKE or REGEXP.

unique_field will return only the unique instances of said field.

=cut

sub get {
    my ( $self, %options ) = @_;

    my @valid_fields = qw{user transport date end_timestamp start_timestamp};
    die "sort_order must be DESC or ASC"                                               unless !$options{sort_order}   || grep { $options{sort_order} eq $_ } qw{ASC DESC};
    die "sort_key must be user, transport, date, start_timestamp or end_timestamp"     unless !$options{sort_key}     || grep { $options{sort_key} eq $_ } @valid_fields;
    die "search_field must be user, transport, date, start_timestamp or end_timestamp" unless !$options{search_field} || grep { $options{search_field} eq $_ } @valid_fields;
    die "unique_field must be user, transport, date, start_timestamp or end_timestamp" unless !$options{unique_field} || grep { $options{unique_field} eq $_ } @valid_fields;

    die "sort_key must be passed if sort_order is"        if $options{sort_order}   && !$options{sort_key};
    die "search_term must be provided if search_field is" if $options{search_field} && !$options{search_term};
    die "limit must be passed if offset is"               if $options{offset}       && !$options{limit};

    my @bind_values;
    my $query = "SELECT user,transport,date FROM happenings ";
    $query = "SELECT * FROM happenings " if $options{elapsed};
    my $countquery = "SELECT count(*) AS count FROM happenings ";

    if ( $options{unique_field} ) {
        $query      = "SELECT DISTINCT $options{unique_field} FROM happenings ";
        $countquery = "SELECT count(DISTINCT $options{unique_field}) AS count FROM happenings ";
    }

    if ( $options{search_field} && $options{search_term} ) {
        if ( $options{search_term} eq 'NULL' ) {
            $query      .= "WHERE $options{search_field} IS NULL  ";
            $countquery .= "WHERE $options{search_field} IS NULL ";
        }
        elsif ( $options{search_term} eq 'NOT NULL' ) {
            $query      .= "WHERE $options{search_field} IS NOT NULL  ";
            $countquery .= "WHERE $options{search_field} IS NOT NULL ";
        }
        else {
            $query      .= "WHERE $options{search_field}=?  ";
            $countquery .= "WHERE $options{search_field}=? ";
            push( @bind_values, $options{search_term} );
        }
    }

    if ( $options{sort_key} ) {
        $query .= "ORDER BY $options{sort_key} ";
        $query .= "$options{sort_order} " if $options{sort_order};
    }

    if ( $options{limit} ) {
        $query .= "LIMIT ? ";
        push( @bind_values, $options{limit} );
        if ( $options{offset} ) {
            $query .= "OFFSET ? ";
            push( @bind_values, $options{offset} );
        }
    }

    my $count;
    if ( $options{count} ) {
        $count = $self->{dbh}->selectrow_hashref($countquery);
        $count = $count->{count} if ref $count eq 'HASH';
    }

    my $ret = $self->{dbh}->selectall_arrayref( $query, { Slice => {} }, @bind_values );
    return $ret unless $options{count};
    return wantarray ? ( $ret, $count ) : $ret;
}

=head2 get_grouped_uniques($field,$subfield, %options)

Similar to get(), but groups by the provided field and returns a hash with a unique list of the values for the provided subkey.

Example:

    print Dumper $history->get_grouped_uniques('user','date');
    $VAR1 = {
        billy => ['2012-03-04','2012-03-05'],
        joe   => ['2013-04-12','2022-07-19'],
    }

Options supported:

    limit
    offset
    search_field
    search_term

See the documentation for get() as to the meaning of those options.

=cut

sub get_grouped_uniques {
    my ( $self, $field, $subfield, %options ) = @_;
    die "field and subfield must be provided"            unless $field && $subfield;
    die "field must be 'user', 'transport' or 'date'"    unless grep { $field eq $_ } qw{user transport date};
    die "subfield must be 'user', 'transport' or 'date'" unless grep { $subfield eq $_ } qw{user transport date};

    die "sort_order must be DESC or ASC"                     unless !$options{sort_order}   || grep { $options{sort_order} eq $_ } qw{ASC DESC};
    die "sort_key must be 'user', 'transport' or 'date'"     unless !$options{sort_key}     || grep { $options{sort_key} eq $_ } qw{user transport date};
    die "search_field must be 'user', 'transport' or 'date'" unless !$options{search_field} || grep { $options{search_field} eq $_ } qw{user transport date};
    die "search_term must be provided if search_field is" if $options{search_field} && !$options{search_term};
    die "limit must be passed if offset is"               if $options{offset}       && !$options{limit};

    #XXX Here's hoping ',' is not an allowed username or transport name (using the default , separator allows me to use DISTINCT here)
    my $query = "SELECT $field, GROUP_CONCAT( DISTINCT $subfield ) AS $subfield FROM happenings GROUP BY $field ";

    my @bind_values;
    if ( $options{search_field} && $options{search_term} ) {
        $query .= "WHERE $options{search_field}=? ";
        push( @bind_values, $options{search_term} );
    }

    if ( $options{limit} ) {
        $query .= "LIMIT ? ";
        push( @bind_values, $options{limit} );
        if ( $options{offset} ) {
            $query .= "OFFSET ? ";
            push( @bind_values, $options{offset} );
        }
    }

    my $result = $self->{dbh}->selectall_arrayref( $query, { Slice => {} }, @bind_values );
    return map { $_->{$field} => [ split( /,/, $_->{$subfield} ) ] } @$result;
}

=head2 prune_by_date($date)

Remove all entries from the history database older or equal to the provided date.

Use this when enforcing backup retention dates.

=cut

sub prune_by_date {
    my ( $self, $date ) = @_;

    #This is ON DELETE CASCADE, so all should be well
    return $self->{dbh}->do( "DELETE from occurrences WHERE date <= ?", undef, $date );
}

=head2 prune_by_user($user)

Remove all entries from the history database referring to the provided user.

Use this when terminating users.

=cut

sub prune_by_user {
    my ( $self, $user ) = @_;

    #This is ON DELETE CASCADE, so all should be well
    return $self->{dbh}->do( "DELETE from users WHERE user=?", undef, $user );
}

=head2 prune_by_transport($transport)

Remove all entries from the history database referring to the provided transport.

Use this when deleting backup transports.

=cut

sub prune_by_transport {
    my ( $self, $transport ) = @_;

    #This is ON DELETE CASCADE, so all should be well
    return $self->{dbh}->do( "DELETE from transports WHERE transport=?", undef, $transport );
}

=head2 is_vacuum_running()

Find out if the transport history DB is being vacuumed

=over 3

B<Returns>: Returns true if vacuum is running; false if not.

=back

=cut

#Lifted from Cpanel::Backup::Metadata
sub is_vacuum_running {

    my $result = 0;

    try {
        my $pid = Cpanel::PIDFile->get_pid($vacuum_pid_file);

        if ($pid) {

            # Process is running
            if ( kill( 0, $pid ) > 0 ) {

                require Cpanel::PsParser;
                my $pid_info = Cpanel::PsParser::get_pid_info($pid);

                if ($pid_info) {

                    if ( ( $pid_info->{'command'} =~ /vacuum/ ) && ( $pid_info->{'state'} ne 'Z' ) ) {
                        $result = 1;
                    }
                }
            }

            # If the pidfile somehow exists & vacuum isn't running
            # Then it is invalid and will block vacuum from ever running
            # in the future.  It needs to be removed
            if ( !$result ) {
                unlink $vacuum_pid_file;
            }
        }
    };

    return $result;
}

=head2 vacuum($logger)

Remove unused space and defragment the database.

Returns 1 on success, 0 in the event it is blocked, undef on failure.

=over 3

=item C<< $logger >>

For logging of any vacuum related issues

=back

=cut

#Again, another direct lift, this probably should be put into AutoRebuildSchemaBase frankly
sub vacuum {
    my ( $self, $logger ) = @_;

    # We can't run vacuum if we are vacuuming
    # Plus, is_vacuum_running will remove an invalid pidfile
    # which would block Cpanel::PIDFile->do() from ever being able to run
    if ( is_vacuum_running() ) {

        $logger->warn("A vacuum operation is already being performed on the transport history database");
        return 0;
    }

    my $rc = 1;

    # Surround this operation with a pid file so we can test if it is running
    Cpanel::PIDFile->do(
        $vacuum_pid_file,
        sub {
            $logger->info("Vacuum of transport history has begun");

            try {
                $self->{dbh}->do("VACUUM;");
            }
            catch {
                $logger->warn("Error vacuuming transport history: $_");
                $rc = undef;
            };

            $logger->info("Vacuum of transport history is complete");
        }
    );

    return $rc;
}

=head2 get_elapsed_statistics()

Get the mean, maximum, minimum, first started datetime and last ended datetime

=cut

sub get_elapsed_statistics {
    my ($self) = @_;
    return $self->{dbh}->selectrow_hashref("SELECT * FROM elapsed_statistics");
}

=head2 get_transport_status(@get_args)

Wrap get()  to also return whether the transport is pending, complete or failed

Transports which never finish(), and that are not in the transport queue are considered 'failed'.

Does not support the unique_field, sort_key, or sort_order arguments, and elapsed is forced high.

Also accepts a 'name' arg which will be translated unless a transport_id is provided as well (terminates in that case).

=cut

sub get_transport_status {
    my ( $self, %args ) = @_;

    die "sort_order and sort_key are NOT supported by this method." if $args{sort_order} || $args{sort_key};
    die "Invalid state argument passed: $args{state}"               if $args{state} && !grep { $_ eq $args{state} } qw{pending running failed completed};
    die "unique_field argument not supported by get_transport_status" unless !$args{unique_field};
    die "transport and name arguments are mutually exclusive" if $args{name} && $args{transport};

    $args{queue_name} ||= 'backups';
    $args{queue_dir}  ||= '/var/cpanel/backups/queue';

    #translate transport 'name' into 'id'
    my $transports = Cpanel::Backup::Transport->new();
    if ( $args{name} ) {
        my @possible = grep { $_->{name} eq $args{name} } values( %{ $transports->{destinations} } );
        my $name     = shift @possible;
        die "$args{name} Does not correspond to any existing backup transport." unless $name;
        $args{search_field} = 'transport';
        $args{search_term}  = $name->{id};
    }

    #Consult the list of destinations so we can build the list of 'pending' stuff
    my $dest_hash  = $transports->{destinations};
    my @transports = keys(%$dest_hash);

    #Consult queue first to prevent race such that we think things are failed which simply just droppped off the q
    my $queue = Cpanel::TaskQueue->new(
        {
            name      => $args{queue_name},
            logger    => $logger,
            queue_dir => $args{queue_dir},
            state_dir => $args{queue_dir},
            cache_dir => $args{queue_dir},
        }
    );

    my $state_snapshot = $queue->has_work_to_do() ? $queue->snapshot_task_lists() : { waiting => [] };

    #Force this on to see end_timestamp
    $args{elapsed} = 1;
    $state_snapshot->{deferred}   //= [];
    $state_snapshot->{processing} //= [];
    my @to_do = ( @{ $state_snapshot->{waiting} }, @{ $state_snapshot->{deferred} }, @{ $state_snapshot->{processing} } );

    @to_do = map {
        my $joined_args = join( ' ', @{ $_->{'_args'} } );
        Cpanel::JSON::Load($joined_args);
    } @to_do;

    #Adjust what we ask for based on requested state
    if ( $args{state} ) {
        if ( grep { $args{state} eq $_ } qw{failed running} ) {
            $args{search_term}  = 'NULL';
            $args{search_field} = 'end_timestamp';
        }
        if ( $args{state} eq 'completed' ) {
            $args{search_term}  = 'NOT NULL';
            $args{search_field} = 'end_timestamp';
        }
    }

    #Get the goods IF we care about anything other than 'queued'
    my $history = [];
    $args{count} = 1;
    my $count = 0;
    ( $history, $count ) = $self->get(%args) if !$args{state} || $args{state} ne 'pending';
    $count += scalar(@to_do) * scalar(@transports);

    #Add in 'synthetic' history entries for items waiting in the q
    foreach my $transport ( sort @transports ) {
        push(
            @$history,
            sort { $a->{user} cmp $b->{user} }
              map {
                {
                    transport => $transport,
                    user      => $_->{user},
                    date      => substr( Cpanel::Time::ISO::unix2iso( $_->{'time'} ), 0, 10 ),
                }
              } grep { $_->{user} } @to_do
        );
    }

    #Truncate list based on our limit/offset
    if ( $args{limit} && ( scalar(@$history) > $args{limit} ) ) {
        my $overage = ( scalar(@$history) - $args{limit} );
        foreach ( 1 .. $overage ) {
            pop @$history;
        }
    }

    @$history = _translate_statuses( $history, @to_do );

    #Do a final correction for the special case of 'running' status
    @$history = grep { $_->{status} eq $args{state} } @$history if $args{state};

    #Map IDs to transport names
    @$history = map {
        my $t = $transports->get( $_->{transport} );
        $_->{transport} = $t->{name} if $t->{name};
        $_
    } @$history;

    my $pages = 0;
    $pages = $count / ( $args{limit} || $count ) if $count;
    return ( $history, $pages );
}

sub _translate_statuses {
    my ( $history, @to_do ) = @_;
    return map {
        my $subject = $_;
        $subject->{status} = 'pending';
        if ( $subject->{start_timestamp} ) {
            my $time = substr( $subject->{date}, 0, 10 );
            $subject->{status} = 'failed';
            if ( $time eq $subject->{date} ) {
                $subject->{status} = 'running' if grep { $subject->{user} eq $_->{user} } @to_do;
            }
            $subject->{status} = 'completed' if $subject->{end_timestamp};
        }
        $subject;
    } @$history;
}

1;
