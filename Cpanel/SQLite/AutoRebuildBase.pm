package Cpanel::SQLite::AutoRebuildBase;

# cpanel - Cpanel/SQLite/AutoRebuildBase.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();
use DBD::SQLite        ();

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::SQLite::AutoRebuildBase

=head1 SYNOPSIS

    package a::sqlite::database::object;

    use parent qw( Cpanel::SQLite::AutoRebuildBase );

    # The following methods must be defined

    sub _handle_invalid_database { ... }

    sub _get_production_dbh { ... }

    sub _get_schema_version { ... }

    sub _create_db { ... }

    sub _PATH { ... }

=head1 DESCRIPTION

This module is meant to be used as a base class for SQLite databases that need to
support a self-healing rebuild path when/if the database becomes corrupt.

=head1 FUNCTIONS


=cut

my $MAX_TRIES_TO_CREATE = 20;

#This is a WAAY-too-long time, actually, but it’s just here
#to be sure we don’t sit here indefinitely.
my $_MAX_WAIT_TIME = 24 * 60 * 60;

#Overridden in tests.
our @_WAIT_TIMES = (
    [ 300 => 30 ],    #Been >= 300 seconds? Wait 30 seconds before retry.
    [ 0   => 10 ],
);

our $SKIP_INTEGRITY_CHECK = 0;

my @SQLITE_ERRORS_THAT_TRIGGER_REBUILD = qw(
  CANTOPEN
  CORRUPT
  ERROR
  NOTADB
);

=head2 new( KEY => VALUE, .. )

This function instantiates an object of the type inheriting from this base class.
If the database it tries to connect to cannot be opened, the function will rebuild/recreate
that database depending on how the implementing/inheriting class handles it.

NOTE: Unless you’re in a context where you can handle the
“Database::DatabaseCreationInProgress” exception, you probably want
new_with_wait(), which, well, “wait”s for DB recreation to finish
if another process has already started rebuilding it.

=head3 Arguments

=over 4

=item %OPTS    - hash - A hash of possible arguments (defined in inheriting classes)

=back

=head3 Returns

This function returns an object of the type inheriting from this base class.

=head3 Exceptions

This function will throw exceptions if there are unexpected errors in creating the database or it
takes too many tries to recreate the database.

=cut

sub new {
    my ( $class, %OPTS ) = @_;

    my $self;

    my $path = $class->_PATH( \%OPTS );

    for my $i ( 0 .. $MAX_TRIES_TO_CREATE ) {
        if ( $i == $MAX_TRIES_TO_CREATE ) {
            die Cpanel::Exception->create_raw("I tried $MAX_TRIES_TO_CREATE times to create the SQLite database at '$path', but each time I failed to open it afterward. This should never happen!");
        }

        try {
            $self = $class->new_without_rebuild(%OPTS);
        }
        catch {
            my $err = $_;
            local $@ = $_;

            die if !try { $err->isa('Cpanel::Exception::Database::Error') };

            #Unrecognized error? Rethrow it!
            if ( !grep { $err->failure_is("SQLITE_$_") } @SQLITE_ERRORS_THAT_TRIGGER_REBUILD ) {
                $@ = $_;
                die;
            }
        };

        last if defined $self;

        my $invalid_db_opts = $class->_handle_invalid_database(%OPTS);

        $class->_create_db( %$invalid_db_opts, %OPTS );

        #Having now created the DB, we’ll try again to open it.
    }

    return $self;
}

=head2 new_without_rebuild( KEY => VALUE, .. )

This function instantiates an object of the type inheriting from this base class.
If the database it tries to connect to cannot be opened, an exception will be thrown.
No rebuild or self-healing will occur.

This “plain” instantiation is only desirable in contexts where it’s
unfeasible to rebuild the cache DB, e.g., cpanellogd

=head3 Arguments

=over 4

=item %OPTS    - hash - A hash of possible arguments (defined in inheriting classes)

=back

=head3 Returns

This function returns an object of the type inheriting from this base class.

=head3 Exceptions

This function allows all exceptions to bubble up.

=cut

sub new_without_rebuild {
    my ( $class, %OPTS ) = @_;

    my $self = bless {}, $class;

    $self->_get_production_dbh( \%OPTS );

    #NOTE: These are where we can get SQLITE_NOTADB if, e.g., the file
    #has been corrupted. This is a *good* thing, so we know up-front that
    #the file is not usable.
    #
    $self->_schema_check( \%OPTS );

    # NB: The “unless” checks below are to prevent a multiple integrity
    # check that was seen during profiling but hasn’t been reproducible.
    #
    if ( $OPTS{full_integrity_check} ) {
        $self->_full_integrity_check( \%OPTS ) unless $self->{'_did_integrity_check'};
    }
    else {
        $self->_quick_integrity_check( \%OPTS ) unless $self->{'_did_quick_check'};
    }

    return $self;
}

=head2 new_with_wait( KEY => VALUE, .. )

This function instantiates an object of the type inheriting from this base class.
If the database it tries to connect to cannot be opened, the function will rebuild/recreate
that database depending on how the implementing/inheriting class handles it.

This will wait, up to $_MAX_WAIT_TIME, for the DB to be available.
This is what you want if you don’t mind waiting.

=head3 Arguments

=over 4

=item %OPTS    - hash - A hash of possible arguments (defined in inheriting classes)

=back

=head3 Returns

This function returns an object of the type inheriting from this base class.

=head3 Exceptions

This function will throw exceptions if there are unexpected errors in creating the database or it
takes too many tries to recreate the database.

