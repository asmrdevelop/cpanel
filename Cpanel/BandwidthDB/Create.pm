package Cpanel::BandwidthDB::Create;

# cpanel - Cpanel/BandwidthDB/Create.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This class creates a new bandwidth summary datastore in the
# current schema. It does not populate said datastore, though the class
# is a subclass of Write, so instances can be used easily to populate
# the datastore.
#
# To ensure race safety, this creates a temp file first. Only when you
# install() this object is it moved into place. This guarantees that
# no reader object will ever see the database before the schema is set up.
#
# A typical use pattern is:
#
#   my $bwdb = Cpanel::BandwidthDB::Create->new($controlling_user);
#
#   #Import useful information ...
#
#   #Now that we’ve imported the data, we’re ready to be “public”.
#   $bwdb->install();
#
#   #This DESTROY will unlink the original filename.
#   #Note that, if we don’t install() before doing this,
#   #all imported data will be LOST beyond this point.
#   undef $bwdb;
#
# NOTE: The above use pattern is found in C<Cpanel::BandwidthDB>’s functions,
# which may suit your needs better than instantitating this module directly.
#
#----------------------------------------------------------------------

use strict;

use base qw(
  Cpanel::BandwidthDB::Write
);

use Try::Tiny;

use DBD::SQLite  ();
use Umask::Local ();

use Cpanel::AccessIds::Normalize         ();
use Cpanel::Autodie                      ();
use Cpanel::BandwidthDB::Base            ();
use Cpanel::BandwidthDB::Constants       ();
use Cpanel::BandwidthDB::Schema          ();
use Cpanel::CommandQueue                 ();
use Cpanel::FileUtils::RaceSafe::SQLite  ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Validate::Username           ();

my $USER_DB_DIR_PERMS = 0750;

#----------------------------------------------------------------------
#STATIC METHODS

sub rename_database_for_user {
    my ( $old_username, $new_username ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($_) for ( $old_username, $new_username );

    my $old_path = Cpanel::BandwidthDB::Base->_name_to_path($old_username);
    my $new_path = Cpanel::BandwidthDB::Base->_name_to_path($new_username);

    my $queue = Cpanel::CommandQueue->new();
    $queue->add(
        sub {
            Cpanel::Autodie::link( $old_path, $new_path );
        },
        sub {
            Cpanel::Autodie::unlink($new_path);
        },
        'unlink new path',
    );

    $queue->add(
        sub {
            Cpanel::Autodie::unlink($old_path);
        },
    );

    $queue->run();

    return 1;
}

#----------------------------------------------------------------------

#Parameters (given in a hashref) match those for Cpanel::BandwidthDB::Write.
#
sub new {
    my ( $class, $username, @domains ) = @_;

    #Have this allow system users for ease of testing.
    #It might be better eventually to make it require a cpuser.
    Cpanel::Validate::Username::user_exists_or_die($username);

    my $self = do {
        my $umask = Umask::Local->new( 0777 - $Cpanel::BandwidthDB::Constants::DB_FILE_PERMS );
        $class->SUPER::new($username);
    };

    $self->_init_tables(@domains);

    return $self;
}

#Override parent class. There’s no schema at all on instantiation here,
#so we need to be able to create it.
sub _check_for_outdated_schema { }

#overrides parent class
sub _create_dbh {
    my ($self) = @_;

    $self->{'_safe_sqlitedb'} = Cpanel::FileUtils::RaceSafe::SQLite->new(
        path => $self->_name_to_path( $self->get_attr('username') ),
    );

    return $self->{'_safe_sqlitedb'}->dbh();
}

sub _init_tables {
    my ( $self, @domains ) = @_;

    my $dbh = $self->{'_dbh'};

    Cpanel::BandwidthDB::Schema::create_schema(
        $dbh,
        $Cpanel::BandwidthDB::Constants::SCHEMA_VERSION,
    );

    for my $moniker (@domains) {
        $self->_create_tables_for_moniker($moniker);
    }

    return;
}

#See Cpanel::FileUtils::RaceSafe::Base for more information about these
#two functions.
#
#NOTE: Until you install() or force_install(), the datastore will not be live!
#
sub install {
    my $self = shift;
    return $self->_install('install');
}

sub force_install {
    my $self = shift;
    return $self->_install('force_install');
}

sub _install {
    my ( $self, $sqlitedb_method ) = @_;

    my $filename = $self->{'_dbh'}->sqlite_db_filename();
    die 'no filename!' if !length $filename;

    my $new_path = $self->_name_to_path( $self->get_attr('username') );

    #Now extend read privileges on the file to the group.
    my ( undef, $gid ) = Cpanel::AccessIds::Normalize::normalize_user_and_groups( 0, $self->get_attr('username') );

    #First create the new link. This will fail if the datastore already exists.
    my $queue = Cpanel::CommandQueue->new();
    $queue->add(
        sub {
            # Ex: Cpanel::FileUtils::RaceSafe::Base->install() or
            # Cpanel::FileUtils::RaceSafe::Base->force_install()
            $self->{'_safe_sqlitedb'}->$sqlitedb_method();
        },
        sub {
            Cpanel::Autodie::unlink($new_path);
        },
    );

    #Then, extend read access to the user.
    $queue->add(
        sub {
            Cpanel::Autodie::chown( -1, $gid, $filename );
        },
    );

    #NOTE: We do NOT unlink() the old path here because this object may still
    #interact with the DB using its old filename.

    $queue->run();

    undef $self->{'_safe_sqlitedb'};    #will unlink the temp file

    return 1;
}

1;
