package Whostmgr::Transfers::ConvertAddon::MigrateData::Mysql;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData/Mysql.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Whostmgr::Transfers::ConvertAddon::MigrateData);

use File::Spec                       ();
use Cpanel::Mysql                    ();
use Cpanel::DB::Map                  ();
use Cpanel::TempFile                 ();
use Cpanel::Exception                ();
use Cpanel::Mysql::Constants         ();
use Cpanel::MysqlUtils::Show         ();
use Cpanel::MysqlUtils::Connect      ();
use Cpanel::MysqlUtils::Stream       ();
use Cpanel::MysqlUtils::Grants       ();
use Cpanel::MysqlUtils::MyCnf::Basic ();

use Cpanel::MysqlUtils::RemoteMySQL::ProfileManager ();

sub new {
    my ( $class, $opts ) = @_;

    my $self = $class->SUPER::new($opts);

    $self->{'tmpfile_obj'}   = Cpanel::TempFile->new();
    $self->{'mysqldump_dir'} = $self->{'tmpfile_obj'}->dir();

    my $profile_manager = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new( { 'read_only' => 1 } );
    $profile_manager->validate_profile( $profile_manager->get_active_profile() );    # dies if profile is invalid

    my $active_profile = $profile_manager->read_profiles()->{ $profile_manager->get_active_profile() };
    $self->{'root_auth'} = {
        'dbuser' => $active_profile->{'mysql_user'},
        'dbpass' => $active_profile->{'mysql_pass'},
        'dbhost' => $active_profile->{'mysql_host'},
        'dbport' => $active_profile->{'mysql_port'},
    };

    return $self;
}

sub move_database {
    my ( $self, $opts_hr ) = @_;

    $self->_validate_required_params( 'move_database', $opts_hr );

    my $user_privs_to_preserve;
    if ( $opts_hr->{'user_privs_to_preserve'} && 'ARRAY' eq ref $opts_hr->{'user_privs_to_preserve'} ) {
        $user_privs_to_preserve = { map { $_ => 1 } @{ $opts_hr->{'user_privs_to_preserve'} } };
    }
    return $self->_remap_dbresource(
        {
            'type'                   => 'db',
            'resource_name'          => $opts_hr->{'dbname'},
            'user_privs_to_preserve' => $user_privs_to_preserve,
        }
    );
}

sub move_database_user {
    my ( $self, $opts_hr ) = @_;

    $self->_validate_required_params( 'move_database_user', $opts_hr );

    my $db_associations_to_preserve;
    if ( $opts_hr->{'db_associations_to_preserve'} && 'ARRAY' eq ref $opts_hr->{'db_associations_to_preserve'} ) {
        $db_associations_to_preserve = { map { $_ => 1 } @{ $opts_hr->{'db_associations_to_preserve'} } };
    }
    return $self->_remap_dbresource(
        {
            'type'                        => 'dbuser',
            'resource_name'               => $opts_hr->{'dbuser'},
            'db_associations_to_preserve' => $db_associations_to_preserve,
        }
    );
}

sub copy_database {
    my ( $self, $opts_hr ) = @_;

    $self->_validate_required_params( 'copy_database', $opts_hr );

    my $mysql_obj = Cpanel::Mysql->new( { cpuser => $self->{'to_username'} } );
    my ( $ok, $err ) = $mysql_obj->create_db( $opts_hr->{'new_dbname'} );
    die Cpanel::Exception->create( 'The system failed to create the database “[_1]”: [_2]', [ $opts_hr->{'new_dbname'}, $err ] )
      if !$ok;

    my @exceptions;

    # Cloning here cause we want the DBH to be
    # bound to the user's account instead of root.
    my $user_dbh = $mysql_obj->{'dbh'}->clone(
        {
            database               => $opts_hr->{'new_dbname'},
            mysql_multi_statements => 1,
            max_allowed_packet     => Cpanel::Mysql::Constants::MAX_ALLOWED_PACKET,
            Username               => $self->{'to_username'},
            Password               => $opts_hr->{'touser_dbpass'},
            PrintError             => 0,
            RaiseError             => 0,
        }
    );

    push @exceptions, $self->_copy_db_structure( $opts_hr->{'old_dbname'}, $user_dbh );
    push @exceptions, $self->_copy_db_data( $opts_hr->{'old_dbname'}, $user_dbh );
    push @exceptions, $self->_copy_db_routines( $opts_hr->{'old_dbname'}, $user_dbh );
    push @exceptions, $self->_copy_db_triggers( $opts_hr->{'old_dbname'}, $user_dbh );
    push @exceptions, $self->_copy_db_events( $opts_hr->{'old_dbname'}, $user_dbh );
    die Cpanel::Exception::create( 'Collection', 'The import of database “[_1]” had errors.', [ $opts_hr->{'new_dbname'} ], { exceptions => \@exceptions } ) if scalar @exceptions;

    return 1;
}

