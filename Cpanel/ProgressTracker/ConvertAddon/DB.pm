package Cpanel::ProgressTracker::ConvertAddon::DB;

# cpanel - Cpanel/ProgressTracker/ConvertAddon/DB.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use DBD::SQLite         ();
use Cpanel::Exception   ();
use Cpanel::LoadModule  ();
use Cpanel::DBI::SQLite ();

sub BASE_DIR { return '/var/cpanel/convert_addon_to_account'; }
sub DB_FILE  { return BASE_DIR() . '/conversions.sqlite'; }

sub new {
    my ( $class, $opts ) = @_;
    $opts = {} if !$opts || 'HASH' ne ref $opts;
    $opts->{'db'} = DB_FILE();

    my $self = bless {}, $class;
    $self->{'read_only'} = delete $opts->{'read_only'} || 0;
    if ( $self->{'read_only'} ) {
        $opts->{'sqlite_open_flags'} = DBD::SQLite::OPEN_READONLY();
    }

    _setup_base_dir() if !-d BASE_DIR();
    if ( !-e DB_FILE() ) {
        open my $fh, '>', DB_FILE() or die "Unable to create DB: $!\n";    #touch
        close $fh;
        chmod 0600, DB_FILE();
    }

    # Cpanel::DBI::SQLite sets RaiseError.
    # It throws Cpanel::Exceptions on failure.
    $self->{'dbh'} = Cpanel::DBI::SQLite->connect($opts);

    # If the DB hasn't been intialized yet - i.e., this is the first
    # instance the SQlite DB is used - then initialize it as part of
    # the object creation.
    $self->initialize_db() if !( -s DB_FILE() || $self->{'read_only'} );
    return $self;
}

sub list_jobs {
    my $self = shift;

    # If the DB hasn't be initialized yet, then just return an empty set.
    return [] if !-s DB_FILE();

    my $sth = $self->{'dbh'}->prepare(
        <<END_OF_SQL
    SELECT
        jobs.id AS "job_id",
        domain,
        source_acct,
        target_acct,
        start_time,
        end_time,
        status_codes.label AS "status"
    FROM jobs
    INNER JOIN status_codes ON status_codes.id = jobs.status_id
    ORDER BY job_id;
END_OF_SQL
    );
    $sth->execute();

    my $results = $sth->fetchall_arrayref( {} );
    return $results;
}

sub get_job_status {
    my ( $self, @job_ids ) = @_;

    return {} if !-s DB_FILE();

    my $job_ids_as_string = join( ',', ('?') x scalar @job_ids );

    my $sth = $self->{'dbh'}->prepare(
        <<"END_OF_SQL"
    SELECT
        jobs.id as 'job_id',
        status_codes.label as "job_status",
        end_time as "job_end_time",
        source_acct
    FROM jobs
    INNER JOIN status_codes ON jobs.status_id = status_codes.id
    WHERE jobs.id IN ($job_ids_as_string);
END_OF_SQL
    );
    $sth->execute(@job_ids);

    my $job_status = $sth->fetchall_hashref('job_id');

    return $job_status;
}

sub fetch_job_details {
    my ( $self, $job_id ) = @_;

    return {} if !-s DB_FILE();

    my $sth = $self->{'dbh'}->prepare(
        <<END_OF_SQL
    SELECT
        jobs.id as "job_id",
        domain,
        source_acct,
        target_acct,
        start_time as "job_start_time",
        end_time as "job_end_time",
        status_codes.label as "job_status"
    FROM jobs
    INNER JOIN status_codes ON jobs.status_id = status_codes.id
    WHERE jobs.id = ?;
END_OF_SQL
    );
    $sth->execute($job_id);
    my $job_details = $sth->fetchrow_hashref();

    return if !$job_details;

    $sth = $self->{'dbh'}->prepare(
        <<END_OF_SQL
    SELECT
        step_name,
        status_codes.label as "status",
        start_time,
        end_time,
        warnings
    FROM job_details
    INNER JOIN status_codes ON job_details.status_id = status_codes.id
    WHERE job_id = ?
    ORDER BY job_details.id;
END_OF_SQL
    );
    $sth->execute($job_id);
    $job_details->{'steps'} = $sth->fetchall_arrayref( {} );

    return $job_details;
}

sub start_job {
    my ( $self, $opts_hr ) = @_;
    die Cpanel::Exception->create('Invalid operation for read_only mode')    ## no extract maketext (developer error message. no need to translate)
      if $self->{'read_only'};

    $self->{'dbh'}->do(
        'INSERT INTO jobs (domain, source_acct, target_acct) VALUES (?, ?, ?)', {},
        $opts_hr->{'domain'},
        $opts_hr->{'source_acct'},
        $opts_hr->{'target_acct'},
    );

    # Return the 'id' of the job we just inserted.
    # https://metacpan.org/pod/DBD::SQLite#dbh-sqlite_last_insert_rowid
    return $self->{'dbh'}->last_insert_id( '', '', '', '' );
}

sub finish_job {
    my ( $self, $opts_hr ) = @_;
    die Cpanel::Exception->create('Invalid operation for read_only mode')    ## no extract maketext (developer error message. no need to translate)
      if $self->{'read_only'};

    $self->{'dbh'}->do(
        'UPDATE jobs SET status_id = 5, end_time = strftime("%s", "now") WHERE id = ?', {},
        $opts_hr->{'job_id'},
    );

    return 1;
}

sub fail_job {
    my ( $self, $opts_hr ) = @_;
    die Cpanel::Exception->create('Invalid operation for read_only mode')    ## no extract maketext (developer error message. no need to translate)
      if $self->{'read_only'};

    $self->{'dbh'}->do(
        'UPDATE jobs SET status_id = 4, end_time = strftime("%s", "now") WHERE id = ?', {},
        $opts_hr->{'job_id'},
    );

    return 1;
}

