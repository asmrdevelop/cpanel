package Whostmgr::DB::ApplyPrefix;

# cpanel - Whostmgr/DB/ApplyPrefix.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::DB::Map::Reader    ();
use Cpanel::Exception          ();
use Cpanel::DB::Prefix         ();
use Cpanel::LoadModule         ();
use Cpanel::NameVariant        ();
use Cpanel::Session::Constants ();
use Cpanel::Validate::DB::Name ();
use Cpanel::Validate::DB::User ();

my %DB_MAP_TYPE_ADMIN_MODULE = qw(
  mysql         Cpanel::Mysql
  postgresql    Cpanel::PostgresAdmin
);

my %RENAME_METHOD = qw(
  user        rename_dbuser
  database    rename_database
);

my %MAX_NAME_LENGTH = (
    mysql => {
        user     => undef,
        database => $Cpanel::Validate::DB::Name::max_mysql_dbname_length,
    },
    postgresql => {
        user     => $Cpanel::Validate::DB::User::max_pgsql_dbuser_length,
        database => $Cpanel::Validate::DB::Name::max_pgsql_dbname_length,
    },
);

#This function renames all prefixed DBs and DBusers so that they'll match
#the new prefix: e.g., if user "bob" is renamed to "scoobydoo" and the user
#has DBs "bob_marley", "al_gore", and "franz", the first two will become
#"scoobydo_marley" and "scoobydo_gore", but "franz" will remain.
#
#This returns a list of hashrefs like:
#   {
#       engine => 'mysql' or 'postgresql',
#       type   => 'user' or 'database',
#       old_name => '..',
#       new_name => '..',
#       status => 0 or 1,
#       error => Cpanel::Exception instance, or undef on success,
#   }
#
#This is done after Modify Account if DB prefixing is enabled in cpanel.config;
#it may be useful in other contexts, so we expose it here.
#
#NOTE: This MUST be called AFTER renaming the user because it will do a DB map
#lookup based on the NEW username.
#
#NOTE: This DOES NOT CARE whether prefixing is enabled on the server.
#
#FIXME: This logic is less than ideal because it reads all the files twice:
#once in read-only mode, then again when it actually does the rename. It would
#be ideal to have this logic in the actual DB admin modules that coordinate the
#rename between the map and the DB engine, which would obviate the need for two
#reads of the datastore.
#
sub synchronize_database_prefixes {
    my ($username) = @_;

    my $PREFIX_LENGTH = Cpanel::DB::Prefix::get_prefix_length();
    return _replace_pattern_with_prefix_for_user( qr<\A[^_]{1,$PREFIX_LENGTH}_>, $username );
}

sub _get_mysql_max_name_length {
    return $MAX_NAME_LENGTH{'mysql'}{'user'} ||= Cpanel::Validate::DB::User::get_max_mysql_dbuser_length();
}

sub _replace_pattern_with_prefix_for_user {
    my ( $pattern, $user ) = @_;

    my @renames;

    _get_mysql_max_name_length();

  DBTYPE:
    for my $engine ( sort keys %MAX_NAME_LENGTH ) {
        my $map = Cpanel::DB::Map::Reader->new( engine => $engine, cpuser => $user );

        #These keys correspond to methods in the DBAdmin classes.
        my %rename = (
            user     => [ $map->get_dbusers() ],
            database => [ $map->get_databases() ],
        );

        _convert_rename_to_oldnew_names( \%rename, $pattern, $user, $engine );

        #Since cPanel creates a role for each PostgreSQL DB,
        #we can't overlap DBusers and DBs in PostgreSQL.
        _make_names_unique( \%rename, $engine );

        next DBTYPE if !grep { %$_ } values %rename;

        push @renames, _perform_renames( \%rename, $engine, $user );
    }

    return @renames;
}

