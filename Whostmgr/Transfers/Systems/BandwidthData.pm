package Whostmgr::Transfers::Systems::BandwidthData;

# cpanel - Whostmgr/Transfers/Systems/BandwidthData.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# RR Audit: JTK

use Try::Tiny;
use Cpanel::AdminBin::Serializer ();
use Cpanel::BandwidthDB::Create  ();
use Cpanel::BandwidthDB::Convert ();
use Cpanel::Exception            ();
use Cpanel::FileUtils::Dir       ();
use Cpanel::Locale               ();
use Cpanel::ServerTasks          ();

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_relative_time {
    return 3;
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores the bandwidth data.') ];
}

sub get_restricted_available {
    return 1;
}

sub get_prereq { return ['Domains']; }

sub get_phase {
    return 110;
}

#From 11.50+
sub _import_from_modern {
    my ( $self, $bwdb ) = @_;

    my $extractdir = $self->extractdir();

    my $modern_backup = "$extractdir/bandwidth_db.json";

    if ( -f $modern_backup ) {
        $bwdb->restore_backup( Cpanel::AdminBin::Serializer::LoadFile($modern_backup), $extractdir );

        return 1;
    }

    return 0;
}

#From pre-11.50
sub _import_from_flat_files {
    my ( $self, $bwdb ) = @_;

    my $olduser = $self->olduser();

    my $extractdir = $self->extractdir();

    my $archive_bw_dir = "$extractdir/bandwidth";

    my $nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes($archive_bw_dir);

    my @domains = grep { !m<\.(?:rrd|xml)\z> } @$nodes_ar;

    for my $d (@domains) {
        $bwdb->initialize_domain($d);
    }

    Cpanel::BandwidthDB::Convert::import_from_flat_files(
        bw_obj       => $bwdb,
        directory    => $archive_bw_dir,
        domains      => \@domains,
        old_username => $olduser,
    );

    return 1;
}

#----------------------------------------------------------------------
# As of 11.52, RRDTool has gone the way of the dinosaur in production. :)
#
# 1. Create a bandwidth DB for the new user.
# 2. Import the bandwidth JSON data or, lacking such, the daily data.
#
sub unrestricted_restore {
    my ($self) = @_;

    my $newuser = $self->newuser();

    my $extractdir = $self->extractdir();

    $self->start_action('Restoring Bandwidth Data');

    require Cpanel::Timezones;

    # This prevents endlessly stating /etc/localtime
    local $ENV{'TZ'} = Cpanel::Timezones::calculate_TZ_env();

    #Don't use Cpanel::BandwidthDB::get_writer() here because
    #we want to clobber whatever might be already in the way.
    my $bwdb = Cpanel::BandwidthDB::Create->new($newuser);

    my $err_str;

    try {
        #NB: We still need to import RRD hourly even if we came from
        #a modern backup since 11.50 shipped with modern backup but
        #un-equalized hourly data.
        $self->_import_from_modern($bwdb) || $self->_import_from_flat_files($bwdb);

        #Clobber anything that might already have the same filename.
        $bwdb->force_install();
    }
    catch {
        $err_str = Cpanel::Exception::get_string($_);
    };

    return ( 0, $err_str ) if defined $err_str;

    undef $bwdb;

    # Avoid a concurrency issue by handing this off to queueprocd
    Cpanel::ServerTasks::schedule_task( ['BandwidthDBTasks'], 10, "build_bwdb_rootcache $newuser" );

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
