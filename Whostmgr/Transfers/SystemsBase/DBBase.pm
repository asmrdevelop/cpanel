package Whostmgr::Transfers::SystemsBase::DBBase;

# cpanel - Whostmgr/Transfers/SystemsBase/DBBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This is a base module. See one of its subclasses to do real work.
#----------------------------------------------------------------------

use strict;

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Validate::DB::Name           ();
use Cpanel::Validate::DB::User           ();
use Cpanel::Locale                       ();
use Cpanel::DB::Utils                    ();
use Cpanel::Carp                         ();
use Cpanel::DB::Map                      ();
use Cpanel::DB::Map::Setup               ();
use Cpanel::DB::Map::Utils               ();
use Cpanel::DB::Map::Reader              ();
use Cpanel::NameVariant                  ();
use Cpanel::SafeSync::UserDir            ();

my %MAP_ENGINE_TO_NEW = qw(
  MYSQL   mysql
  PGSQL   postgresql
);

use base qw(
  Whostmgr::Transfers::Systems
);

sub disable_options {
    return [ 'all', 'databases' ];
}

sub _init {
    my ($self) = @_;

    $self->{'_dbname_updates'} = {};
    $self->{'_dbuser_updates'} = {};

    # For testing
    $self->{'_restored_databases'} = {};
    $self->{'_restored_dbusers'}   = {};
    $self->{'_restored_grants'}    = [];
    $self->{'_old_cpuser'}         = $self->olduser();

    # Make sure /var/cpanel/databases is there and has the right permissions
    Cpanel::DB::Map::Setup::initialize();

    return ( 1, $self );
}

#named options:
#   name => required, the original name
#   statement => required, the DBI statement to test a name's validity
#       If this returns a result, that means NOT to accept the tested name.
#       The name to check will bind to each variable in the statement.
#   max_length => required (in bytes)
#   exclude => optional, arrayref of names to reject
#
sub _find_unique_name_variant {
    my ( $self, %opts ) = @_;

    my $stmt = $opts{'statement'};

    #Be sure to try the original name from the archive.
    $opts{'exclude'} = [ @{ $opts{'exclude'} } ];

    return Cpanel::NameVariant::find_name_variant(
        %opts,
        test => sub {
            my $variant = shift;

            $stmt->execute( ($variant) x $stmt->{NUM_OF_PARAMS} );

            if ( !$stmt->fetchrow_arrayref() ) {
                if ( $stmt->err() ) {
                    die 'ERROR while checking for duplicates: ' . $stmt->err();
                }

                return 1;
            }

            return 0;
        },
    );
}

# Handle overwrite requests
sub _determine_dbuser_updates_for_restore_and_overwrite {
    my ($self) = @_;

    $self->{'_overwrite_all_dbusers'}       = 0;
    $self->{'_overwrite_sameowner_dbusers'} = 0;
    my $newuser         = $self->newuser();
    my $dbowner         = Cpanel::DB::Utils::username_to_dbowner($newuser);
    my $olduser         = $self->olduser();
    my $old_dbowner     = Cpanel::DB::Utils::username_to_dbowner($olduser);
    my $is_unrestricted = $self->{'_utils'}->is_unrestricted_restore() ? 1 : 0;
    my $flags           = $self->{'_utils'}->{'flags'};

    if ( $flags->{'overwrite_all_dbusers'} ) {
        if ($is_unrestricted) {
            $self->{'_overwrite_all_dbusers'} = 1;
            $self->out( _locale()->maketext('Database users will be overwritten on conflict.') );
        }
        else {
            $self->{'_overwrite_sameowner_dbusers'} = 1;
            $self->out( _locale()->maketext( 'Database users owned by “[_1]” will be overwritten on conflict instead of all users because the system is operating in restricted mode.', $newuser ) );
        }
    }
    elsif ( $flags->{'overwrite_sameowner_dbusers'} ) {
        $self->{'_overwrite_sameowner_dbusers'} = 1;
        $self->out( _locale()->maketext( 'Database users owned by “[_1]” will be overwritten on conflict.', $newuser ) );
    }

    $self->{'_system_dbuser_owner'} = {};

    foreach my $dbuser ( keys %{ $self->{'_dbuser_updates'} } ) {

        #i.e., without any overwrite setting, would this user be restored
        #with a different name?
        my $dbuser_differs = ( $dbuser ne $self->new_dbuser_name($dbuser) ) ? 1 : 0;

        if ( $self->{'_overwrite_all_dbusers'} ) {
            $self->_set_overwrite_dbuser($dbuser);
            if ( $dbuser_differs && !$self->_cpuser_owns_dbuser($dbuser) ) {
                $self->{'_system_dbuser_owner'}{$dbuser} = Cpanel::DB::Map::Utils::get_cpuser_for_engine_dbuser( $self->map_engine(), $dbuser );
            }
        }
        elsif ( $self->{'_overwrite_sameowner_dbusers'} ) {
            if ( $self->_cpuser_owns_dbuser($dbuser) || $dbuser eq $dbowner ) {
                $self->_set_overwrite_dbuser($dbuser);
            }
            elsif ($dbuser_differs) {
                $self->out( _locale()->maketext( "The system will restore the database user “[_1]” as “[_2]” because another cPanel user owns “[_1]”.", $dbuser, $self->new_dbuser_name($dbuser) ) );
            }
        }
    }

    return 1;
}

