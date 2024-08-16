package Cpanel::DB::Map;

# cpanel - Cpanel/DB/Map.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This is a read/write interface to the DB map.
# For a read-only interface (e.g., for access as a normal user) see
# Cpanel::DB::Map::Reader.
#----------------------------------------------------------------------

use strict;

use parent qw( Cpanel::DB::Map::Admin );    # perlpkg is really fragile in including base classes

use Cpanel::Autodie                 ();
use Cpanel::ConfigFiles             ();
use Cpanel::DB::Map::Owner          ();
use Cpanel::DB::Utils               ();
use Cpanel::PwCache                 ();
use Cpanel::Exception               ();
use Cpanel::Debug                   ();
use Cpanel::Transaction::File::JSON ();
use Cpanel::Validate::DB::User      ();
use Cpanel::LoadModule              ();
use Cpanel::Session::Constants      ();

#TODO: This flag was for testing during development of 11.50
#when the format was converted from YAML/Storable to JSON.
#It can safely be removed once we’re “out of the woods” on the
#YAML/Storable -> JSON conversion is done for existing customers.
my $KEEP_CONVERTED_OLD_FILES = 0;

my $MAP_FILE_PERMS = 0640;

my $DEFAULT_db = 'MYSQL';

our $DATASTORE_SCHEMA_VERSION = 1;

sub rename_cpuser {
    my ( $old_cpusername, $new_cpusername ) = @_;

    for my $dbengine (qw( MYSQL PGSQL )) {
        my $map   = __PACKAGE__->new( { cpuser => $old_cpusername, db => $dbengine } );
        my $owner = $map->get_owner();

        $owner->update_cpuser_name($new_cpusername);
        $map->update_cpuser_name($new_cpusername);

        $map->save();
    }

    my $oldpath = _data_file( { map_dir => $Cpanel::ConfigFiles::DATABASES_INFO_DIR, cpuser => $old_cpusername } );
    my $newpath = _data_file( { map_dir => $Cpanel::ConfigFiles::DATABASES_INFO_DIR, cpuser => $new_cpusername } );

    Cpanel::Autodie::rename( $oldpath, $newpath );

    # There may be a legacy YAML file present; if so, remove it, as its
    # existence will prevent creating an account.
    my $oldyaml = $oldpath =~ s/\.json\z/\.yaml/r;
    unlink($oldyaml) if -e $oldyaml;

    return 1;
}

#----------------------------------------------------------------------

#This constructor will automatically create a DB map entry for the user.
#If all you need to do is to create the entry, then just leave the object be;
#save()ing without having done anything with an “owner” object will produce
#a warning (which will break some tests).
#
#Note that this constructor will up-convert any old data on load and will
#save() whatever it has right away to ensure that the saved data is as it
#should be.
#
#If the user does not have a dbmap use
#Cpanel::DB::Map ->new_allow_create($args_hr) in order to allow
#the dbmap to be created
#
#$args is a hashref of:
#
#   cpuser  (required)
#
#   name    (dbowner - probably superfluous?)
#
#   db      either 'MYSQL' (default) or 'PGSQL'
#
#   dir     defaults to $Cpanel::ConfigFiles::DATABASES_INFO_DIR.
#           (Does anything use this?)
#
#
#
sub new {
    my ( $class, $args_hr ) = @_;

    my $self = $class->init($args_hr);

    bless $self, $class;

    $self->_initialize_data();

    return $self;
}

#->new_allow_create($args_hr)
#
#This is the same as ->new however it will allow
#the dbmap for the cpuser will be created
#if it does not exist.
#
#If a dbmap for the cpuser does not exist, a
#Database::CpuserNotInMap exception will be thown.
#This prevents background processes from re-creating
#the dbmap after a user has been deleted and
#getting the system in an indeterminate state which
#prevents the user from being recreated later.
#
sub new_allow_create {
    my ( $class, $args_hr ) = @_;

    my $self = $class->init($args_hr);

    bless $self, $class;

    $self->{'_allow_create'} = 1;

    $self->_initialize_data();

    return $self;
}

