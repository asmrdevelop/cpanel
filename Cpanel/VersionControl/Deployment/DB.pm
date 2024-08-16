package Cpanel::VersionControl::Deployment::DB;

# cpanel - Cpanel/VersionControl/Deployment/DB.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::VersionControl::Deployment::DB

=head1 SYNOPSIS

    use Cpanel::VersionControl::Deployment::DB ();

    my $db = Cpanel::VersionControl::Deployment::DB->new();

    my $id = $db->queue(
       '0000/1234',
       '/home/user/repositories/my_repo',
       '/home/user/.cpanel/logs/vc_1234567890_git_deploy.log'
    );

        ...

    $db->activate($id);

        ...

    $db->stamp( $id, 'succeeded' );

    my $deploy_obj = $db->retrieve($id);

    my $objs_arrref = $db->retrieve();

    $db->remove($id);

=head1 DESCRIPTION

Cpanel::VersionControl::Deployment::DB is a wrapper around a SQLite
database file, which holds data on all deployments.

=cut

use strict;
use warnings;

use Cpanel::DBI::SQLite ();
use Cpanel::PwCache     ();
use Time::HiRes         ();

=head1 VARIABLES

=head2 $DB_FILENAME

The relative path of the SQLite file within the user's home directory.
Default value is '.cpanel/datastore/vc_deploy.sqlite'.

=cut

our $DB_FILENAME = '.cpanel/datastore/vc_deploy.sqlite';

=head1 CLASS FUNCTIONS

=head2 Cpanel::VersionControl::Deployment::DB-E<gt>new()

Create a new DB object.

=cut

sub new {
    my ( $class, $args ) = @_;

    my $self = bless( {}, $class );

    $self->_init_db();

    return $self;
}

=head1 METHODS

=head2 $db-E<gt>queue()

Inserts a new record for a deployment and adds a 'queued' timestamp for it.

=head3 Arguments

=over 4

=item $task_id

The C<Cpanel::UserTasks> queue ID of the deployment.

=item $repository_root

Full path to the root of the repository to be deployed.

=item $log_file

Full path to the log file for this deployment.

=back

=cut

sub queue {
    my ( $self, $task_id, $repo_root, $log_file ) = @_;

    my $deploy_id = $self->_add_deployment( $task_id, $repo_root, $log_file );

    return $self->_get_deployment($deploy_id);
}

=head2 $db-E<gt>activate()

Activate a deployment record in the database.  This includes inserting
the repository state, and adding an 'active' timestamp for the
deployment.

=head3 Arguments

=over 4

=item $deployment_id

The ID value of the deployment we wish to activate.

=item $version_control

A C<Cpanel::VersionControl> object, which should provide the
C<last_update> and C<branch> methods.

=back

=cut

sub activate {
    my ( $self, $deploy_id, $vc ) = @_;

    $self->_add_deploy_state( $deploy_id, $self->_prepare_deploy_state($vc) );

    return $self->stamp( $deploy_id, 'active' );
}

=head2 $db-E<gt>stamp()

Adds a timestamp for a deployment.

=head3 Arguments

=over 4

=item $deployment_id

The ID value of the deployment we wish to update.

=item $status

The status we wish to use for this timestamp.

=back

Invalid status values will be ignored, as will statuses which already
have an entry.

=cut

sub stamp {
    my ( $self, $deploy_id, $status ) = @_;

    $self->_add_timestamp( $deploy_id, $status );

    return $self->_get_deployment($deploy_id);
}

=head2 $db-E<gt>retrieve()

Retrieve deployments from the database.

=head3 Arguments

=over 4

=item $deployment_id

Optional argument, to limit result to a single deployment.

=back

=cut

sub retrieve {
    my ( $self, $deploy_id ) = @_;

    return $self->_get_deployment($deploy_id)
      if $deploy_id;

    return $self->_get_all_deployments();
}

=head2 $db-E<gt>remove()

Remove a deployment from the database.

=head3 Arguments

=over 4

=item $deployment_id

Deployment ID to remove.

=back

=cut

sub remove {
    my ( $self, $deploy_id ) = @_;

    return unless $deploy_id;

    $self->_remove_timestamps($deploy_id);
    $self->_remove_deployment_state($deploy_id);
    $self->_clean_deployments();
    $self->_clean_repository_states();
    $self->_clean_authors();
    $self->_clean_branches();
    $self->_clean_repositories();

    return;
}