sub _copy_db_structure {
    my ( $self, $old_db, $user_dbh ) = @_;

    my $db_create_file = File::Spec->catfile( $self->{'mysqldump_dir'}, $old_db . '.create' );
    if ( open my $fh, '>', $db_create_file ) {
        Cpanel::MysqlUtils::Stream::stream_mysqldump_to_filehandle(
            {
                %{ $self->{'root_auth'} },
                'options' => [
                    '--no-data',
                    '--skip-routines',
                    '--skip-triggers',
                    '--skip-events',
                ],
                'db'         => $old_db,
                'filehandle' => $fh,
            }
        );
        close $fh;
    }
    else {
        return Cpanel::Exception->create( 'The system failed to export the table structure from the database “[_1]”: [_2]', [ $old_db, $! ] );
    }

    return _import_mysqldump_as_user( $user_dbh, $db_create_file );
}

sub _copy_db_data {
    my ( $self, $old_db, $user_dbh ) = @_;

    my $db_data_file = File::Spec->catfile( $self->{'mysqldump_dir'}, $old_db . '.data' );
    if ( open my $fh, '>', $db_data_file ) {
        Cpanel::MysqlUtils::Stream::stream_mysqldump_to_filehandle(
            {
                %{ $self->{'root_auth'} },
                'options' => [
                    '--no-create-info',
                    '--skip-routines',
                    '--skip-triggers',
                    '--skip-events',
                ],
                'db'         => $old_db,
                'filehandle' => $fh,
            }
        );
        close $fh;
    }
    else {
        return Cpanel::Exception->create( 'The system failed to export data from the database “[_1]”: [_2]', [ $old_db, $! ] );
    }

    return _import_mysqldump_as_user( $user_dbh, $db_data_file );
}

sub _copy_db_routines {
    my ( $self, $old_db, $user_dbh ) = @_;

    my $db_routines_file = File::Spec->catfile( $self->{'mysqldump_dir'}, $old_db . '.routines' );
    if ( open my $fh, '>', $db_routines_file ) {
        Cpanel::MysqlUtils::Stream::stream_mysqldump_to_filehandle(
            {
                %{ $self->{'root_auth'} },
                'options' => [
                    '--routines',
                    '--no-data',
                    '--no-create-info',
                    '--skip-triggers',
                    '--skip-events',
                ],
                'db'         => $old_db,
                'filehandle' => $fh,
            }
        );
        close $fh;
    }
    else {
        return Cpanel::Exception->create( 'The system failed to export data from the database “[_1]”: [_2]', [ $old_db, $! ] );
    }

    return _import_mysqldump_as_user( $user_dbh, $db_routines_file, $self->{'to_username'} );
}

