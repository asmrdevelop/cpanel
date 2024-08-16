
# cpanel - Cpanel/UserManager/Storage.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::UserManager::Storage;

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::UserManager::Storage

=head1 EXECUTION ENVIRONMENT

Run as user: Yes

Run as root: No; relies on current uid to locate the database

Requires cPanel variables: No

=cut

#----------------------------------------------------------------------

use Carp ();

use Cpanel::Autodie    ();
use Cpanel::Exception  ();
use Cpanel::LoadModule ();
use Cpanel::Locale 'lh';
use Cpanel::Logger                         ();
use Cpanel::PwCache                        ();
use Cpanel::SQLite::Savepoint              ();
use Cpanel::Umask                          ();
use Cpanel::UserManager::Annotation        ();
use Cpanel::UserManager::AnnotationList    ();
use Cpanel::UserManager::Record            ();    # PPI USE OK - used by listusers
use Cpanel::UserManager::Record::Lite      ();    # PPI USE OK - could be used by listusers
use Cpanel::UserManager::Storage::Versions ();

use Try::Tiny;

our $DB_DIR  = '.subaccounts';
our $DB_NAME = 'storage.sqlite';

=head1 FUNCTIONS

=head2 store(OBJECT)

Store a sub-account record or service account annotation in the database.

If OBJECT isa L<Cpanel::UserManager::Record>, but that object conflicts
with another that already exists in the database, a
L<Cpanel::Exception::EntryAlreadyExists> exception is thrown.
That exception’s metadata will contain an C<entry> property whose value
is a L<Cpanel::UserManager::Record> object that represents the conflicting
record.

If, however, OBJECT isa L<Cpanel::UserManager::Annotation>, any existing
conflicting object is B<overwritten>.

=head3 ARGUMENTS

Accepts a single argument B<OBJECT>, which may be an object of one of the following types:

- Cpanel::UserManager::Record

- Cpanel::UserManager::Annotation

- Anything else that has a compatible as_insert method

Example usage:

  my $record = Cpanel::UserManager::Record->new( {
        type => 'sub',
        username => 'bob',
        domain => 'example.com',
        real_name => 'Bob Bobson',
        password => 'superSecurePassword'
    });
  Cpanel::UserManager::Storage::store($record);

=cut

sub store ($obj) {
    my $dbh = dbh();

    my $save = Cpanel::SQLite::Savepoint->new($dbh);

    my ( $sql_statement, $sql_args_ar );

    if ( eval { $obj->isa('Cpanel::UserManager::Record') } ) {

        my $existing = $dbh->selectall_arrayref( 'SELECT guid FROM users WHERE type = ? AND username = ? AND domain = ?', {}, $obj->type, $obj->username, $obj->domain );

        if ( $existing && @$existing ) {
            my $existing_ar = list_users(
                dbh  => $dbh,
                guid => $existing->[0][0],
            );

            $save->release();

            die Cpanel::Exception::create( 'EntryAlreadyExists', 'A record of the type “[_1]” named “[_2]” at the domain “[_3]” already exists.', [ $obj->type, $obj->username, $obj->domain ], { entry => $existing_ar->[0] } );
        }

        # This setter has to be directly called in order to generate the password hash.
        $obj->password( $obj->password );
    }
    elsif ( eval { $obj->isa('Cpanel::UserManager::Annotation') } ) {
        my $existing = $dbh->selectall_arrayref( 'SELECT service,username,domain FROM annotations WHERE service = ? AND username = ? AND domain = ?', {}, $obj->service, $obj->username, $obj->domain );

        if ( 'ARRAY' eq ref $existing && @$existing ) {
            ( $sql_statement, $sql_args_ar ) = $obj->as_update;
        }
    }
    else {
        $save->release();

        Carp::croak( lh()->maketext('You can only store objects of type [asis,Cpanel::UserManager::Record] or [asis,Cpanel::UserManager::Annotation].') );
    }

    if ( !$sql_statement ) {
        ( $sql_statement, $sql_args_ar ) = $obj->as_insert();
    }

    $dbh->do( $sql_statement, {}, @$sql_args_ar );

    $save->release();

    return $obj;
}