sub init {
    my ( $class, $args ) = @_;
    die "This now needs “cpuser”." if !$args->{'cpuser'};

    my $dbuser = $args->{'name'} || $args->{'cpuser'};
    $dbuser &&= Cpanel::DB::Utils::username_to_dbowner($dbuser);

    my $engine = $args->{'db'};
    $engine ||= $DEFAULT_db;

    if ( $engine eq 'MYSQL' ) {
        Cpanel::Validate::DB::User::verify_mysql_dbuser_name_format($dbuser);
    }
    elsif ( $engine eq 'PGSQL' ) {
        Cpanel::Validate::DB::User::verify_pgsql_dbuser_name_format($dbuser);
    }
    else {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid value of “[_2]”.', [ $args->{'db'}, 'db' ] );
    }

    my $self = {
        'owner'   => q<>,                                                          # will be an object later
        'db'      => $engine,
        'name'    => $dbuser,
        'cpuser'  => $args->{'cpuser'},
        'map_dir' => $args->{'dir'} || $Cpanel::ConfigFiles::DATABASES_INFO_DIR,
    };

    return $self;
}

#TODO: Use Cpanel::DB::Map::Path::data_file_for_username() for this.
sub _data_file {
    return sprintf( '%s/%s.json', $_[0]->{'map_dir'}, $_[0]->{'cpuser'} );
}

sub _open_transaction {
    my ( $self, @xaction_opts ) = @_;

    # Lookup here so we can avoid reading /etc/shadow
    my $gid;
    my @pw = Cpanel::PwCache::getpwnam_noshadow( $self->{'cpuser'} );
    if (@pw) {
        $gid = $pw[3];
    }
    else {
        $gid = ( Cpanel::PwCache::getpwnam_noshadow('root') )[3];
    }

    return $self->{'_transaction'} = Cpanel::Transaction::File::JSON->new(
        path        => $self->_data_file(),
        permissions => $MAP_FILE_PERMS,
        ownership   => [ 0, $gid ],
        @xaction_opts,
    );
}

sub _initialize_data {
    my ($self) = @_;

    die '“root” does not have a DB map!' if $self->{'cpuser'} eq 'root';

    my $data_file = $self->_data_file();

    my $transaction;
    my $changed;
    if ( $self->{'_allow_create'} ) {
        $transaction = $self->_open_transaction();

    }
    else {
        # If we do not allow create we need to open
        # without O_CREAT to make sure we do not create
        # the dbmap inadvertently
        $transaction = $self->_open_transaction( sysopen_flags => 0 );
        my $data_exists = !!$transaction;

        if ( !$data_exists ) {
            require Cpanel::DB::Map::Convert;

            if ( Cpanel::DB::Map::Convert::old_dbmap_exists( $self->{'cpuser'} ) ) {

                # Even if we’re not in “_allow_create” mode, if the map
                # file is in the old format then we open the transaction
                # for creation because we’re going to migrate the old data.
                # To the caller this is transparent.
                #
                # The order here ensures that we won’t get a race condition
                # between two processes: the first process that gets the
                # transaction lock reads the old map, writes the data, and
                # deletes the old map file before releasing the lock. Thus,
                # the 2nd process will not read any data from the old map file.

                $transaction = $self->_open_transaction();

                # NB: We don’t read the old dbmap if we passed allow_create.
                my $data = Cpanel::DB::Map::Convert::read_old_dbmap( $self->{'cpuser'} );

                if ($data) {
                    $changed = 1;
                    $transaction->set_data($data);
                    $self->{'_cleanup_old_on_save'} = 1;
                }
            }
            else {
                die Cpanel::Exception::create( 'Database::CpuserNotInMap', [ name => $self->{'cpuser'} ] );
            }
        }
    }

    if ( 'HASH' ne ref $transaction->get_data() ) {
        $changed = 1;
        $transaction->set_data( {} );
    }

    $self->{'stash'} = $transaction->get_data();
    if ( !exists $self->{'stash'}{ $self->{'db'} } ) {
        $changed = 1;
        $self->{'stash'}{ $self->{'db'} } = {};
    }

    if ( !$self->{'stash'}{'version'} ) {
        $changed = 1;
        $self->{'stash'}{'version'} = $DATASTORE_SCHEMA_VERSION;
    }

    $self->_clean_stash();

    #Save changes right away.
    if ($changed) {
        $transaction->save_or_die();
    }

    return;
}

