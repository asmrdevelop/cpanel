package Whostmgr::Transfers::Systems::ProxySubdomains;

# cpanel - Whostmgr/Transfers/Systems/ProxySubdomains.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# RR Audit: JNK

use Cpanel::Config::LoadCpConf ();
use Cpanel::Proxy              ();
use Cpanel::Proxy::Tiny        ();

sub get_phase { return 90; }

# Must run after the apache vhosts are in httpd.conf
# Reseller is required so we can determine the correct proxysubdomains
# but since it can be disabled the phase is 100 for this module
sub get_prereq { return [ 'MailRouting', 'ZoneFile', 'Vhosts' ]; }

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores service subdomains.') ];
}

sub get_restricted_available {
    return 1;
}

sub get_notes {
    my ($self) = @_;

    my @example_subdomains = sort keys %{ Cpanel::Proxy::Tiny::get_known_proxy_subdomains() };

    # Limit the number of listed service subs.
    splice( @example_subdomains, 3 );

    return [ $self->_locale()->maketext( 'This module ensures that service subdomains such as [list_and_quoted,_1] are configured properly.', \@example_subdomains ) ];
}

sub unrestricted_restore {
    my ($self) = @_;

    my $newuser = $self->{'_utils'}->local_username();

    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy() or do {
        my $msg = $self->_locale()->maketext( 'The system failed to read the [output,asis,cPanel] configuration file because of an error: [_1]', $! );
        $self->warn($msg);
        return ( 0, $msg );
    };

    return 1 if !$cpconf_ref->{'proxysubdomains'};

    $self->start_action( $self->_locale()->maketext( "Update service subdomains for “[_1]”.", $newuser ) );

    my $old_hostname = $self->{'_utils'}->get_old_hostname();

    my ( $status, $msg, $results ) = Cpanel::Proxy::setup_proxy_subdomains(
        user            => $newuser,
        domain          => $self->{'_utils'}{'domain'},
        old_hostname    => $old_hostname,
        no_replace      => 0,
        delete_disabled => 1,
    );

    if ( $results && ref $results->{'domain_status'} ) {
        foreach my $response ( sort { $a->{'domain'} cmp $b->{'domain'} } @{ $results->{'domain_status'} } ) {
            $self->out( _pad( $response->{'domain'}, 35 ) . $response->{'msg'} . "\n" );
        }
    }

    $self->out($msg) if $msg;

    return $status ? $status : ( $status, $msg );
}

sub _pad {
    my ( $text, $length ) = @_;

    if ( length($text) > $length ) {
        return substr( $text, 0, ( $length - 1 ) ) . '…';
    }
    else {
        return $text . ( ' ' x ( $length - length $text ) );
    }
}

*restricted_restore = \&unrestricted_restore;

1;