=head2 amend(OBJECT)

Amend an existing sub-account record in the database.

=head3 Arguments

  - OBJECT - A Cpanel::UserManager::Record object - The record to amend.

=cut

sub amend {
    my ($obj) = @_;
    my $dbh = dbh();
    my ( $insert_statement, $insert_args ) = $obj->as_update;
    return $dbh->do( $insert_statement, {}, @$insert_args );
}

=head2 delete_user(GUID)

Delete a record from the users table.

=head3 ARGUMENTS

- GUID - string - the guid of the record to delete.

Example usage:

    Cpanel::UserManager::Storage::delete_user($guid);

=cut

sub delete_user {
    my ($guid) = @_;

    my $dbh = dbh();
    return $dbh->do( 'DELETE FROM users WHERE guid = ?', {}, $guid );
}

=head2 list_users(guid => ...)

List all users from the unified account storage backend.

=head3 ARGUMENTS

  - guid - String - If specified, filter by this guid.

=head3 RETURNS

array ref of Cpanel::UserManager::Record-compatible objects.

=cut

sub list_users {
    my %args = @_;

    # Shortcut for the case where the database doesn't exist yet, and so we know that there are no subaccounts.
    # This also gets around the problem that attempting to auto-create the database for lists prevented listing
    # of accounts when over-quota.
    if ( !-e _db_file() ) {
        return [];
    }

    my $dbh = delete $args{'dbh'} || dbh();

    my $objtype = $args{objtype} || 'Cpanel::UserManager::Record';

    my $records;
    my $annotations;
    if ( $args{guid} ) {
        $records     = $dbh->selectall_arrayref( 'SELECT * FROM users WHERE guid = ?',                              { Slice => {} }, $args{guid} );
        $annotations = $dbh->selectall_arrayref( 'SELECT service,owner_guid FROM annotations WHERE owner_guid = ?', { Slice => {} }, $args{guid} );
    }
    elsif ( $args{full_username} ) {
        my ( $username, $domain ) = split( /[@]/, $args{full_username} );
        $username    = lc $username;                                                                                                                   # Usernames should be stored as lowercase, but people might try to look them up using other styles
        $records     = $dbh->selectall_arrayref( 'SELECT * FROM users WHERE username = ? AND domain = ?', { Slice => {} }, ( $username, $domain ) );
        $annotations = $dbh->selectall_arrayref( 'SELECT service,owner_guid FROM annotations', { Slice => {} } );
    }
    else {
        $records     = $dbh->selectall_arrayref( 'SELECT * FROM users',                        { Slice => {} }, () );
        $annotations = $dbh->selectall_arrayref( 'SELECT service,owner_guid FROM annotations', { Slice => {} } );
    }

    my %annotations_lookup;
    for my $annotation (@$annotations) {
        if ( $annotation->{merged} ) {
            push @{ $annotations_lookup{ $annotation->{owner_guid} } }, $annotation->{service};
        }

        # else: this is a dismissal, and so it can't possibly be linked to any sub-account
    }

    my @record_objs;
    for my $rec (@$records) {
        my $owned_services = $annotations_lookup{ $rec->{guid} };
        $rec->{services} = { map { $_ => { enabled => 1 } } @$owned_services };

        my $record = eval { $objtype->new($rec) };
        if ( my $exception = $@ ) {

            # If any of the existing data is invalid and can't be loaded, log it, but otherwise just pretend
            # it doesn't exist to avoid interfering with operations on the remaining valid data.
            Cpanel::Logger->new->warn( lh()->maketext('There is a problem with one or more records in the [asis,subaccount] database: [_2]'), $exception );
        }
        else {
            push @record_objs, $record;
        }
    }

    return \@record_objs;
}

=head2 lookup_user(username => ..., domain => ...)

Look up a user by username and domain.

=head3 ARGUMENTS

  - username      - String - The username (without the @domain portion).
  - domain        - String - The domain of the user.

