package Cpanel::API::WordPressSite;

# cpanel - Cpanel/API/WordPressSite.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::API::WordPressSite

=head1 DESCRIPTION

A module providing functionality to install WordPress and retrieve the status of an install.

=head1 SYNOPSIS

    use Cpanel::API::WordPressSite;
    my $result = Cpanel::API::execute_or_die ('WordPressSite', 'create');

=cut

use strict;
use warnings;

use Cpanel::AdminBin::Call ();
use Cpanel::JSON           ();
use Cpanel::Locale::Lazy 'lh';

my $wordpress_site_role = {
    needs_feature => 'wp-toolkit',
};

our %API = (
    create   => $wordpress_site_role,
    retrieve => $wordpress_site_role,
);

=head1 FUNCTIONS

=head2 create

Triggers the installation of WordPress in the docroot in the current user's primary domain.
This is done via an admin bin that runs the install in the background.

=head3 RETURNS

Returns 1 on success, 0 on failure.  Error details, if any, are available in metadata.

=cut

sub create {
    my ( $args, $result ) = @_;

    my ( $status, $msg ) = Cpanel::AdminBin::Call::call( 'Cpanel', 'wpt', 'install' );
    if ($status) {
        $result->data($msg);
        return 1;
    }

    $result->error($msg);
    return 0;
}

=head2 retrieve

Returns information on the status of WordPress install on the current user's primary domain.

=head3 RETURNS

Always returns 1.  Details are available in metadata.

=cut

sub retrieve {
    my ( $args, $result ) = @_;

    my $domain = $Cpanel::CPDATA{'DNS'};

    my ( $stdout, $stderr, $status ) = Cpanel::AdminBin::Call::call( 'Cpanel', 'WpToolkitCli', 'execute_command', 'info', '-domain-name', $domain );
    if ( !$status ) {
        if ( !$stdout ) {
            $result->raw_error( lh()->maketext("Unable to run wp-toolkit.") );
            return 0;
        }
        my $data = _process_info($stdout);
        if ( $data->{'details'}->{'alive'} && !$data->{'details'}->{'hidden'} ) {
            $result->data($data);
            return 1;
        }
    }

    $result->data( _get_installation_status() );
    return 1;
}

sub _process_info {
    my ($info) = @_;

    my $data = Cpanel::JSON::LoadNoSetUTF8($info);

    return { 'install_status' => 'success', 'details' => $data };
}

sub _get_installation_status {
    my ( $status, $msg ) = Cpanel::AdminBin::Call::call( 'Cpanel', 'wpt', 'install_status' );

    return { 'install_status' => $status, 'details' => { 'msg' => $msg } };
}

1;