sub _copy_db_triggers {
    my ( $self, $old_db, $user_dbh ) = @_;

    my $db_triggers_file = File::Spec->catfile( $self->{'mysqldump_dir'}, $old_db . '.triggers' );
    if ( open my $fh, '>', $db_triggers_file ) {
        Cpanel::MysqlUtils::Stream::stream_mysqldump_to_filehandle(
            {
                %{ $self->{'root_auth'} },
                'options' => [
                    '--triggers',
                    '--no-data',
                    '--no-create-info',
                    '--skip-routines',
                    '--skip-events',
                ],
                'db'         => $old_db,
                'filehandle' => $fh,
            }
        );
        close $fh;
    }
    else {
        return Cpanel::Exception->create( 'The system failed to export data from the database “[_1]”: [_2]', [ $old_db, $! ] );
    }

    return _import_mysqldump_as_user( $user_dbh, $db_triggers_file, $self->{'to_username'} );
}

sub _copy_db_events {
    my ( $self, $old_db, $user_dbh ) = @_;

    my $db_events_file = File::Spec->catfile( $self->{'mysqldump_dir'}, $old_db . '.events' );
    if ( open my $fh, '>', $db_events_file ) {
        Cpanel::MysqlUtils::Stream::stream_mysqldump_to_filehandle(
            {
                %{ $self->{'root_auth'} },
                'options' => [
                    '--events',
                    '--no-data',
                    '--no-create-info',
                    '--skip-routines',
                    '--skip-triggers',
                ],
                'db'         => $old_db,
                'filehandle' => $fh,
            }
        );
        close $fh;
    }
    else {
        return Cpanel::Exception->create( 'The system failed to export data from the database “[_1]”: [_2]', [ $old_db, $! ] );
    }

    return _import_mysqldump_as_user( $user_dbh, $db_events_file, $self->{'to_username'} );
}

sub _import_mysqldump_as_user {
    my ( $user_dbh, $file, $new_username ) = @_;

    # If the file is empty, then short circuit the call
    return if !-s $file;

    if ( open my $fh, '<', $file ) {

        my $cur_delimiter = ';';
        my $cur_statement;
        my @errors;
        while ( readline $fh ) {
            if ( my ($new_delimiter) = m{\ADELIMITER (\S+)\s*\z}i ) {
                if ( length $cur_statement && $cur_statement =~ m{\Q$cur_delimiter\E} ) {
                    push @errors, Cpanel::Exception->create(
                        'There is an error in the MySQL restore file “[_1]”: The buffer contained a statement ([_2]) that should have already been processed when a new delimiter was set to “[_3]”.',
                        [ $file, $cur_statement, $new_delimiter ]
                    );
                    last;
                }
                $cur_delimiter = $new_delimiter;
            }
            elsif ( m{^--} || m{^\s+$} ) {

                # ignore comments
            }
            else {
                $cur_statement .= $_;

                # Process the statements one at a time.
                if ( $cur_statement =~ m{\Q$cur_delimiter\E\n$} ) {
                    if ($new_username) {
                        my $id_quoted_newuser = $user_dbh->quote_identifier($new_username);
                        $cur_statement =~ s<DEFINER\s*=\s*`.+`\@(`.*?`)><DEFINER=$id_quoted_newuser\@$1>;
                    }
                    $user_dbh->do($cur_statement) or do {
                        push @errors, Cpanel::Exception->create( 'The [asis,MySQL] server reported an error ([_1]) in response to this request: [_2]', [ $user_dbh->errstr(), $cur_statement ] );
                    };
                    $cur_statement = '';
                }
            }
        }
        return @errors if @errors;
    }
    else {
        return Cpanel::Exception->create( 'The system failed to open the file “[_1]” because of an error: [_2]', [ $file, $! ] );
    }

    return;
}

