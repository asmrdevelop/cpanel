package Cpanel::DBAdmin;

# cpanel - Cpanel/DBAdmin.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This is a base class, not to be instantiated directly.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::Destruct ();
use Try::Tiny;

use Cpanel::Debug           ();
use Cpanel::DB::Map::Reader ();
use Cpanel::DB::Utils       ();
use Cpanel::Exception       ();
use Cpanel::LoadModule      ();
use Cpanel::ServerTasks     ();

our $DEFAULT_DBSTOREGRANTS_DEFER_TIME = 3;

#NOTE: Use with caution! First see if there’s a way to do what you want
#without direct DB access.
sub dbh_do {
    my ( $self, @args ) = @_;

    return $self->{'dbh'}->do(@args);
}

#NOTE: Returns the appropriate Cpanel::DB::Map instance.
sub _verify_db_in_map {
    my ( $self, $name ) = @_;

    if ( !$self->owns_db($name) ) {
        die Cpanel::Exception::create( 'Database::DatabaseNotFound', [ engine => $self->DB_ENGINE(), name => $name, cpuser => $self->{'cpuser'} ] );
    }

    return;
}

#NOTE: Returns the appropriate Cpanel::DB::Map instance.
sub _verify_dbuser_in_map {
    my ( $self, $name ) = @_;

    if ( !$self->owns_dbuser($name) ) {
        die Cpanel::Exception::create( 'Database::UserNotFound', [ engine => $self->DB_ENGINE(), name => $name, cpuser => $self->{'cpuser'} ] );
    }

    return;
}

sub owns_db {
    my ( $self, $db ) = @_;

    return $self->_get_map_reader()->database_exists($db);
}

sub owns_dbuser {
    my ( $self, $dbuser ) = @_;

    return $self->_get_map_reader()->dbuser_exists($dbuser);
}

#NOTE: This does NOT update the DB map, which is necessary for instantiating
#DB Map objects for the new cpuser. See Cpanel/DB/Map/Rename.pm.
sub rename_cpuser {
    my ( $self, $newname ) = @_;

    my $old_dbowner = Cpanel::DB::Utils::username_to_dbowner( $self->{'cpuser'} );
    my $new_dbowner = Cpanel::DB::Utils::username_to_dbowner($newname);

    # The db owners may be the same if we are just
    # removing an underscore or changing past the first
    # 8 characters of the username.
    #
    # In that case we do not need to rename the dbowner in the
    # database because it is the same.
    $self->_rename_dbowner( $old_dbowner, $new_dbowner ) if $old_dbowner ne $new_dbowner;

    $self->{'cpuser'} = $newname;

    return 1;
}

#NOTE: This does NOT add a DB prefix.
sub rename_dbuser {
    my ( $self, $oldname, $newname ) = @_;

    $self->_verify_dbuser_in_map($oldname);

    my $map = $self->_get_map();

    # method in child class ( probably Cpanel::Mysql or Cpanel::PostgresAdmin )
    my $ret = $self->_rename_dbuser_in_server( $oldname, $newname );

    $map->{'map'}->rename_dbuser( $oldname, $newname );
    $self->_save_map_hash($map);

    $self->queue_dbstoregrants();

    return $ret;
}

sub listdbs {
    my ($self) = @_;
    return $self->_get_map_reader()->get_databases();
}

#This does NOT add a DB prefix.
sub rename_database {
    my ( $self, $oldname, $newname ) = @_;

    $self->_verify_db_in_map($oldname);

    my $map = $self->_get_map();

    # method in child class ( probably Cpanel::Mysql or Cpanel::PostgresAdmin )
    my $ret = $self->_rename_database_in_server( $oldname, $newname );

    $map->{'map'}->rename_database( $oldname, $newname );
    $self->_save_map_hash($map);

    $self->queue_dbstoregrants();

    return $ret;
}

sub DESTROY {
    my ($self) = @_;

    return if Cpanel::Destruct::in_dangerous_global_destruction();

    $self->clear_map();

    if ( $self->{'_pid'} && $self->{'_pid'} == $$ ) {
        $self->destroy();
    }

    return;
}

