package Cpanel::Features::Migrate;

# cpanel - Cpanel/Features/Migrate.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

our $VERSION = 1.1;

use Cpanel::LoadFile         ();
use Cpanel::FileUtils::Write ();
use Cpanel::Features::Write  ();
use Cpanel::Features::Load   ();
use Cpanel::Version::Compare ();

our $migrate_track_file = '/var/cpanel/features.migrated';
our %MIGRATE_MAP        = (
    '11.32.0' => {
        'split' => [],
        'merge' => [ [ [ 'traceaddy', 'deliveryreport' ], 'emailtrace' ] ]

    }
);

sub migrate_feature_list_to_current {
    my $feature_list_name    = shift;
    my $include_versions_ref = shift;
    my $exclude_versions_ref = shift;
    my $featurelist_ref      = Cpanel::Features::Load::load_featurelist($feature_list_name);
    my $modified             = 0;
    foreach my $version ( sort { Cpanel::Version::Compare::compare( $a, '<', $b ) } keys %MIGRATE_MAP ) {
        if ( defined $include_versions_ref && !exists $include_versions_ref->{$version} ) { next; }
        if ( defined $exclude_versions_ref && exists $exclude_versions_ref->{$version} )  { next; }
        my $ops = $MIGRATE_MAP{$version};
        if ( exists $ops->{'split'} ) {

            # we only have 0s in a feature list as anything not in there is explicitly on
            foreach my $split_op ( @{ $ops->{'split'} } ) {
                my $source  = $split_op->[0];
                my @targets = @{ $split_op->[1] };
                if ( exists $featurelist_ref->{$source} ) {
                    foreach my $target (@targets) {
                        $featurelist_ref->{$target} = $featurelist_ref->{$source};
                        $modified = 1;
                    }
                }
            }
        }
        if ( exists $ops->{'merge'} ) {

            # we only have 0s in a feature list as anything not in there is explicitly on
            foreach my $merge_op ( @{ $ops->{'merge'} } ) {
                my @sources = @{ $merge_op->[0] };
                my $target  = $merge_op->[1];
                my $value;

                next if exists $featurelist_ref->{$target};
                foreach my $source (@sources) {
                    if ( exists $featurelist_ref->{$source} ) {
                        $value = $featurelist_ref->{$source};
                    }
                }
                if ( defined $value ) {
                    $featurelist_ref->{$target} = $value;
                    $modified = 1;
                }
            }
        }

    }

    Cpanel::Features::Write::write_featurelist( $feature_list_name, $featurelist_ref )
      if $modified;

    return ( 1, $modified );
}

sub migrate_all_feature_lists_to_current {
    my $force = shift;

    my @migrated = split( /\s*\,\s*/, Cpanel::LoadFile::loadfile($migrate_track_file) // '' );
    @migrated = () if $force;

    my @feature_files;

    if ( opendir( my $feature_dh, $Cpanel::Features::Load::feature_list_dir ) ) {
        @feature_files = grep( !m/^\.+$/, readdir($feature_dh) );
        closedir($feature_dh);
    }
    else {
        return ( 0, 0 );
    }
    my $status   = 1;
    my $modified = 0;
    foreach my $feature_file (@feature_files) {
        my ( $op_status, $op_modified ) = migrate_feature_list_to_current( $feature_file, undef, { map { $_ => 1 } @migrated } ) if -f $Cpanel::Features::Load::feature_list_dir . '/' . $feature_file;
        $status = 0 if !$op_status;
        $modified++ if $op_modified;
    }
    Cpanel::FileUtils::Write::overwrite_no_exceptions( $migrate_track_file, join( ',', keys %MIGRATE_MAP ), 0644 ) || return ( 0, 0 );

    return ( $status, $modified );
}

1;