#Pre-11.44 we sometimes (erroneously) wrote a DB with empty string
#for a name to the DB map. This also cleans out empty-string DBuser names
#just in case.
sub _clean_stash {
    my ($self) = @_;

    my $engine_stash = $self->{'stash'} && $self->{'stash'}{ $self->{'db'} };

    if ($engine_stash) {
        for my $obj_type (qw( dbusers dbs )) {
            delete $engine_stash->{$obj_type}{q<>} if $engine_stash->{$obj_type};
        }

        if ( $engine_stash->{'dbusers'} ) {
            for my $dbuser_entry ( values %{ $engine_stash->{'dbusers'} } ) {
                delete $dbuser_entry->{'dbs'}{q<>} if $dbuser_entry->{'dbs'};
            }
        }

        $self->_remove_invalid_dbusers();
    }

    return 1;
}

sub _save_file {
    my ($self) = @_;

    $self->{'_transaction'}->set_data( $self->{'stash'} );

    $self->{'_transaction'}->save_and_close_or_die();

    if ( !$KEEP_CONVERTED_OLD_FILES && $self->{'_cleanup_old_on_save'} ) {
        require Cpanel::DB::Map::Convert;
        Cpanel::DB::Map::Convert::remove_old_dbmap( $self->{'cpuser'} );
    }

    return 1;
}

#$data is a hashref of:
#   owner
#   server
#   noprefix - lookup hashref
#   dbs - lookup hashref
#   dbusers - hashref, values are hashes:
#       server
#       domain
#       dbs - lookup hashref
sub _build_owner {
    my ( $self, $cpuser, $data ) = @_;

    my $owner = Cpanel::DB::Map::Owner->new(
        {
            'cpuser' => $self->{'cpuser'},
            'db'     => $self->{'db'},
            'name'   => Cpanel::DB::Utils::username_to_dbowner( $data->{'owner'} ),
            'server' => $data->{'server'},
        }
    );

    foreach my $db ( keys %{ $data->{'dbs'} } ) {
        $owner->add_db($db);
    }

  DBUSER:
    foreach my $dbuser ( keys %{ $data->{'dbusers'} } ) {

        #This shouldn't happen in production, but it cropped up in development.
        #So, just in case.
        #NOTE: This will automatically remove the cpuser as a DB user from the
        #map file once we save this DB map with the new $owner.
        next DBUSER if $dbuser eq Cpanel::DB::Utils::username_to_dbowner( $self->{'cpuser'} );

        $owner->add_dbuser(
            {
                'dbuser' => $dbuser,
                'server' => exists $data->{'dbusers'}{$dbuser}{'server'}
                ? $data->{'dbusers'}{$dbuser}{'server'}
                : $data->{'dbusers'}{$dbuser}{'domain'},
            }
        );
        foreach my $db ( keys %{ $data->{'dbusers'}{$dbuser}{'dbs'} } ) {
            $owner->add_db_for_dbuser( $db, $dbuser );
        }

        foreach my $name ( keys %{ $data->{'noprefix'} } ) {
            $owner->no_prefix($name);
        }
    }

    return $owner;
}

# Returns the number of invalid usernames dropped.
sub _remove_invalid_dbusers {
    my ($self) = @_;

    my $dbusers_hr = $self->{'stash'};
    $dbusers_hr &&= $dbusers_hr->{ $self->{'db'} };
    $dbusers_hr &&= $dbusers_hr->{'dbusers'};

    my $dropped = 0;

    if ($dbusers_hr) {
        foreach my $dbuser ( keys %$dbusers_hr ) {

            # Don't remove the temporary users
            next if $dbuser =~ m{^\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E};

            # We simply drop the users here because there's no legitimate reason
            # to have these in the first place; the user must be up to no good.
            # See case 57326.
            if ( Cpanel::Validate::DB::User::reserved_username_check($dbuser) ) {
                delete $dbusers_hr->{$dbuser};
                $dropped++;
            }
        }
    }

    return $dropped;
}

sub db_exists {
    my ( $self, $name ) = @_;

    return exists $self->{'stash'}{ $self->{'db'} }{'dbs'}{$name} ? 1 : 0;
}

sub dbuser_exists {
    my ( $self, $name ) = @_;

    return exists $self->{'stash'}{ $self->{'db'} }{'dbusers'}{$name} ? 1 : 0;
}

sub get_dbs {
    my $self = shift;

    return keys %{ $self->{'stash'}{ $self->{'db'} }{'dbs'} };
}