sub _set_pid {
    my ($self) = @_;

    $self->{'_pid'} = $$;

    return;
}

# calling this method with a hash ref of the form, { 'deferred_seconds' => <int> }
# will result in dbstoregrants being scheduled using Cpanel::ServerTasks::schedule_task;
# If no value is specified for deferred_seconds, we use the default $DEFAULT_DBSTOREGRANTS_DEFER_TIME
sub queue_dbstoregrants {
    my ( $self, $opts ) = @_;

    return if $self->{'disable_queue_dbstoregrants'};

    if ( $self->{'cpuser'} eq 'root' ) {
        Cpanel::Debug::log_warn("Attempt to dbstoregrants for root");
        return 0;
    }

    my $seconds = int( $opts->{'deferred_seconds'} || 0 ) || $DEFAULT_DBSTOREGRANTS_DEFER_TIME;

    # schedule_task collapses identical requests within a certain window of time
    Cpanel::ServerTasks::schedule_task( ['MysqlTasks'], $seconds, "dbstoregrants " . $self->{'cpuser'} );

    return 1;
}

sub _log_error_and_output_return {
    my ( $self, $lstring ) = @_;

    if ( !try { $lstring->isa('Cpanel::LocaleString') } ) {
        die "Must receive a Cpanel::LocaleString, not “$lstring”!";
    }

    # Always log in en
    my $logger_text = $lstring->to_en_string();

    $self->{'logger'}->warn($logger_text);

    # Return errors in native language
    # $| here in case we die later before
    # stdout is flushed out with a print
    local $| = 1;

    my $err;
    if ($lstring) {
        $err = $lstring->to_string();
    }
    else {
        $err = 'UNKNOWN';
    }

    print "$err\n" if $self->{'ERRORS_TO_STDOUT'};

    return $err;
}

sub _log_error_and_output {
    my ( $self, $lstring ) = @_;

    $self->_log_error_and_output_return($lstring);

    return;
}

sub _get_map_reader {
    my ($self) = @_;

    return Cpanel::DB::Map::Reader->new(
        cpuser => $self->{'cpuser'},
        engine => $self->DB_ENGINE(),
    );
}

{
    my %map_cache;

    sub _get_map {
        my ($self) = @_;

        my $cpuser_as_hash_key = length( $self->{'cpuser'} ) ? $self->{'cpuser'} : q<>;

        #subclass provides _map_dbtype()
        my $dbtype = $self->_map_dbtype();

        if ( !$map_cache{$dbtype}{$cpuser_as_hash_key} ) {
            my $args = { cpuser => $self->{'cpuser'}, db => $dbtype };
            require Cpanel::DB::Map;
            my $map   = $self->{'allow_create_dbmap'} ? Cpanel::DB::Map->new_allow_create($args) : Cpanel::DB::Map->new($args);
            my $owner = $map->get_owner();

            $map_cache{$dbtype}{$cpuser_as_hash_key} = { 'map' => $map, 'owner' => $owner };
        }

        return $map_cache{$dbtype}{$cpuser_as_hash_key};
    }

    #NOTE: DB map objects that are fetched from _get_map() need
    #ALWAYS to be saved via this method; doing a manual save() on a DB map
    #object will make the DB map object persist in the cache, which will make
    #subsequent _get_map() calls return the already-saved-but-still-cached
    #DB map object, which will produce an exception when you try to save() that
    #DB map object for what ends up being a 2nd time.
    #
    #This die()s on failure.
    #
    sub _save_map_hash {
        my ( $self, $map_struct ) = @_;

        if ( ( 'HASH' ne ref($map_struct) ) || !$map_struct->{'owner'} ) {
            die "This method is for the data structure that _get_map() returns.";
        }

        my $map_obj = $map_struct->{'map'};
        $map_obj->save();

        delete $map_cache{ $self->_map_dbtype() }{ $map_obj->cpuser() || q<> };

        return;
    }

    sub clear_map {
        my ($self) = @_;

        my $dbtype = $self->_map_dbtype();

        delete $map_cache{$dbtype};

        return undef;
    }
}

my $locale;

sub _locale {
    return $locale ||= do {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        Cpanel::Locale->get_handle();
    };
}

1;
