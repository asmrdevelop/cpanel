# cpanel - Whostmgr/API/1/ConnectedApplications.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::API::1::ConnectedApplications;

use cPstrict;

use constant NEEDS_ROLE => {
    save_connected_application   => undef,
    remove_connected_application => undef,
    fetch_connected_application  => undef,
    list_connected_applications  => undef,
};

use Cpanel::ConnectedApplications ();
use Whostmgr::API::1::Utils       ();

=head1 MODULE

C<Whostmgr::API::1::ConnectedApplications>

=head1 DESCRIPTION

C<Whostmgr::API::1::ConnectedApplications> provides WHM API 1 call implementation used to view and manage
various external applications that are linked to this instance of cPanel & WHM.

The data storage files will be stored in one of the following depending on the user logged into WHM:

=over

=item root - /home/root

=item reseller - /var/cpanel/resellers/<username>

=back

=head1 FUNCTIONS

=head2 save_connected_application

See L<save_connected_application|https://go.cpanel.net/save_connected_application>

=cut

sub save_connected_application ( $args, $metadata, @ ) {
    my ( $name, $data ) = (
        Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' ),
        Whostmgr::API::1::Utils::get_length_required_argument( $args, 'data' )
    );

    my $path    = _get_path();
    my $manager = Cpanel::ConnectedApplications->new( path => $path );
    $manager->save( $name, $data );
    $metadata->set_ok();

    return;
}

=head2 remove_connected_application

See L<remove_connected_application|https://go.cpanel.net/remove_connected_application>

=cut

sub remove_connected_application ( $args, $metadata, @ ) {
    my $name = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' );

    my $path    = _get_path();
    my $manager = Cpanel::ConnectedApplications->new( path => $path );
    $manager->remove($name);

    $metadata->set_ok();

    return;
}

=head2 fetch_connected_application

See L<fetch_connected_application|https://go.cpanel.net/fetch_connected_application>

=cut

sub fetch_connected_application ( $args, $metadata, @ ) {
    my $name = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' );

    my $path    = _get_path();
    my $manager = Cpanel::ConnectedApplications->new( path => $path );
    my $app     = $manager->load($name);

    $metadata->set_ok();

    return { app => $app };
}

=head2 list_connected_applications

See L<list_connected_applications|https://go.cpanel.net/list_connected_applications>

=cut

sub list_connected_applications ( $args, $metadata, @ ) {
    my $path    = _get_path();
    my $manager = Cpanel::ConnectedApplications->new( path => $path );
    my @list    = $manager->list();

    $metadata->set_ok();

    return { list => \@list };
}

=head2 _get_path()

Get the storage path from the environment.

=cut

sub _get_path() {
    return $ENV{'REMOTE_USER'} eq 'root' ? '/root' : "/var/cpanel/reseller-data/$ENV{'REMOTE_USER'}";
}

1;