Additionally, any valid attribute of a I<Cpanel::UserManager::Record> object may be passed
as an argument as long as it also corresponds to a stored attribute in the database.

Alternatively, you can give:
  - guid          - String - The user’s guid

=head3 RETURNS

If exactly one matching user is found, this function returns a Cpanel::UserManager::Record-compatible object.

If no matching users are found, this function returns an undefined value.

=head3 THROWS

This function throws an exception in either of these cases:

  - More than one match was found.

  - The database could not be queried.

Callers should not attempt to trap these exceptions unless they intend to offer the end-user a way to solve the problem.

=cut

sub lookup_user {
    my %args = @_;
    if ( !%args ) {
        die lh()->maketext('You must filter with at least one attribute to search for a user.') . "\n";
    }

    # If the database does not exist, the subaccount cannot possibly exist
    return undef if !Cpanel::Autodie::exists( _db_file() );

    my $dbh          = delete $args{'dbh'} || dbh();
    my $known_fields = _users_fields();

    my @list_users_args;
    if ( $args{guid} ) {
        push @list_users_args, guid => $args{guid};    # optimize lookup if using guid
    }
    elsif ( $args{username} && $args{domain} ) {
        push @list_users_args, full_username => $args{username} . '@' . $args{domain};    # optimize lookup if we have the username and domain
    }

    my $record_objs = list_users( @list_users_args, 'dbh', $dbh );

    my @matches;
  RECORD: for my $record (@$record_objs) {
        for my $k ( sort keys %args ) {

            # This check for known fields is important because we're calling an object method named after whatever was passed in.
            # If we don't check that it's a valid field, then the caller could pass something that results in an operation other
            # than accessing an attribute being performed.
            if ( !$known_fields->{$k} ) {
                die lh()->maketext( 'Unknown user attribute: [_1]', $k ) . "\n";
            }

            if ( $record->$k && !$args{$k} || !$record->$k && $args{$k} || $record->$k ne $args{$k} ) {
                next RECORD;
            }
        }
        push @matches, $record;
    }

    if ( @matches == 1 ) {
        my $record_obj = $matches[0];
        my $services   = $dbh->selectall_arrayref( 'SELECT service FROM annotations WHERE owner_guid = ?', {}, $record_obj->guid );
        for my $row ( @{ $services || [] } ) {
            $record_obj->has_service( $row->[0], 1 );
        }
        return $record_obj;
    }
    elsif ( @matches > 1 ) {
        die lh()->maketext('The system found more than one match for the lookup criteria.') . "\n";
    }

    return undef;
}

=head2 list_annotations(full_username => ...)

Look up the service annotations. If a full_username is provided, it will filter it down to just the
service annotation for that user. Limited to the records belonging to the current cpanel user.

=head3 ARGUMENTS

  - full_username - string - optional, <user>@<domain> or <cpanel user>

=head3 RETURNS

Cpanel::UserManager::AnnotationList containing the records.

=cut

sub list_annotations {
    my %args = @_;

    # Shortcut for the case where the database doesn't exist yet, and so we know that there are no annotations.
    # This also gets around the problem that attempting to auto-create the database for lists prevented listing
    # of accounts when over-quota.
    if ( !-e _db_file() ) {
        return Cpanel::UserManager::AnnotationList->new( [] );
    }

    my $dbh = delete $args{'dbh'} || dbh();
    my $annotations;

    if ( $args{full_username} ) {
        my ( $username, $domain ) = split( /[@]/, $args{full_username} );
        $annotations = $dbh->selectall_arrayref( 'SELECT * FROM annotations WHERE username = ? AND domain = ?', { Slice => {} }, ( $username, $domain ) );
    }
    else {
        $annotations = $dbh->selectall_arrayref( 'SELECT * FROM annotations', { Slice => {} } );
    }

    my @annotation_objs = map { Cpanel::UserManager::Annotation->new($_) } @$annotations;
    return Cpanel::UserManager::AnnotationList->new( \@annotation_objs );
}

=head2 delete_annotation(RECORD, SERVICE)

Delete the service annotations for a specific user and service.

