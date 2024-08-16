package Cpanel::BandwidthDB;

# cpanel - Cpanel/BandwidthDB.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# These functions implement “create/upgrade if not exists”.
#----------------------------------------------------------------------

use strict;

use Try::Tiny;

use Cpanel::BandwidthDB::Read      ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::LoadModule             ();
use Cpanel::PwCache                ();

#TODO: This flag was off for testing during 11.50.
#Once we’re “out of the woods” and pretty sure we’ll
#not need this functionality further, remove this flag.
our $_UNLINK_OLD_FLAT_FILES_ON_CONVERSION = 1;

#----------------------------------------------------------------------
#
# 1) Attempts to create a read-only BandwidthDB reader.
# 2) If that fails, and if the failure is a disk I/O failure,
#    then we’ll try to create a DB via an admin binary.
# 3) Then try to open the DB again.
#
sub get_reader_for_user {
    die 'Do not run as root!' if !$>;

    my $username = Cpanel::PwCache::getusername();

    my $obj;
    try {
        $obj = _try_to_create_instance(
            'Cpanel::BandwidthDB::Read',
            $username,
        );
    }
    catch {
        # local $@ will cause die to propgate the failure
        # from try
        my $exp = $_;
        if ( !try { $_->isa('Cpanel::Exception::Database::SchemaOutdated') } ) {
            local $@ = $exp;
            die;
        }
    };

    return $obj if $obj;

    #This will convert the DB if it still needs it.
    Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin::Call');

    try {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'bandwidth_call', 'CREATE_DATABASE' );
    }
    catch {

        #This failure might have been a race condition between two
        #DB creations. If it was, then there’s no actual error, and
        #we can continue on our merry way.
        #
        #NOTE: If we returned more than just a string from the admin layer
        #then we could just parse that, but for now this is fine.
        #
        my $create_err = $_;

        try {
            $obj = Cpanel::BandwidthDB::Read->new($username);
        }
        catch {
            warn "CREATE_DATABASE failed: $create_err";

            # local $@ will cause die to propgate the failure
            # from try
            local $@ = $_;
            die;
        };
    };

    return $obj || Cpanel::BandwidthDB::Read->new($username);
}

sub get_reader_for_root {
    my ($username) = @_;

    return _instantiate_for_root(
        'Cpanel::BandwidthDB::Read',
        $username,
    );
}

#Root required.
#
sub get_writer {
    my ($username) = @_;

    return _instantiate_for_root(
        'Cpanel::BandwidthDB::Write',
        $username,
    );
}

#----------------------------------------------------------------------

sub _create_and_import {
    my ($username) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB::Create');
    Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB::Convert');
    Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB::Write');    # PPI USE OK -- See _instantiate_for_root above.

    my $bwdb = Cpanel::BandwidthDB::Create->new($username);

    my $cpuser = Cpanel::Config::LoadCpUserFile::load($username);

    #NOTE: Allow this for testing so that we can use just "plain"
    #temporary system users rather than big, heavy temporary cpusers.
    if ( $cpuser && %$cpuser ) {
        my @domains = (
            $cpuser->{'DOMAIN'},
            @{ $cpuser->{'DOMAINS'} },
            @{ $cpuser->{'DEADDOMAINS'} },
        );

        $bwdb->initialize_domain($_) for @domains;

        Cpanel::BandwidthDB::Convert::import_from_flat_files(
            bw_obj       => $bwdb,
            domains      => \@domains,
            old_username => $username,
        );

        if ($_UNLINK_OLD_FLAT_FILES_ON_CONVERSION) {

            for my $moniker ( $username, @domains ) {

                # Don't laugh, an entry for @domains can be "" if running for something like user 'clamd'
                Cpanel::BandwidthDB::Convert::unlink_flat_files($moniker) if $moniker;
            }
        }
    }

    #Suppress the error if the problem was that the DB file already exists.
    #Recall that we only got here because SQLite told us that the DB file
    #*didn’t* exist; so, if the file does exist now, then probably there was
    #another process creating the DB at the same time, and that process
    #finished first. We can probably, then, just connect to that file, and
    #all should be well.
    try {
        $bwdb->install();
    }
    catch {
        my $exp = $_;
        if ( !try { $_->isa('Cpanel::Exception::IO::LinkError') } ) {
            local $@ = $exp;
            die;
        }
        if ( $_->error_name() ne 'EEXIST' ) {
            local $@ = $exp;
            die;
        }

        #OK, apparently another process install()ed this DB first.
    };

    return 1;
}

sub _instantiate_for_root {
    my ( $class, $username ) = @_;

    die 'Only run as root!' if $>;

    die 'Need “username”!' if !length $username;

    my $obj = _try_to_create_instance_with_schema_update( $class, $username );
    return $obj if $obj;

    _create_and_import($username);

    return $class->new($username);
}

sub _try_to_create_instance {
    my ( $class, $username ) = @_;

    my $obj;

    Cpanel::LoadModule::load_perl_module($class);

    try {
        $obj = $class->new($username);
    }
    catch {
        my $exp = $_;
        if ( !try { $_->isa('Cpanel::Exception::Database::Error') } ) {
            local $@ = $exp;
            die;
        }
        if ( !$_->failure_is('SQLITE_CANTOPEN') ) {
            local $@ = $exp;
            die;

        }
    };

    return $obj;
}

#Only root should call this
sub _try_to_create_instance_with_schema_update {
    my ( $class, $username ) = @_;

    my $obj;
    try {
        $obj = _try_to_create_instance( $class, $username );
    }
    catch {
        my $exp = $_;
        if ( !try { $_->isa('Cpanel::Exception::Database::SchemaOutdated') } ) {
            local $@ = $exp;
            die;
        }

        Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB::Upgrade');
        Cpanel::BandwidthDB::Upgrade::upgrade_schema($username);

        $obj = _try_to_create_instance( $class, $username );
    };

    return $obj;
}

1;