#This function is very specific to the context of restoring grants. It:
#   - checks to see if the given DB is to be restored
#   - warns about non-grant-restoration IF the DB was to be restored.
#
#Note that this does NOT give the grant's user nor the privileges granted.
#
#It returns 1 if the DB was/is restored, and 0 if not.
sub _check_if_db_is_restored_and_warn_about_non_grant_restoration {
    my ( $self, $old_db_name ) = @_;

    return 1 if length $self->new_dbname_name($old_db_name);

    #Only show this message if we didn't give a list of specific DBs
    #to restore or if this DB is in the list that was given.
    my $given_dbs_to_restore = $self->_given_dbs_to_restore();
    if ( !$given_dbs_to_restore || grep { $_ eq $old_db_name } @$given_dbs_to_restore ) {
        $self->{'_utils'}->add_dangerous_item( _locale()->maketext( 'The archive contains a grant for the database “[_1]”, but the archive does not contain that database itself. The system will not restore this grant.', $old_db_name ) );
    }

    return 0;
}

sub _given_dbs_to_restore {
    my ($self) = @_;

    return $self->{'_given_dbs_to_restore'};
}

# Handle overwrite requests
sub _determine_dbname_updates_for_restore_and_overwrite {
    my ($self) = @_;

    $self->{'_overwrite_all_dbs'}       = 0;
    $self->{'_overwrite_sameowner_dbs'} = 0;

    my $newuser                   = $self->newuser();
    my $dbs_to_restore_engine_key = lc( $self->map_engine() ) . "_dbs_to_restore";
    my $dbs_to_restore;

    my $is_unrestricted = $self->{'_utils'}->is_unrestricted_restore() ? 1 : 0;
    my $flags           = $self->{'_utils'}->{'flags'};

    if ( $flags->{'overwrite_all_dbs'} ) {
        if ($is_unrestricted) {
            $self->{'_overwrite_all_dbs'} = 1;
            $self->out( _locale()->maketext('Databases will be overwritten on conflict.') );
        }
        else {
            $self->{'_overwrite_sameowner_dbs'} = 1;
            $self->out( _locale()->maketext( 'Databases owned by “[_1]” will be overwritten on conflict instead of all users because the system is operating in restricted mode.', $newuser ) );
        }
    }
    elsif ( $flags->{'overwrite_sameowner_dbs'} ) {
        $self->{'_overwrite_sameowner_dbs'} = 1;
        $self->out( _locale()->maketext( 'Databases owned by “[_1]” will be overwritten on conflict.', $newuser ) );
    }
    elsif ( $is_unrestricted && $flags->{$dbs_to_restore_engine_key} ) {
        $dbs_to_restore = $flags->{$dbs_to_restore_engine_key};
        if ( !ref $dbs_to_restore ) {
            $dbs_to_restore = [ split( m{,}, $dbs_to_restore ) ];
        }
        $self->{'_given_dbs_to_restore'} = $dbs_to_restore;
        $self->out( _locale()->maketext( 'Database restoration will be limited to the following databases: [list_and_quoted,_1]', $dbs_to_restore ) );
    }

    foreach my $dbname ( keys %{ $self->{'_dbname_updates'} } ) {

        if ( $self->{'_overwrite_all_dbs'} ) {
            $self->_set_overwrite_db($dbname);
        }
        elsif ( $self->{'_overwrite_sameowner_dbs'} ) {
            my $dbname_differs = ( $dbname ne $self->new_dbname_name($dbname) ) ? 1 : 0;
            if ( $self->_cpuser_owns_db($dbname) ) {
                $self->_set_overwrite_db($dbname);
            }
            elsif ($dbname_differs) {
                $self->out( _locale()->maketext( "The system will restore the database “[_1]” as “[_2]” because another cPanel user owns “[_1]”.", $dbname, $self->new_dbname_name($dbname) ) );
            }
        }
        elsif ($dbs_to_restore) {
            my $should_restore_and_overwrite = ( grep { $dbname eq $_ } @{$dbs_to_restore} ) ? 1 : 0;
            if ($should_restore_and_overwrite) {
                $self->_set_overwrite_db($dbname);
            }
            else {
                $self->set_skip_db($dbname);
            }
        }
    }

    return 1;
}

