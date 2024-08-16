# cpanel - Whostmgr/Transfers/Systems/ManualMX.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Whostmgr::Transfers::Systems::ManualMX;

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::ManualMX

=head1 DESCRIPTION

This module is part of the account restoration system.
It subclasses L<Whostmgr::Transfers::Systems>; see that module
for more details.

=cut

use parent 'Whostmgr::Transfers::Systems';

use Cpanel::Imports;

use Cpanel::Sys::Hostname          ();
use Cpanel::Validate::Domain::Tiny ();

use constant {
    get_restricted_available        => 1,
    minimum_transfer_source_version => 90,

    # v96 introduced the cPanel endpoint for ManualMX
    minimum_transfer_source_version_for_user => 96,

    get_phase  => 99,
    get_prereq => [ 'Homedir', 'Domains' ],
};

=head1 METHODS

=head2 I<OBJ>->get_summary()

POD for cplint. Don’t call this directly.

=cut

sub get_summary ($self) {
    return [ locale()->maketext('This configures the source server’s manual [asis,MX] entries to send mail to the destination server.') ];
}

=head2 I<OBJ>->restricted_restore( %OPTS )

POD for cplint. Don’t call this directly.

=cut

sub restricted_restore ($self) {

    my $utils = $self->utils();

    if ( !$utils->is_live_transfer() ) {
        $self->out( locale()->maketext('This module pertains to the [asis,Live Transfer] setting only.') );
        return 1;
    }

    my @domains  = ( $utils->main_domain(), @{ $utils->get_original_domains() } );
    my $hostname = Cpanel::Sys::Hostname::gethostname();

    my $api_args = { domain => [], mx_host => [] };
    for ( 0 .. $#domains ) {

        # Filter invalid entries in case there’s some kind of corruption.
        # We want to submit as many valid domains as we can.
        next if !Cpanel::Validate::Domain::Tiny::validdomainname( $domains[$_], 1 );
        push @{ $api_args->{domain} },  $domains[$_];
        push @{ $api_args->{mx_host} }, $hostname;
    }

    my $source_host = $utils->get_source_hostname_or_ip();
    $self->start_action( locale()->maketext( 'Configuring manual [asis,MX] entries on the source server ([_1]) …', $source_host ) );

    if ( $utils->{'flags'}{'restore_type'} eq 'user' ) {
        my $api = $utils->get_source_cpanel_api_object();
        $api->request_uapi( 'Email', 'set_manual_mx_redirects', $api_args );
    }
    elsif ( $utils->{'flags'}{'restore_type'} eq 'root' ) {
        my $api = $utils->get_source_api_object();
        $api->request_whmapi1_or_die( 'set_manual_mx_redirects', $api_args );
    }
    else {
        Carp::confess "Invalid restore type: $utils->{'flags'}{'restore_type'}";
    }

    return ( 1, locale()->maketext("Manual [asis,MX] entries configured.") );
}

*unrestricted_restore = \&restricted_restore;

1;