sub _remap_dbresource {
    my ( $self, $opts_hr ) = @_;

    my $newuser_map = Cpanel::DB::Map->new( { 'cpuser' => $self->{'to_username'},   'db' => 'MYSQL' } );
    my $olduser_map = Cpanel::DB::Map->new( { 'cpuser' => $self->{'from_username'}, 'db' => 'MYSQL' } );

    my $server        = Cpanel::MysqlUtils::MyCnf::Basic::get_server();
    my $new_owner_obj = $newuser_map->get_owner( { 'name' => $self->{'to_username'},   'server' => $server } );
    my $old_owner_obj = $olduser_map->get_owner( { 'name' => $self->{'from_username'}, 'server' => $server } );

    if ( $opts_hr->{'type'} eq 'db' ) {
        $new_owner_obj->add_db( $opts_hr->{'resource_name'} );
        $old_owner_obj->remove_db( $opts_hr->{'resource_name'} );
    }
    elsif ( $opts_hr->{'type'} eq 'dbuser' ) {
        $new_owner_obj->add_dbuser( { 'dbuser' => $opts_hr->{'resource_name'}, 'server' => $server } );

        if ( $opts_hr->{'db_associations_to_preserve'} ) {
            my @dbs_to_add = grep { $opts_hr->{'db_associations_to_preserve'}->{$_} } map { $_->name } $old_owner_obj->dbuser( $opts_hr->{'resource_name'} )->dbs();
            $new_owner_obj->add_db_for_dbuser( $_, $opts_hr->{'resource_name'} ) for @dbs_to_add;
        }

        $old_owner_obj->remove_dbuser( $opts_hr->{'resource_name'} );
    }
    else {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid database resource type', [ $opts_hr->{'type'} ] );    ## no extract maketext (developer error message. no need to translate)
    }

    $newuser_map->save();
    $olduser_map->save();
    $self->_fix_grants($opts_hr);

    return 1;
}

sub _fix_grants {
    my ( $self, $opts_hr ) = @_;

    my $dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle();

    my $old_mysql_obj = Cpanel::Mysql->new( { cpuser => $self->{'from_username'} } );

    if ( $opts_hr->{'type'} eq 'db' ) {
        my $user_mysql_obj = Cpanel::Mysql->new( { cpuser => $self->{'to_username'} } );
        my $grants         = Cpanel::MysqlUtils::Show::show_grants_on_dbs( $dbh, $opts_hr->{'resource_name'} );
        foreach my $grant ( @{$grants} ) {
            next if $grant->db_name eq '*';
            next if ( $opts_hr->{'user_privs_to_preserve'} && $opts_hr->{'user_privs_to_preserve'}->{ $grant->db_user } );
            $old_mysql_obj->deluserfromdb_if_not_exists( $opts_hr->{'resource_name'}, $grant->db_user );
        }
        $old_mysql_obj->deluserfromdb_if_not_exists( $opts_hr->{'resource_name'}, $self->{'from_username'} );
        $user_mysql_obj->updateprivs( $opts_hr->{'resource_name'} );
    }
    elsif ( $opts_hr->{'type'} eq 'dbuser' ) {
        my $grants = Cpanel::MysqlUtils::Grants::show_grants_for_user( $dbh, $opts_hr->{'resource_name'} );
        foreach my $grant ( @{$grants} ) {
            next if $grant->db_name eq '*';
            next if ( $opts_hr->{'db_associations_to_preserve'} && $opts_hr->{'db_associations_to_preserve'}->{ $grant->db_name } );
            $old_mysql_obj->deluserfromdb_if_not_exists( $grant->db_name, $opts_hr->{'resource_name'} );
        }
    }

    return 1;
}

# Note: this does not validate whether
# the databases belong to the users or not.
# That is left up to the caller.
sub _validate_required_params {
    my ( $self, $operation, $opts ) = @_;

    $self->ensure_users_exist();

    if ( !( $opts && 'HASH' eq ref $opts ) ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] detailing the data migration' );    ## no extract maketext (developer error message. no need to translate)
    }

    my $required_params = {
        'copy_database'      => [qw(old_dbname new_dbname touser_dbpass)],
        'move_database'      => [qw(dbname)],
        'move_database_user' => [qw(dbuser)],
    };

    my @exceptions;
    foreach my $required_arg ( @{ $required_params->{$operation} } ) {
        if ( not defined $opts->{$required_arg} ) {
            push @exceptions, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_arg] );
        }
    }

    die Cpanel::Exception::create( 'Collection', 'Invalid or Missing required parameters', [], { exceptions => \@exceptions } ) if scalar @exceptions;
    return 1;
}

1;