sub get_dbusers {
    my $self = shift;

    return keys %{ $self->{'stash'}{ $self->{'db'} }{'dbusers'} };
}

#$args is a hashref passed to add_owner() if the owner doesn't already exist.
#If the owner already exists, $args is useless.
sub get_owner {
    my ( $self, $args ) = @_;
    my $cpuser = $self->{'cpuser'};

    if ( scalar keys %{ $self->{'stash'}{ $self->{'db'} } } ) {
        my $owner = $self->_build_owner( $cpuser, $self->{'stash'}{ $self->{'db'} } );

        if ($owner) {
            $self->{'owner'} = $owner;
            return $owner;
        }
    }
    else {
        return $self->add_owner($args);
    }
}

#$args is a hashref of:
#   owner
#   server
sub add_owner {
    my ( $self, $args ) = @_;

    my $owner = Cpanel::DB::Map::Owner->new(
        {
            'db'     => $self->{'db'},
            'cpuser' => $self->{'cpuser'} || '',
            'name'   => Cpanel::DB::Utils::username_to_dbowner( $args->{'owner'} || $self->{'cpuser'} ),
            'server' => $args->{'server'},
        }
    );
    $self->{'owner'} = $owner;
    return $owner;
}

sub db_type {
    my ($self) = @_;

    return $self->{'db'};
}

sub should_prefix {
    my ( $self, $name ) = @_;

    return ( exists $self->{'stash'}{ $self->{'db'} }{'noprefix'}{$name} ) ? 0 : 1;
}

#The name here is a bit confusing; it's really a check to see if a
#dbuser has (any) permissions on the DB.
sub user_owns_db {
    my ( $self, $dbuser, $dbobj ) = @_;
    my $stash = $self->{'stash'}{ $self->{'db'} };

    return undef if !exists $stash->{'dbs'}{$dbobj};

    #Does $dbuser have any rights on the $dbobj?
    return 1 if $stash->{'dbusers'}{$dbuser} && $stash->{'dbusers'}{$dbuser}{'dbs'}{$dbobj};

    #Is the $dbuser listed as the owner of this map?
    return 1 if $dbuser eq $self->cpuser();
    return 1 if $dbuser eq $self->name();
    return 1 if defined( $stash->{'owner'} ) && ( $dbuser eq $stash->{'owner'} );

    return 0;
}

#This checks that the dbuser exists in the map.
#
#NOTE: $user is actually irrelevant here. Worse, you could pass in garbage for
#both $user and $dbuser and get a false positive response. You might as well
#just pass in empty string.
#
sub user_owns_dbuser {
    my ( $self, $user, $dbuser ) = @_;

    return 1 if ( $user eq $dbuser || $dbuser eq $self->cpuser() || $dbuser eq $self->name() );

    my $stash = $self->{'stash'}{ $self->{'db'} };

    return 1 if exists $stash->{'dbusers'}{$dbuser};

    return;
}

sub users_by_server {
    my ( $self, $server ) = @_;
    my $stash = $self->{'stash'};

    my %users = ();

    foreach my $dbuser ( keys %{ $stash->{ $self->{'db'} }{'dbusers'} } ) {
        my $dbuser_server =
          exists $stash->{ $self->{'db'} }{'dbusers'}{$dbuser}{'server'}
          ? $stash->{ $self->{'db'} }{'dbusers'}{$dbuser}{'server'}
          : $stash->{ $self->{'db'} }{'dbusers'}{$dbuser}{'domain'};
        $users{$dbuser} = 1 if $dbuser_server eq $server;
    }
    return map { $self->{'owner'}->_find_user($_) } keys %users;
}

#NOTE: This will now throw an exception on error.
#Also, it will save AND close the DB map, so a subsequent save()
#will produce an error.
sub save {
    my ($self) = @_;
    $self->merge();
    $self->_save_file();
    return 1;
}

sub merge {
    my ($self) = @_;

    my $owner = $self->{'owner'};

    if ($owner) {
        $self->{'stash'}{ $self->{'db'} } = {
            'owner'   => $owner->name()   || $self->name(),
            'server'  => $owner->server() || $self->default_server(),
            'dbs'     => { map { $_->name() => $owner->server() || $self->default_server() } $owner->dbs() },
            'dbusers' => {
                map {
                    $_->name() => {
                        'server' => $_->server() || $self->default_server(),
                        'dbs'    => { map { $_->name() => $owner->server() || $self->default_server() } $_->dbs() },
                    }
                } $owner->dbusers()
            },
            'noprefix' => {
                map { $_ => 1 } $owner->no_prefix(),
            },
        };
    }
    else {
        Cpanel::Debug::log_warn('Owner did not exist for merge');
    }
    return;
}

