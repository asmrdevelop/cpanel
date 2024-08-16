package Install::CheckcPHulkDB;

# cpanel - install/CheckcPHulkDB.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use parent qw( Cpanel::Task );

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Exception       ();
use Cpanel::LoadModule      ();
use Cpanel::Config::Hulk    ();
use Cpanel::SafeRun::Object ();
use Cpanel::Hulk::Admin::DB ();

our $VERSION = '1.0';

=head1 NAME

Install::CheckcPHulkDB - upcp post-install task module for checking the cPHulk database.

=head1 DESCRIPTION

This Cpanel::Task module checks the cPHulk database for corruption, and rebuilds it if needed.

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: Always

=item EOL: never

=back

=cut

=head1 METHODS

=head2 new()

Constructor for Install::CheckcPHulkDB objects.

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('check_cphulk_database');

    return $self;
}

=head2 perform()

Method to do the actual work of the Install::CheckcPHulkDB task.

This does nothing if cPHulk is not enabled on the server. Otherwise...

It checks to see if the cPHulk DB is corrupt. If the DB is corrupt, then it
will stop the cPHulk service, rename the existing database if it exists, create a new
SQLite DB, and start the cPHulk service.

It sends a notification to the server administrator with details of the actions taken.

=cut

sub perform {
    my $self = shift;

    return if !Cpanel::Config::Hulk::is_enabled();

    if ( !_integrity_check() ) {
        my $rebuild_details = {};
        try {
            Cpanel::SafeRun::Object->new_or_die( 'program' => '/usr/local/cpanel/scripts/restartsrv_cphulkd', 'args' => ['--stop'] );

            $rebuild_details->{'corrupted_db'} = _handle_invalid_database();
            Cpanel::Hulk::Admin::DB::initialize_db();

            Cpanel::SafeRun::Object->new_or_die( 'program' => '/usr/local/cpanel/scripts/restartsrv_cphulkd', 'args' => ['--start'] );
            $rebuild_details->{'rebuilt_db'} = 1;
        }
        catch {
            my $error = $_;

            $rebuild_details = {
                'rebuilt_db'    => 0,
                'rebuild_error' => Cpanel::Exception::get_string_no_id($error),
            };

            # We dont want to leave the service down, so even on failures, we'll start the service back up and just notify the admin.
            Cpanel::SafeRun::Object->new_or_die( 'program' => '/usr/local/cpanel/scripts/restartsrv_cphulkd', 'args' => ['--start'] );
        };

        $self->_notify($rebuild_details);
    }

    return 1;
}

sub _notify {
    my ( $self, $rebuild_details ) = @_;

    require Cpanel::Notify;
    return Cpanel::Notify::notification_class(
        'class'            => 'Install::CheckcPHulkDB',
        'application'      => 'Install::CheckcPHulkDB',
        'constructor_args' => [
            origin          => 'CheckcPHulk',
            rebuild_details => $rebuild_details,
        ]
    );
}

sub _integrity_check {
    my $success = 0;

    try {
        $success = Cpanel::Hulk::Admin::DB::integrity_check();
    }
    catch {
        local $@ = $_;

        # If we get a non DB error then something went wrong, so
        # just rethrow it
        die if !try { $_->isa('Cpanel::Exception::Database::Error') };

        # If we get a BUSY error, then let the process retry in the next run.
        if ( $_->failure_is('SQLITE_BUSY') ) {
            $success = 1;
        }
    };

    return $success;
}

# NOTE: We could de-duplicate these two subs as they are taken from
# the Cpanel::SQLite::AutoRebuildSchemaBase module. Unfortunately,
# this base class does not fit the use case for cPHulk at this time.
sub _handle_invalid_database {
    my $db_path = Cpanel::Config::Hulk::get_sqlite_db();
    return if !-e $db_path;

    Cpanel::LoadModule::load_perl_module('Cpanel::NameVariant');
    Cpanel::LoadModule::load_perl_module('Cpanel::Autodie');
    Cpanel::LoadModule::load_perl_module('Cpanel::Time::ISO');

    my $new_filename = Cpanel::NameVariant::find_name_variant(
        max_length => 254,
        name       => $db_path . '.broken.' . Cpanel::Time::ISO::unix2iso(),
        test       => sub { return !-e $_[0] },
    );

    Cpanel::Autodie::rename( $db_path, $new_filename );

    _clean_old_broken_dbs($db_path);

    return $new_filename;
}

sub _clean_old_broken_dbs {
    my $db_path = shift;

    Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::Dir');
    Cpanel::LoadModule::load_perl_module('File::Basename');

    my $DB_DIR    = File::Basename::dirname($db_path);
    my $DB_REGEX  = File::Basename::basename($db_path);
    my $dir_nodes = Cpanel::FileUtils::Dir::get_directory_nodes($DB_DIR);
    my @old_dbs   = sort grep { /^\Q$DB_REGEX\E.broken/ } @$dir_nodes;

    my $MAX_BROKEN_DBS = 3;
    if ( ( my $dbs_to_remove = ( scalar @old_dbs ) - $MAX_BROKEN_DBS ) > 0 ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Autodie');
        Cpanel::Autodie::unlink_if_exists( $DB_DIR . '/' . $_ ) for splice( @old_dbs, 0, $dbs_to_remove );
    }

    return;
}

1;
