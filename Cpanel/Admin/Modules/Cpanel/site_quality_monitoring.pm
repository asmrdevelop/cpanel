# cpanel - Cpanel/Admin/Modules/Cpanel/site_quality_monitoring.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::site_quality_monitoring;

use cPstrict;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Slurper ();

use constant UUID_FILE => '/var/cpanel/cpanel.uuid';

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::site_quality_monitoring

=head1 SYNOPSIS

  use Cpanel::AdminBin::Call ();

  Cpanel::AdminBin::Call::call( "Cpanel", "site_quality_monitoring", $action, {} );

=head1 DESCRIPTION

This admin bin is used by Site Quality Monitoring (koality) to execute code with root permissions.

=cut

sub _actions {
    return qw(GET_SERVER_UUID);
}

use constant _allowed_parents => (
    __PACKAGE__->SUPER::_allowed_parents(),
);

sub GET_SERVER_UUID {
    chomp(my $uuid = eval { Cpanel::Slurper::read(UUID_FILE) } || '' );
    return $uuid;
}

1;