my %server;

sub default_server {
    my ($self) = @_;

    return $server{ $self->{'db'} } if exists $server{ $self->{'db'} };

    if ( $self->{'db'} eq 'MYSQL' ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::MyCnf::Basic');
        $server{'MYSQL'} = Cpanel::MysqlUtils::MyCnf::Basic::get_server();
    }
    elsif ( $self->{'db'} eq 'PGSQL' ) {
        require Cpanel::PostgresUtils::PgPass;
        $server{'PGSQL'} = Cpanel::PostgresUtils::PgPass::get_server();
    }

    return $server{ $self->{'db'} };
}

sub _rename_owner_items {
    my ( $self, $getter_name, $oldname, $newname ) = @_;

    $self->get_owner() if !ref $self->{'owner'};
    my $owner = $self->{'owner'};

    for ( $owner->$getter_name() ) {
        next if $_->name() ne $oldname;
        $_->name($newname);
    }

    return 1;
}

sub rename_database {
    my ( $self, $oldname, $newname ) = @_;

    my $stash = $self->{'stash'}{ $self->{'db'} };

    my $dbs_hr = $stash->{'dbs'};

    #This should not happen in production.
    die "DB name “$newname” already exists in map!" if $dbs_hr->{$newname};

    my $ret = $self->_rename_owner_items( 'dbs', $oldname, $newname );

    $dbs_hr->{$newname} = delete $dbs_hr->{$oldname};

    my $dbusers_hr = $stash->{'dbusers'};
    while ( my ( $dbuser, $userstats_hr ) = each %$dbusers_hr ) {
        my $user_dbs_hr = $userstats_hr->{'dbs'};
        if ( exists $user_dbs_hr->{$oldname} ) {
            $user_dbs_hr->{$newname} = delete $user_dbs_hr->{$oldname};
        }
    }

    return $ret;
}

sub rename_dbuser {
    my ( $self, $oldname, $newname ) = @_;

    my $stash = $self->{'stash'}{ $self->{'db'} };

    my $dbusers_hr = $stash->{'dbusers'};

    #This should not happen in production.
    die "DBuser name “$newname” already exists in map!" if $dbusers_hr->{$newname};

    my $ret = $self->_rename_owner_items( 'dbusers', $oldname, $newname );

    $dbusers_hr->{$newname} = delete $dbusers_hr->{$oldname};

    return $ret;
}

1;

=pod

=head1 NAME

Cpanel::DB::Map

=head1 DESCRIPTION

    This is the main interface for the DB mapping functionality that gives access
    to Owner, User, and DB objects. It also provides limited querying of the objects
    that a cpanel user owns.

=head1 DIRECTORIES AND FILES

    Cpanel::DB::Map interacts with a datastore that represents the cpanel user's database
    users and databases. The implementation of this datastore is abstracted from the user
    (by design).

=head1 SYNOPSIS

   my $map   = Cpanel::DB::Map->new({ cpuser => $cpuser, db => 'MYSQL' });

   my $owner = $map->get_owner({owner => $dbuser, server => $server});

   # my $owner = $map->get_owner(); If the owner has already been created
   $owner->add_db($db);

   $map->save();

=head1 METHODS

=over

=item new(HASHREF)

=over 12

=item KEY: cpuser

=item KEY: db

=back

Instantiate new map object. Use database name constants for supported database values.

=item get_owner(OPTIONAL HASHREF)

=over 12

=item KEY: owner

=item KEY: server

=back

Get the database owner object. Pass the hashref as an argument if you want to create a database owner.

=item user_owns_db($user, $db)

Return boolean if $user owns $db

=item user_owns_dbuser($owner, $dbuser)

Returns boolean if $owner owns $dbuser

=item users_by_server($server)

Returns list of all users objects that match $server

=item save()

This saves the map and owner object to a yaml file

=item cpuser()

Returns the cpuser name

=item name()

Returns the dbuser name

=back

=cut
