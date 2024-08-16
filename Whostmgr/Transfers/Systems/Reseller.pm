package Whostmgr::Transfers::Systems::Reseller;

# cpanel - Whostmgr/Transfers/Systems/Reseller.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
# RR Audit: JNK

use Cpanel::ConfigFiles      ();
use Cpanel::SafeDir::MK      ();
use Cpanel::SimpleSync::CORE ();
use Whostmgr::Limits         ();
use Cpanel::Reseller         ();
use Cpanel::LoadFile         ();

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_phase {
    return 20;
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores reseller privileges.') ];
}

sub get_restricted_available {
    my ($self) = @_;
    return 0;
}

sub get_notes {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores all of the privileges the account previously had. This includes the “all” privilege, which is equivalent to root access.') ];
}

sub unrestricted_restore {
    my ($self) = @_;

    my $newuser = $self->newuser();

    my $extractdir = $self->extractdir();
    my $olduser    = $self->olduser();

    #TODO: This should bail out early if this isn't a reseller that we're restoring.

    $self->start_action('Restoring reseller packages and features (if any)');

    my ( $ok, $msg ) = $self->_import_reseller_belongings(
        'newuser' => $newuser,                         #
        'olduser' => $olduser,                         #
        'type'    => "packages",                       #
        'dir'     => "$extractdir/resellerpackages"    #
    );
    $self->warn($msg) if !$ok;

    ( $ok, $msg ) = $self->_import_reseller_belongings(
        'newuser' => $newuser,                         #
        'olduser' => $olduser,                         #
        'type'    => "features",                       #
        'dir'     => "$extractdir/resellerfeatures"    #
    );
    $self->warn($msg) if !$ok;

    $self->start_action('Restoring reseller privileges (if any)');

    #XXX: Fix this when $olduser ne $newuser -- been broken for a while.
    #TODO: Error reporting in most of Whostmgr::Limits

    #Looks for:
    #my_reseller-limits.yaml
    #my_package-limits.yaml
    Whostmgr::Limits::import_reseller_limits(
        'dir'     => "$extractdir/resellerconfig",    #
        'newuser' => $newuser,                        #
        'olduser' => $olduser                         #
    );

    my $version_txt = Cpanel::LoadFile::load_if_exists("$extractdir/version") || '';
    my ($pkg_archive_version) = $version_txt =~ m/archive version: ([0-9]+)/g;

    my $warnings = {};

    #Brings in ACLs and nameservers
    Whostmgr::Limits::import_reseller_config(
        'dir'                 => "$extractdir/resellerconfig",    #
        'newuser'             => $newuser,                        #
        'olduser'             => $olduser,                        #
        'warnings'            => $warnings,                       #
        'pkg_archive_version' => $pkg_archive_version // 3,       #
    );

    if (
        $warnings->{'unknown-acls'}                               #
        && ref $warnings->{'unknown-acls'} eq 'ARRAY'             #
        && scalar @{ $warnings->{'unknown-acls'} }                #
    ) {
        $self->warn(
            $self->_locale()->maketext(
                "Unable to restore the [list_and,_2] [numerate,_1,ACL,ACLs] for user “[_3]”.",    #
                scalar @{ $warnings->{'unknown-acls'} },                                          #
                $warnings->{'unknown-acls'},                                                      #
                $newuser,                                                                         #
            )
        );
    }

    {
        # Force re-cache of reseller privs
        $Cpanel::Reseller::reseller_cache_fully_loaded = 0;
        Cpanel::Reseller::getresellersaclhash();
    }
    return 1;
}

sub restricted_restore {
    my ($self) = @_;

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    #Packages can have the reseller *directories* even if the user
    #isn't a reseller, so we have to check for this file.
    if ( -e "$extractdir/resellerconfig/resellers" ) {
        return ( $Whostmgr::Transfers::Systems::UNSUPPORTED_ACTION, $self->_locale()->maketext( 'Restricted restorations do not allow running the “[_1]” module.', 'Reseller' ) );
    }

    return 1;
}

sub _import_reseller_belongings {
    my ( $self, %OPTS ) = @_;

    my $newuser        = $OPTS{'newuser'};
    my $olduser        = $OPTS{'olduser'};
    my $belonging_type = $OPTS{'type'};
    my $backup_dir     = $OPTS{'dir'};

    return 1 if !-d $backup_dir;

    my $dir_creator = sub { };
    my $dest_dir;
    if ( $belonging_type eq 'packages' ) {
        $dest_dir    = $Cpanel::ConfigFiles::PACKAGES_DIR;
        $dir_creator = sub {
            Cpanel::SafeDir::MK::safemkdir( $Cpanel::ConfigFiles::PACKAGES_DIR, '0775' );
            return 1;
        };
    }
    elsif ( $belonging_type eq 'features' ) {
        $dest_dir    = $Cpanel::ConfigFiles::FEATURES_DIR;
        $dir_creator = sub {
            eval {
                require Cpanel::Features::Lists;
                Cpanel::Features::Lists::ensure_featurelist_dir();
                return 1;
            };
        };
    }
    else {
        die "Invalid type: $belonging_type";    #programmer error
    }

    if ( !-e $dest_dir ) {
        $dir_creator->() or do {
            $self->warn("Unable to create dir \"$dest_dir\".");
            return ( 0, $self->_locale()->maketext( 'The system failed to ensure that the directory “[_1]” exists with permissions “[_2]” because of an error: [_3]', $dest_dir, '0775', $! ) );
        };
    }

    # Get backup list
    my ( $items_ok, $items_owned ) = $self->_get_reseller_belongings( $olduser, $backup_dir );
    return ( 0, $items_owned ) if !$items_ok;

    #Nothing to do?
    return 1 if !@$items_owned;

    my $backup_file = '';
    my $dest_item   = '';
    my $dest_file   = '';
    my $status      = '';
    my $message     = '';

    foreach my $item ( @{$items_owned} ) {

        #foreach my $item ( @{$items_owned} ) {
        $backup_file = "$backup_dir/$item";

        $dest_item = $item;
        if ( $olduser ne $newuser ) {
            $dest_item =~ s/^\Q$olduser\E_/$newuser\_/;
        }
        $dest_file = "$dest_dir/$dest_item";

        # Restoring file from its backup
        ( $status, $message ) = Cpanel::SimpleSync::CORE::syncfile( $backup_file, $dest_file );
        if ( $status == 0 ) {
            $self->warn("No file restored from \"$backup_file\" to \"$dest_file\" ($message)");
        }
    }

    return 1;
}

sub _get_reseller_belongings {
    my ( $self, $reseller, $belonging_src_dir ) = @_;

    die "check arguments" if !$reseller || !$belonging_src_dir;

    my @belongings;

    #TODO: This needs to propagate
    opendir( my $belonging_dh, $belonging_src_dir ) or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to open the directory “[_1]” because of an error: [_2]', $belonging_src_dir, $! ) );
    };

    local $!;
    while ( my $item = readdir $belonging_dh ) {
        next if ( $item !~ m/^\Q${reseller}\E_/ );

        if ( -s "$belonging_src_dir/$item" ) {
            push @belongings, $item;
        }
    }

    #cf. RT #118651
    #if ($!) {
    #    return ( 0, $self->_locale()->maketext( 'The system failed to read from the directory “[_1]” because of an error: [_2]', $belonging_src_dir, $! ) );
    #}

    closedir $belonging_dh or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to close the directory “[_1]” because of an error: [_2]', $belonging_src_dir, $! ) );
    };

    return ( 1, \@belongings );
}

1;
