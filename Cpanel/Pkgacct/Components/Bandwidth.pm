package Cpanel::Pkgacct::Components::Bandwidth;

# cpanel - Cpanel/Pkgacct/Components/Bandwidth.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use parent 'Cpanel::Pkgacct::Component';

use strict;
use warnings;

use Cpanel::BandwidthDB             ();
use Cpanel::Exception               ();
use Cpanel::Transaction::File::JSON ();

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::Bandwidth

=head1 SYNOPSIS

use Cpanel::Pkgacct ();

my $pkgacct = Cpanel::Pkgacct->new(
        ... # check the documentation for this object
    );

$pkgacct->perform_component("Bandwidth");

=head1 DESCRIPTION

The component to backup the /var/cpanel/bandwidth database for a user

=head1 FUNCTIONS


=cut

=head2 perform()

The workhorse of this module. This is the overridden function that is employed to restore bandwidth data information.
Please see/create documentation for Cpanel::Pkgacct::Component for information on how this interface should work.

=head3 Exceptions

Anything Cpanel::BandwidthDB can throw
Anything Cpanel::Transaction::File::JSON can throw

=cut

sub perform {
    my ($self) = @_;

    my $work_dir   = $self->get_work_dir();
    my $user       = $self->get_user();
    my $output_obj = $self->get_output_obj();

    $self->_copy_bandwidth_data_to_work_dir( $user, $work_dir, $output_obj );

    return 1;
}

sub _copy_bandwidth_data_to_work_dir {
    my ( $self, $user, $work_dir, $output_obj ) = @_;

    if ($>) {
        $output_obj->warn("Skipping summary databases due to lack of privileges.\n");
        return;
    }

    $output_obj->out( "Summary databases …", @Cpanel::Pkgacct::PARTIAL_MESSAGE );

    _save_bandwidth_data_to_dest( $user, "$work_dir/bandwidth_db.json", $work_dir, $output_obj );

    $output_obj->out(" done!\n");

    return 1;
}

sub _save_bandwidth_data_to_dest {
    my ( $user, $dest, $work_dir, $output_obj ) = @_;

    try {
        my $bw_reader = Cpanel::BandwidthDB::get_reader_for_root($user);
        my $trans     = Cpanel::Transaction::File::JSON->new( path => $dest );
        $trans->set_data( $bw_reader->get_backup_manifest() );
        $trans->save_and_close_or_die();

        $bw_reader->generate_backup_data($work_dir);
    }
    catch {
        $output_obj->warn( Cpanel::Exception::get_string($_) );
    };

    return;
}

1;
