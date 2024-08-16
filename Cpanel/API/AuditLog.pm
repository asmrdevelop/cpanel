package Cpanel::API::AuditLog;

# cpanel - Cpanel/API/AuditLog.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::AdminBin::Call ();
use Cpanel::Exception      ();
use Cpanel::Locale         ();
use Cpanel::Server::Type   ();

=encoding utf-8

=head1 NAME

Cpanel::API::AuditLog - read the API log

=head1 DESCRIPTION

Provides API access to the API call history of a cPanel or Team Manager user.

=cut

my $non_mutating = { allow_demo => 1 };
my $mutating     = {};

our %API = (
    get_api_log => $non_mutating,
);

=head1 METHODS

=head2 get_api_log -- retrieves all API log entries for the caller.

    RETURNS: Array of log entry hashes, e.g.:
    {
        api_version    => 'uapi',
        called_by      => 'cptest',
        date_timestamp => '2022-08-11 19:17:22 -0500',
        call           => 'Team::list_team',
        origin         => 'Terminal',
    }

=cut

sub get_api_log ( $args, $result ) {
    if ( !Cpanel::Server::Type::has_feature('teams') ) {
        die Cpanel::Exception::create( 'FeatureNotEnabled', 'The “[_1]” feature is not available. Ask your reseller about adding this feature.', ['Team Manager'] );
    }

    my $locale   = Cpanel::Locale->get_handle();
    my $log_data = Cpanel::AdminBin::Call::call( 'Cpanel', 'api_call', 'READ' );
    $result->data($log_data);

    return 1;
}

1;