=head3 ARGUMENTS

RECORD - Cpanel::UserManager::Record - User we are deleting annotation from.

SERVICE - string - Name of the service to delete: email, ftp, webdisk

=cut

sub delete_annotation {
    my ( $record_obj, $service ) = @_;

    my $dbh = dbh();
    return $dbh->do( 'DELETE FROM annotations WHERE username = ? AND domain = ? AND service = ?', {}, $record_obj->username, $record_obj->domain, $service );
}

=head2 change_domain(OLD_DOMAIN, NEW_DOMAIN)

Changes all the domains for users and their annotation when a domain is renamed. This is common
when a domain is removed from an account or an accounts primary domain is changed.

=head3 ARGUMENTS

- OLD_DOMAIN - string - starting domain.
- NEW_DOMAIN - string - final domain.

=cut

sub change_domain {
    my ( $old_domain, $new_domain ) = @_;
    my $dbh = dbh();
    $dbh->do('BEGIN TRANSACTION');
    $dbh->do( 'UPDATE users SET domain = ? WHERE domain = ?',       {}, $new_domain, $old_domain );
    $dbh->do( 'UPDATE annotations SET domain = ? WHERE domain = ?', {}, $new_domain, $old_domain );
    $dbh->do('COMMIT');
    return;
}

sub _users_fields {
    my %fields = qw(
      alternate_email    text
      avatar_url         text
      domain             text
      guid               text
      password_hash      text
      digest_auth_hash   text
      phone_number       text
      real_name          text
      synced_password    integer
      type               text
      username           text
      has_invite         integer
      invite_expiration  integer
    );
    return \%fields;
}

sub _annotations_fields {
    my %fields = qw(
      service          text
      username         text
      domain           text
      owner_guid       text
      merged           integer
      dismissed_merge  integer
    );
    return \%fields;
}

# For mocking in unit tests
sub _homedir {
    if ( $> == 0 ) {
        Carp::croak( lh()->maketext('You cannot run this code as [asis,root].') );
    }

    my $homedir = Cpanel::PwCache::gethomedir() || die 'homedir unknown';
    return $homedir;
}

sub _ensure_db_dir_present {
    my $umask_obj = Cpanel::Umask->new(0077);

    my $db_dir = _db_dir();
    Cpanel::Autodie::mkdir_if_not_exists($db_dir);

    return;
}

sub _ensure_db_file_usable {
    my $umask_obj = Cpanel::Umask->new(0077);
    my $db_file   = _db_file();

    Cpanel::Autodie::open( my $db_fh, '>>', $db_file );

    my $need_schema = -z $db_fh;

    close $db_fh;

    return $need_schema;
}

sub _db_dir {
    return _homedir() . '/' . $DB_DIR;
}

sub _db_file {
    return _db_dir() . '/' . $DB_NAME;
}

=head2 dbh

Helper method to fetch the db handle for the users database for the current user.

=cut

sub dbh {
    my $db_file = _db_file();

    _ensure_db_dir_present();
    my $need_schema = _ensure_db_file_usable();

    Cpanel::LoadModule::load_perl_module('Cpanel::DBI');

    my $dbh = Cpanel::DBI->connect( 'dbi:SQLite:dbname=' . $db_file, '', '' );
    $dbh->{RaiseError} = 1;    # This is not set by Cpanel::DBI by default

    _create_schema($dbh) if $need_schema;

    return $dbh;
}

sub _create_schema {
    my ($dbh) = @_;

    my $fields      = _users_fields();
    my $fields_info = join( ', ', map { "$_ $fields->{$_}" } sort keys %$fields );
    $dbh->do(qq{CREATE TABLE users ($fields_info) });

    $fields      = _annotations_fields();
    $fields_info = join( ', ', map { "$_ $fields->{$_}" } sort keys %$fields );
    $dbh->do(qq{CREATE TABLE annotations ($fields_info) });

    Cpanel::UserManager::Storage::Versions::create_meta_table_if_needed( dbh => $dbh, initialize => 1 );

    return;
}

1;