sub _get_new_dbuser_names {
    my ($self) = @_;

    die "Too early to call this!" if !$self->{'_dbuser_updates'};

    return values %{ $self->{'_dbuser_updates'} };
}

sub _set_overwrite_dbuser {
    my ( $self, $dbuser ) = @_;

    # Always setup as the target
    if ( $self->{'_dbuser_updates'}{$dbuser} && $self->{'_dbuser_updates'}{$dbuser} eq $dbuser ) {
        return 1;
    }
    elsif ( Cpanel::Validate::DB::User::reserved_username_check($dbuser) ) {
        $self->warn( _locale()->maketext( "The database user “[_1]” will be renamed to “[_2]” even though overwrite was requested because it is a reserved name.", $dbuser, $self->new_dbuser_name($dbuser) ) );
        return 0;
    }

    $self->{'_dbuser_updates'}{$dbuser} = $dbuser;
    return 1;
}

sub _get_new_db_names {
    my ($self) = @_;

    die "Too early to call this!" if !$self->{'_dbname_updates'};

    return values %{ $self->{'_dbname_updates'} };
}

sub _set_overwrite_db {
    my ( $self, $dbname ) = @_;

    # Always setup as the target
    if ( $self->{'_dbname_updates'}{$dbname} && $self->{'_dbname_updates'}{$dbname} eq $dbname ) {
        return 1;
    }

    if ( Cpanel::Validate::DB::Name::reserved_database_check($dbname) ) {
        $self->warn( _locale()->maketext( "The database “[_1]” will be renamed to “[_2]” even though overwrite was requested because it is a reserved name.", $dbname, $self->new_dbname_name($dbname) ) );
        return 0;
    }

    $self->{'_dbname_updates'}{$dbname} = $dbname;
    return 1;
}

sub _cpuser_owns_db {
    my ( $self, $dbname ) = @_;

    return $self->_init_dbmap_read()->database_exists($dbname);
}

sub _cpuser_owns_dbuser {
    my ( $self, $dbuser ) = @_;

    $self->_init_dbmap_read();

    return $self->_init_dbmap_read()->dbuser_exists($dbuser) ? 1 : 0;
}

sub _init_dbmap_read {
    my ($self) = @_;

    #Create a DB map file if it doesn’t already exist on the system.
    if ( !Cpanel::DB::Map::Reader::cpuser_exists( $self->newuser() ) ) {
        Cpanel::DB::Map->new_allow_create( { cpuser => $self->newuser() } );
    }

    #This attribute is accessed directly via tests.
    return $self->{'_map_read'} ||= Cpanel::DB::Map::Reader->new( cpuser => $self->newuser(), engine => $MAP_ENGINE_TO_NEW{ $self->map_engine() } );
}

sub set_skip_db {

    my ( $self, $dbname ) = @_;
    $self->{'_dbname_updates'}{$dbname} = undef;
    return 1;
}