=cut

sub new_with_wait {
    my ( $class, %OPTS ) = @_;

    my $started = _time();

    my $self;

    while ( !$self && ( $started + $_MAX_WAIT_TIME ) > _time() ) {
        try {
            $self = $class->new(%OPTS);
        }
        catch {
            local $@ = $_;

            die if !try { $_->isa('Cpanel::Exception::Database::DatabaseCreationInProgress') };

            my $elapsed = _time() - $started;

          WAIT:
            for my $t (@_WAIT_TIMES) {
                next if $elapsed < $t->[0];
                _sleep( $t->[1] );
                last WAIT;
            }
        };
    }

    return $self;
}

=head2 _handle_invalid_database()

The implementing class should use this function as a means to clean up the database
if it becomes corrupt or unreadable. It could move it out of the way, delete it, etc.

=head3 Arguments

None.

=head3 Returns

This function may return a hashref that will be passed into the _create_db function as KEY => VALUE.

=head3 Exceptions

This function should allow exceptions to 'bubble up'.

=cut

sub _handle_invalid_database {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

=head2 _get_production_dbh()

The implementing class should use this function as a means to get the database handle on
the database.

=head3 Arguments

None.

=head3 Returns

This function isn't expected to return anything.

=head3 Exceptions

This function should allow exceptions to 'bubble up'.

=cut

sub _get_production_dbh {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

=head2 _get_schema_version()

The implementing class should use this function as a means to get the schema version of
the database. This function is used as a means to tell if the database is readable and not
corrupted.

=head3 Arguments

None.

=head3 Returns

This function isn't expected to return anything.

=head3 Exceptions

This function should allow exceptions to 'bubble up'.

=cut

sub _get_schema_version {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

=head2 _create_db( KEY => VALUE )

The implementing class should use this function as a means to recreate the
database if it should become corrupt or unreadable.

=head3 Arguments

The hashref returned by _handle_invalid_database is passed into this function
as KEY => VALUE pairs. Arguments passed to the new(?:_with_wait) functions are
passed to this one as well, with these arguments taking precedence over the return
value from _handle_invalid_database. Please see derived modules for more detail.

=head3 Returns

This function isn't expected to return anything.

=head3 Exceptions

This function should allow exceptions to 'bubble up'.

=cut

sub _create_db {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

=head2 _PATH()

The implementing class should use this function to return the path to the
SQLite database file.

=head3 Arguments

None.

=head3 Returns

This function isn't expected to return anything.

=head3 Exceptions

This function should allow exceptions to 'bubble up'.

=cut

sub _PATH {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

=head2 _schema_check()

The implementing class should use this function to check if the schema version has
changed and upgrade the database if so.

Setting the global flag $SKIP_INTEGRITY_CHECK will make this function skip the check.
This is important for situations like in iContact where we just want to send a message
quickly and not wait for the integrity check to complete.

=head3 Arguments

None.

=head3 Returns

This function isn't expected to return anything.

=head3 Exceptions

This function should allow exceptions to 'bubble up'.

=cut

sub _schema_check {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

=head2 _quick_integrity_check()

The implementing class should use this function to check if the database is corrupt.

Setting the global flag $SKIP_INTEGRITY_CHECK will make this function skip the check.
This is important for situations like in iContact where we just want to send a message
quickly and not wait for the integrity check to complete.

=head3 Arguments

None.

=head3 Returns

This function isn't expected to return anything.

=head3 Exceptions

This function should allow exceptions to 'bubble up'.

=cut

sub _quick_integrity_check {
    my ( $self, $opts ) = @_;

    if ($SKIP_INTEGRITY_CHECK) {
        return;
    }

    my $results = $self->_run_check('quick_check');
    $self->{'_did_quick_check'} = 1;

    # The above may or may not error depending on how badly the database is corrupt.
    # So, we send the result if there wasn't an exception to another function to handle
    return $self->_handle_results_of_integrity_check($results);
}

=head2 _full_integrity_check()

The implementing class should use this function to check if the database is corrupt.

=head3 Arguments

None.

=head3 Returns

This function isn't expected to return anything.

=head3 Exceptions

This function should allow exceptions to 'bubble up'.

=cut

sub _full_integrity_check {
    my ( $self, $opts ) = @_;

    if ($SKIP_INTEGRITY_CHECK) {
        return;
    }

    my $results = $self->_run_check('integrity_check');
    $self->{'_did_integrity_check'} = 1;

    # The above may or may not error depending on how badly the database is corrupt.
    # So, we send the result if there wasn't an exception to another function to handle
    return $self->_handle_results_of_integrity_check($results);
}

sub _run_check {
    my ( $self, $type ) = @_;
    return $self->_get_production_dbh()->selectrow_arrayref("PRAGMA $type;");
}

# Handle the non-exception results
sub _handle_results_of_integrity_check {
    my ( $self, $results ) = @_;

    if ( $results && @$results && $results->[0] eq 'ok' ) {
        return 1;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::DBI::SQLite::Error');
    Cpanel::LoadModule::load_perl_module('Cpanel::Exception::Database::Error');

    die Cpanel::Exception::Database::Error->new( 'The SQLite database did not pass the integrity check', { dbi_driver => 'SQLite', error_code => Cpanel::DBI::SQLite::Error::SQLITE_CORRUPT() } );    ## no extract maketext
}

# For tests
sub _sleep {
    return sleep $_[0];
}

# For tests
sub _time {
    return time();
}

1;