=head1 PRIVATE METHODS

=head2 $db-E<gt>_init_db()

Returns a database handle.  If no database exists, one will be created
and the schema will be inserted.

=cut

sub _init_db {
    my ($self) = @_;

    my $fname = _db_filename();

    $self->{'dbh'} = Cpanel::DBI::SQLite->connect(
        {
            'database'   => $fname,
            'RaiseError' => 1
        }
    );
    $self->{'dbh'}->do('PRAGMA foreign_keys = ON');

    if ( !-s $fname ) {
        chmod 0600, $fname;
        $self->_add_schema();
    }
    $self->_get_statuses();

    return;
}

=head2 $db-E<gt>_get_statuses()

Gets the set of valid statuses from the database and inserts them into
the object.

=cut

sub _get_statuses {
    my ($self) = @_;

    $self->{'statuses'} = { map { $_->[0] => $_->[1] } $self->{'dbh'}->selectall_array('SELECT status, status_id FROM statuses;') };
    return;
}

=head2 $db-E<gt>_get_repository()

Return the ID for a given repository record.  Will insert the record if
necessary.

=head3 Arguments

=over 4

=item $repository_root

The root directory of the given repository.

=back

=cut

sub _get_repository {
    my ( $self, $repo_root ) = @_;

    my $sth = $self->{'dbh'}->prepare(
        qq{
            INSERT OR IGNORE INTO repositories (repository_root)
            VALUES (?);
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute($repo_root);
    $sth = $self->{'dbh'}->prepare(
        qq{
            SELECT repository_id FROM repositories
            WHERE repository_root = ?;
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute($repo_root);
    my $result = $sth->fetchall_arrayref;

    return $result->[0][0];
}

=head2 $db-E<gt>_clean_repositories()

Remove unreferenced repositories from the database.

=cut

sub _clean_repositories {
    my ($self) = @_;

    $self->{'dbh'}->do(
        qq{
            DELETE FROM repositories WHERE repository_id NOT IN
            (SELECT DISTINCT repository_id FROM deployments);
        }
    );

    return;
}

=head2 $db-E<gt>_get_author()

Return the ID for a given author record.  Will insert the record if
necessary.

=head3 Arguments

=over 4

=item $author

Name/email string for the author.

=back

=cut

sub _get_author {
    my ( $self, $author ) = @_;

    my $sth = $self->{'dbh'}->prepare(
        qq{
            INSERT OR IGNORE INTO authors (author)
            VALUES (?);
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute($author);
    $sth = $self->{'dbh'}->prepare(
        qq{
            SELECT author_id FROM authors
            WHERE author = ?;
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute($author);
    my $result = $sth->fetchall_arrayref;

    return $result->[0][0];
}

=head2 $db-E<gt>_clean_authors()

Remove unreferenced authors from the database.

=cut

sub _clean_authors {
    my ($self) = @_;

    $self->{'dbh'}->do(
        qq{
            DELETE FROM authors WHERE author_id NOT IN
            (SELECT DISTINCT author_id FROM repository_states);
        }
    );

    return;
}

=head2 $db-E<gt>_get_branch()

Return the ID for a given branch record.  Will insert the record if
necessary.

=cut

sub _get_branch {
    my ( $self, $branch ) = @_;

    my $sth = $self->{'dbh'}->prepare(
        qq{
            INSERT OR IGNORE INTO branches (branch)
            VALUES (?);
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute($branch);
    $sth = $self->{'dbh'}->prepare(
        qq{
            SELECT branch_id FROM branches
            WHERE branch = ?;
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute($branch);
    my $result = $sth->fetchall_arrayref;

    return $result->[0][0];
}

=head2 $db-E<gt>_clean_branches()

Remove unreferenced branches from the database.

=cut

sub _clean_branches {
    my ($self) = @_;

    $self->{'dbh'}->do(
        qq{
            DELETE FROM branches WHERE branch_id NOT IN
            (SELECT DISTINCT branch_id FROM repository_states);
        }
    );

    return;
}

=head2 $db-E<gt>_prepare_deploy_state()

Prepares pieces of SQL queries used during insertion of
repository_state and deployment_state records.

=head3 Arguments

=over 4

=item $version_control

A C<Cpanel::VersionControl> object, which should provide the
C<last_update> and C<branch> methods.

=back

=head3 Returns

A hashref of the following format:

    {
        'keys'         => 'field1, field2',
        'values'       => [value1, value2],
        'predicates'   => 'field1 = ? AND field2 = ?',
        'placeholders' => '?, ?'
    }

=head3 Notes

These three fields are used by the C<_add_deploy_state> method in
constructing its SQL queries.

=cut

sub _prepare_deploy_state {
    my ( $self, $vc ) = @_;

    my ( @keys, @values, @predicates, @placeholders );

    my $state = $vc->last_update();
    for my $field ( 'identifier', 'date', 'message' ) {
        if ( defined $state->{$field} ) {
            push @keys,         $field;
            push @values,       "$state->{$field}";
            push @predicates,   "$field = ?";
            push @placeholders, '?';
        }
    }
    if ( defined $state->{'author'} ) {
        my $author_id = $self->_get_author( $state->{'author'} );
        push @keys,         'author_id';
        push @values,       $author_id;
        push @predicates,   "author_id = ?";
        push @placeholders, '?';
    }

    my $branch = $vc->branch();
    if ( defined $branch ) {
        my $branch_id = $self->_get_branch($branch);
        push @keys,         'branch_id';
        push @values,       $branch_id;
        push @predicates,   "branch_id = ?";
        push @placeholders, '?';
    }

    return {
        'keys'         => join( ', ', @keys ),
        'values'       => \@values,
        'predicates'   => join( ' AND ', @predicates ),
        'placeholders' => join( ', ',    @placeholders ),
    };
}

=head2 $db-E<gt>_add_deploy_state()

Insert a new deployment_state record into the database.  If a new
repository_state record is needed, it will also be inserted.

=head3 Arguments

=over 4

=item $deployment_id

=item $fields

=back

=cut

sub _add_deploy_state {
    my ( $self, $deploy_id, $fields ) = @_;

    return unless length $fields->{'keys'};

    my $sth = $self->{'dbh'}->prepare(
        qq{
            INSERT OR IGNORE INTO repository_states ($fields->{'keys'})
            VALUES ($fields->{'placeholders'});
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute( @{ $fields->{'values'} } );
    $sth = $self->{'dbh'}->prepare(
        qq{
            SELECT state_id FROM repository_states
            WHERE $fields->{'predicates'};
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute( @{ $fields->{'values'} } );
    my $state_id = ( $sth->fetchrow_array )[0];
    $sth = $self->{'dbh'}->prepare(
        qq{
            INSERT INTO deployment_states (deploy_id, state_id)
            VALUES (?, ?);
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute( $deploy_id, $state_id );

    return;
}

=head2 $db-E<gt>_get_deploy_state()

Return the deployment state for a given deployment ID.

=head3 Arguments

=over 4

=item $deployment_id

=back

=cut

sub _get_deploy_state {
    my ( $self, $deploy_id ) = @_;

    my $sth = $self->{'dbh'}->prepare(
        qq{
            SELECT branch, date, identifier, author, message
            FROM deployment_states
              NATURAL JOIN repository_states
              NATURAL JOIN branches
              NATURAL JOIN authors
            WHERE deploy_id = ?;
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute($deploy_id);

    my $result = $sth->fetchrow_hashref;
    return $result;
}

=head2 $db-E<gt>_remove_deployment_state()

Removes a deployment state record from the database.  No foreign keys
depend on this table, so this can be performed first in the removal
process.

=head3 Arguments

=over 4

=item $deployment_id

The ID value of the deployment we wish to remove.

=back

=cut

sub _remove_deployment_state {
    my ( $self, $deploy_id ) = @_;

    my $sth = $self->{'dbh'}->prepare(
        qq{
            DELETE FROM deployment_states WHERE deploy_id = ?;
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute($deploy_id);

    return;
}

=head2 $db-E<gt>_clean_repository_states()

Remove unreferenced repository_states from the database.

=cut

sub _clean_repository_states {
    my ($self) = @_;

    $self->{'dbh'}->do(
        qq{
            DELETE FROM repository_states WHERE state_id NOT IN
            (SELECT DISTINCT state_id FROM deployment_states);
        }
    );

    return;
}

=head2 $db-E<gt>_add_deployment()

Insert a new record for a deployment into the database.  Returns the
deployment ID for the new record.

=head3 Arguments

=over 4

=item $task_id

=item $repository_root

=item $log_path

=back

=cut

sub _add_deployment {
    my ( $self, $task_id, $repo_root, $log_path ) = @_;

    my $repo = $self->_get_repository($repo_root);

    my $sth = $self->{'dbh'}->prepare(
        qq{
            INSERT INTO deployments (task_id, repository_id, log_path)
            VALUES (?, ?, ?);
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute( $task_id, $repo, $log_path );
    my $deploy = $self->{'dbh'}->last_insert_id(
        undef,
        undef,
        'deployments',
        'deploy_id'
    );

    $self->_add_timestamp( $deploy, 'queued' );

    return $deploy;
}

=head2 $db-E<gt>_get_deployment()

Retrieve a deployment record from the database.  Records will include
timestamps.

=head3 Arguments

=over 4

=item $deployment_id

ID for the deployment in question.

=back

=cut

sub _get_deployment {
    my ( $self, $deploy_id ) = @_;

    my $sth = $self->{'dbh'}->prepare(
        qq{
            SELECT deploy_id, task_id, repository_root, log_path
            FROM deployments
              NATURAL JOIN repositories
            WHERE deploy_id = ?;
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute($deploy_id);
    my $result = $sth->fetchrow_hashref;

    return unless defined $result->{'task_id'};

    $result->{'timestamps'} = $self->_get_timestamps($deploy_id);

    my $state = $self->_get_deploy_state($deploy_id);
    $result->{'repository_state'} = $state
      if defined $state;

    return $result;
}

=head2 $db-E<gt>_get_all_deployments()

Returns all the deployments in the database.  All records will include
timestamps.

=cut

sub _get_all_deployments {
    my ($self) = @_;

    my $sth = $self->{'dbh'}->prepare(
        qq{
            SELECT deploy_id, task_id, repository_root, log_path
            FROM deployments
              NATURAL JOIN repositories;
        }
    );
    $sth->execute();
    my $result = [];
    while ( my $row = $sth->fetchrow_hashref() ) {
        push @$result, $row;
    }
    for my $deploy (@$result) {
        $deploy->{'timestamps'} = $self->_get_timestamps( $deploy->{'deploy_id'} );
        my $state = $self->_get_deploy_state( $deploy->{'deploy_id'} );
        $deploy->{'repository_state'} = $state
          if defined $state;

    }

    return $result;
}

=head2 $db-E<gt>_clean_deployments()

Remove unreferenced deployments from the database.

=cut

sub _clean_deployments {
    my ($self) = @_;

    $self->{'dbh'}->do(
        qq{
            DELETE FROM deployments WHERE deploy_id NOT IN
            (SELECT DISTINCT deploy_id FROM deployment_states);
        }
    );

    return;
}

=head2 $db-E<gt>_add_timestamp()

Add a timestamp for the given deployment ID.

=head3 Arguments

=over 4

=item $deployment_id

ID for the deployment in question.

=item $status

String of the status to update.  Unrecognized statuses will be
ignored.  Valid status strings are 'queued', 'active', 'succeeded',
'failed', or 'canceled'.

=back

=head3 Notes

Once a status is in the database, it will not be changed.  Any
attempts to update it via this object will be ignored.

=cut

sub _add_timestamp {
    my ( $self, $deploy_id, $status ) = @_;

    return unless grep { $_ eq $status } keys %{ $self->{'statuses'} };

    my $time = Time::HiRes::gettimeofday();
    my $sth  = $self->{'dbh'}->prepare(
        qq{
            INSERT OR IGNORE INTO timestamps (deploy_id, status_id, timestamp)
            VALUES (?, ?, ?);
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute( $deploy_id, $self->{'statuses'}{$status}, $time );

    return;
}

=head2 $db-E<gt>_get_timestamps()

Return a hashref of all timestamps for a given deployment ID.

=head3 Arguments

=over 4

=item $deployment_id

ID for the deployment in question.

=back

=cut

sub _get_timestamps {
    my ( $self, $deploy_id ) = @_;

    my $sth = $self->{'dbh'}->prepare(
        qq{
            SELECT status, timestamp FROM timestamps
              NATURAL JOIN statuses
            WHERE deploy_id = ?;
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute($deploy_id);
    my $stamps = $sth->fetchall_arrayref;

    return { map { $_->[0] => $_->[1] } @$stamps };
}

=head2 $db-E<gt>_remove_timestamps()

Removes all timestamp records from the database which relate to the
provided deployment ID.  No foreign keys depend on this table, so this
can be performed first in the removal process.

=head3 Arguments

=over 4

=item $deployment_id

The ID value of the deployment we wish to remove.

=back

=cut

sub _remove_timestamps {
    my ( $self, $deploy_id ) = @_;

    my $sth = $self->{'dbh'}->prepare(
        qq{
            DELETE FROM timestamps WHERE deploy_id = ?;
        }
    ) || die "Couldn't prepare statement: " . $self->{'dbh'}->errstr;
    $sth->execute($deploy_id);

    return;
}

=head2 _add_schema()

Adds a schema to a database file, along with the status entries.

=cut

sub _add_schema {
    my ($self) = @_;

    my @tables = (
        qq{
            CREATE TABLE repositories (
                repository_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                repository_root TEXT UNIQUE NOT NULL
            );
        },
        qq{
            CREATE TABLE statuses (
                status_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                status TEXT UNIQUE NOT NULL
            );
        },
        qq{ INSERT INTO statuses (status_id, status) VALUES (1, 'queued'); },
        qq{ INSERT INTO statuses (status_id, status) VALUES (2, 'active'); },
        qq{ INSERT INTO statuses (status_id, status) VALUES (3, 'succeeded'); },
        qq{ INSERT INTO statuses (status_id, status) VALUES (4, 'failed'); },
        qq{ INSERT INTO statuses (status_id, status) VALUES (5, 'canceled'); },
        qq{
            CREATE TABLE deployments (
                deploy_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                task_id TEXT UNIQUE NOT NULL,
                repository_id INTEGER NOT NULL,
                log_path TEXT NOT NULL,
                FOREIGN KEY (repository_id) REFERENCES repositories(repository_id)
            );
        },
        qq{
            CREATE TABLE timestamps (
                deploy_id INTEGER NOT NULL,
                status_id INTEGER NOT NULL,
                timestamp REAL NOT NULL,
                CONSTRAINT unique_ids UNIQUE (deploy_id, status_id),
                FOREIGN KEY (deploy_id) REFERENCES deployments(deploy_id),
                FOREIGN KEY (status_id) REFERENCES statuses(status_id)
            );
        },
        qq{
            CREATE TABLE branches (
                branch_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                branch TEXT UNIQUE NOT NULL
            );
        },
        qq{
            CREATE TABLE authors (
                author_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                author TEXT UNIQUE NOT NULL
            );
        },
        qq{
            CREATE TABLE repository_states (
                state_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                branch_id INTEGER,
                date INTEGER NOT NULL,
                identifier TEXT NOT NULL,
                author_id INTEGER,
                message TEXT,
                CONSTRAINT unique_state UNIQUE
                  (branch_id, date, identifier, author_id, message),
                FOREIGN KEY (branch_id) REFERENCES branches(branch_id),
                FOREIGN KEY (author_id) REFERENCES authors(author_id)
            );
        },
        qq{
            CREATE TABLE deployment_states (
                deploy_id INTEGER NOT NULL,
                state_id INTEGER NOT NULL,
                FOREIGN KEY (deploy_id) REFERENCES deployments(deploy_id),
                FOREIGN KEY (state_id) REFERENCES repository_states(state_id)
            );
        },
    );

    for my $table (@tables) {
        $self->{'dbh'}->do($table);
    }
    return;
}

=head1 PRIVATE FUNCTIONS

=head2 _db_filename()

Returns the database file location.

=cut

sub _db_filename {
    my $homedir = Cpanel::PwCache::gethomedir();

    return "$homedir/$DB_FILENAME";
}

=head1 CONFIGURATION AND ENVIRONMENT

There are no configuration files or environment variables which are
required or produced by this module.

=head1 DEPENDENCIES

L<Cpanel::PwCache>.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2018, cPanel, Inc.  All rights reserved.  This code is
subject to the cPanel license.  Unauthorized copying is prohibited.

=cut

1;