sub start_step_for_job {
    my ( $self, $opts_hr ) = @_;
    die Cpanel::Exception->create('Invalid operation for read_only mode')    ## no extract maketext (developer error message. no need to translate)
      if $self->{'read_only'};

    $self->{'dbh'}->do(
        'INSERT OR IGNORE INTO job_details (job_id, step_name) VALUES (?, ?)', {},
        $opts_hr->{'job_id'},
        $opts_hr->{'step_name'},
    );

    return 1;
}

sub finish_step_for_job {
    my ( $self, $opts_hr ) = @_;
    die Cpanel::Exception->create('Invalid operation for read_only mode')    ## no extract maketext (developer error message. no need to translate)
      if $self->{'read_only'};

    $self->{'dbh'}->do(

        # We can set the status_id with a subquery instead, but that is not going to be
        # performant with sqlite. Additionally, since foreign keys are not enforced strongly
        # we need to 'maintain' the relationships outside of sqlite by taking care with the
        # INSERT, UPDATE calls, and the table definitions.
        'UPDATE job_details SET status_id = 5, end_time = strftime("%s", "now") WHERE job_id = ? AND step_name = ?', {},
        $opts_hr->{'job_id'},
        $opts_hr->{'step_name'},
    );

    return 1;
}

sub fail_step_for_job {
    my ( $self, $opts_hr ) = @_;
    die Cpanel::Exception->create('Invalid operation for read_only mode')    ## no extract maketext (developer error message. no need to translate)
      if $self->{'read_only'};

    $self->{'dbh'}->do(

        # We can set the status_id with a subquery instead, but that is not going to be
        # performant with sqlite. Additionally, since foreign keys are not enforced strongly
        # we need to 'maintain' the relationships outside of sqlite by taking care with the
        # INSERT, UPDATE calls, and the table definitions.
        'UPDATE job_details SET status_id = 4, end_time = strftime("%s", "now") WHERE job_id = ? AND step_name = ?', {},
        $opts_hr->{'job_id'},
        $opts_hr->{'step_name'},
    );

    return 1;
}

sub set_step_warnings_for_job {
    my ( $self, $opts_hr ) = @_;
    die Cpanel::Exception->create('Invalid operation for read_only mode')    ## no extract maketext (developer error message. no need to translate)
      if $self->{'read_only'};

    $self->{'dbh'}->do(
        'UPDATE job_details SET warnings = ? WHERE job_id = ? AND step_name = ?', {},
        $opts_hr->{'warnings'},
        $opts_hr->{'job_id'},
        $opts_hr->{'step_name'},
    );

    return 1;
}

sub initialize_db {
    my ( $self, $force ) = @_;
    die Cpanel::Exception->create('Invalid operation for read_only mode')    ## no extract maketext (developer error message. no need to translate)
      if $self->{'read_only'};

    $self->_create_jobs_tbl($force);
    $self->_create_job_details_tbl($force);
    $self->_create_status_codes_tbl($force);

    return 1;
}

sub _create_jobs_tbl {
    my ( $self, $force ) = @_;

    $self->{'dbh'}->do('DROP TABLE IF EXISTS jobs;') if $force;

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS jobs (
    id INTEGER PRIMARY KEY,
    status_id INTEGER DEFAULT 1,
    domain VARCHAR(255) NOT NULL,
    source_acct VARCHAR(255) NOT NULL,
    target_acct VARCHAR(255) NOT NULL,
    start_time TIMESTAMP DEFAULT (strftime('%s', 'now')),
    end_time TIMESTAMP DEFAULT NULL,
    FOREIGN KEY(status_id) REFERENCES status_codes(id)
);
END_OF_SQL
    );

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE INDEX IF NOT EXISTS job_index ON jobs(id, domain);
END_OF_SQL
    );

    return 1;
}

sub _create_job_details_tbl {
    my ( $self, $force ) = @_;

    $self->{'dbh'}->do('DROP TABLE IF EXISTS job_details;') if $force;

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS job_details (
    id INTEGER PRIMARY KEY,
    job_id INTEGER,
    step_name TEXT NOT NULL,
    status_id INTEGER DEFAULT 1,
    start_time TIMESTAMP DEFAULT (strftime('%s', 'now')),
    end_time TIMESTAMP DEFAULT NULL,
    warnings TEXT DEFAULT NULL,
    FOREIGN KEY(status_id) REFERENCES status_codes(id),
    FOREIGN KEY(job_id) REFERENCES jobs(id),
    UNIQUE (job_id, step_name) ON CONFLICT REPLACE
);
END_OF_SQL
    );

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE INDEX IF NOT EXISTS job_details_index ON job_details(id, job_id, step_name);
END_OF_SQL
    );

    return 1;
}

sub _create_status_codes_tbl {
    my ( $self, $force ) = @_;

    $self->{'dbh'}->do('DROP TABLE IF EXISTS status_codes;') if $force;

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS status_codes (
    id INTEGER PRIMARY KEY,
    label VARCHAR(255),
    UNIQUE (label) ON CONFLICT REPLACE
);
END_OF_SQL
    );

    my $sth = $self->{'dbh'}->prepare('INSERT OR IGNORE INTO status_codes (label) VALUES (?)');
    foreach my $status (qw(INPROGRESS QUEUED SKIPPED FAILED DONE)) {
        $sth->execute($status);
    }
    return 1;
}

sub _setup_base_dir {
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
    Cpanel::SafeDir::MK::safemkdir( BASE_DIR(), 0700 )
      or die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ 'path' => BASE_DIR(), 'error' => $! ] );

    return 1;
}

1;