sub should_skip_db {
    my ( $self, $dbname ) = @_;

    return defined( $self->{'_dbname_updates'}{$dbname} ) ? 0 : 1;
}

sub _archive_dbnames {
    my ($self) = @_;

    die "Too early to call this!" if !defined $self->{'_dbname_updates'};

    return keys %{ $self->{'_dbname_updates'} };
}

#If this returns undef, that means either
sub get_preexisting_system_dbuser_owner {
    my ( $self, $dbuser ) = @_;

    die "Too early to call this!" if !$self->{'_system_dbuser_owner'};

    #This should already have been checked for.
    die "Nonexistent dbuser: $dbuser" if !exists $self->{'_system_dbuser_owner'}{$dbuser};

    return $self->{'_system_dbuser_owner'}{$dbuser};
}

sub system_already_has_dbuser_with_name {
    my ( $self, $dbuser ) = @_;

    die "Too early to call this!" if !$self->{'_system_dbuser_owner'};

    return exists $self->{'_system_dbuser_owner'}{$dbuser} ? 1 : 0;
}

sub new_dbuser_name {
    my ( $self, $old_dbuser_name ) = @_;

    die "Too early to call this!" if !defined $self->{'_dbuser_updates'};
    if ( !exists $self->{'_dbuser_updates'}{$old_dbuser_name} ) {

        # Should never happen
        die Cpanel::Carp::safe_longmess("The new dbuser name for “$old_dbuser_name” was unexpectedly missing.");
    }

    return $self->{'_dbuser_updates'}{$old_dbuser_name};
}

sub new_dbname_name {
    my ( $self, $old_dbname_name ) = @_;

    die "Too early to call this!" if !defined $self->{'_dbname_updates'};
    if ( !exists $self->{'_dbname_updates'}{$old_dbname_name} ) {

        # Should never happen
        die Cpanel::Carp::safe_longmess("The new database name for “$old_dbname_name” was unexpectedly missing.");
    }

    return $self->{'_dbname_updates'}{$old_dbname_name};
}

#A hashref of $archived_dbname => $dbname_updates
sub restored_databases {
    my ($self) = @_;

    my %copy = %{ $self->{'_restored_databases'} };
    return \%copy;
}

#A hashref of $archived_dbname => $dbname_updates
sub restored_dbusers {
    my ($self) = @_;

    my %copy = %{ $self->{'_restored_dbusers'} };
    return \%copy;
}

sub restored_grants {
    my ($self) = @_;

    my @copy = @{ $self->{'_restored_grants'} };
    return \@copy;
}

sub save_databases_in_homedir {
    my ( $self, $source_dir ) = @_;

    return if $self->{'saved_failed_databases'};
    $self->{'saved_failed_databases'} = 1;

    my $time       = time();
    my $target_dir = $self->{'_utils'}->homedir() . "/cpmove_failed_${source_dir}_dbs.$time";
    my $newuser    = $self->newuser();
    my $extractdir = $self->extractdir();
    my $err;

    if ( Cpanel::AccessIds::ReducedPrivileges::call_as_user( sub { return mkdir( $target_dir, 0700 ); }, $newuser ) ) {
        my ( $uid, $gid ) = ( $self->{'_utils'}->pwnam() )[ 2, 3 ];
        if (
            Cpanel::SafeSync::UserDir::sync_to_userdir(
                'source' => "$extractdir/$source_dir",
                'target' => $target_dir,
                'setuid' => [ $uid, $gid ]
            )
        ) {
            $self->warn( _locale()->maketext( "The system has saved the database archive data in the directory “[_1]”. You may use this directory’s contents to restore your data manually.", $target_dir ) );
        }
        else {
            $err = _locale()->maketext( "The system attempted to save the database archive data to the directory “[_1]” for you to restore your data manually; however, the system failed to save this data.", $target_dir );
        }
    }
    else {
        $err = _locale()->maketext( "The system attempted to create a directory “[_1]” for you to save your data manually, but the system failed to create this directory because of an error: [_2]", $target_dir, $! );
    }

    if ($err) {
        $self->warn($err);
        return ( 0, $err );
    }

    return ( 1, 'ok' );
}

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

1;