sub _convert_rename_to_oldnew_names {
    my ( $rename_ref, $pattern, $user, $dbengine ) = @_;

    my $new_prefix = Cpanel::DB::Prefix::username_to_prefix($user) . '_';

    _get_mysql_max_name_length();

    #Convert the %rename values to hashrefs of old => new names.
    #At this point, the names are NOT necessarily unique/final.
    for my $type ( keys %{$rename_ref} ) {
        my $map_items_ar = $rename_ref->{$type};

        my %old_to_new;
        for my $item_name (@$map_items_ar) {

            #Ignore temp session users.
            next if $type eq 'user' && $item_name =~ m<\A\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E>;

            my $name = $item_name;

            $name =~ s<$pattern><$new_prefix>;
            $name = substr( $name, 0, $MAX_NAME_LENGTH{$dbengine}{$type} );

            #Make undef entries for things we aren't renaming so that,
            #below, we know how not to create conflicts with pre-existing
            #DBs/users.
            if ( $name ne $item_name ) {
                $old_to_new{$item_name} = $name;
            }
            else {
                $old_to_new{$item_name} = undef;
            }
        }

        $rename_ref->{$type} = \%old_to_new;
    }

    return 1;
}

#The new names we assign should neither currently exist nor
#be already planned as a new name. This block will ensure that
#the new names don't conflict with any names of the DB server's
#existing objects.
sub _make_names_unique {
    my ( $rename_ref, $dbengine ) = @_;

    _get_mysql_max_name_length();

    my %name_is_used;

    #If PostgreSQL, prohibit user and DB from having the same name.
    if ( $dbengine eq 'postgresql' ) {
        for my $pgsql_old_to_new_hr ( values %$rename_ref ) {
            for my $old ( keys %$pgsql_old_to_new_hr ) {
                if ( !defined $pgsql_old_to_new_hr->{$old} ) {
                    $name_is_used{$old} = 1;
                }
            }
        }
    }

    #NOTE: Sorting is to ensure uniformity in renaming.
    for my $type ( sort keys %$rename_ref ) {
        my $old_to_new_hr = $rename_ref->{$type};

        if ( $dbengine ne 'postgresql' ) {
            %name_is_used = ();
        }

        #NOTE: Sorting is to ensure uniformity in renaming.
        #We have to sort by the keys, not the values, since many of the
        #values may be the same (currently).
      NEWNAME:
        for my $oldname ( sort keys %$old_to_new_hr ) {
            my $newname = $old_to_new_hr->{$oldname};

            #Above, we use undef for things we aren't renaming.
            next NEWNAME if !defined $newname;

            $newname = Cpanel::NameVariant::find_name_variant(
                name       => $newname,
                max_length => $MAX_NAME_LENGTH{$dbengine}{$type},
                test       => sub {
                    return 0 if $name_is_used{$_};
                    if ( exists $old_to_new_hr->{$_} ) {
                        return 0 if !defined $old_to_new_hr->{$_};
                        return 0 if $old_to_new_hr->{$_} ne $_;
                    }

                    return 1;
                },
            );

            $name_is_used{$newname} = 1;

            #This updates $rename_ref.
            $old_to_new_hr->{$oldname} = $newname;
        }
    }

    return 1;
}

sub _perform_renames {
    my ( $rename_ref, $dbengine, $user ) = @_;

    my @renames;

    my $admin_class = $DB_MAP_TYPE_ADMIN_MODULE{$dbengine};
    Cpanel::LoadModule::load_perl_module($admin_class);
    my $admin_obj = $admin_class->new( { cpuser => $user } );

    for my $type ( keys %$rename_ref ) {
        my $oldnew_hr = $rename_ref->{$type};

        my $method = $RENAME_METHOD{$type};

        my @rename_entry_parts = (
            engine => $dbengine,
            type   => ( $type eq 'dbuser' ) ? 'user' : $type,
        );

      OLDNEW:
        for my $old ( keys %$oldnew_hr ) {
            my $new = $oldnew_hr->{$old};

            next OLDNEW if !defined $new;

            my %rename_entry = (
                @rename_entry_parts,
                old_name => $old,
                new_name => $new,
            );

            #Use eval rather than try/catch here because
            #as of 11.44, it's significantly faster in a loop.
            #
            local $@;
            my $ok = eval {
                $admin_obj->$method( $old, $new );
                @rename_entry{qw( status error )} = ( 1, undef );
                1;
            };
            if ( !$ok ) {
                @rename_entry{qw( status error )} = ( 0, Cpanel::Exception::get_string($@) );
            }

            push @renames, \%rename_entry;
        }
    }
    return @renames;
}

1;
