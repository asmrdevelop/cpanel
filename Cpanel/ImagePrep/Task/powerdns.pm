
# cpanel - Cpanel/ImagePrep/Task/powerdns.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::powerdns;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::FileUtils::Modify ();

=head1 NAME

Cpanel::ImagePrep::Task::powerdns - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Clear and regenerate PowerDNS API key, webserver, and webserver-password
lines in /etc/pdns/pdns.conf.
EOF
}

use constant CONF              => '/etc/pdns/pdns.conf';
use constant MIGRATE_PDNS_CONF => '/usr/local/cpanel/scripts/migrate-pdns-conf';

sub _type { return 'non-repair only' }

=head2 PRE ACTIONS

Abort as "not applicable" if PowerDNS is not configured as the local DNS server.

Otherwise, in /etc/pdns/pdns.conf, delete the api, api-key, webserver, and
webserver-password lines so that this feature is deactivated.

=cut

sub _pre ($self) {

    if ( !$self->common->_exists( CONF() ) ) {
        $self->loginfo('PowerDNS API and webserver configuration does not exist.');
        return $self->PRE_POST_NOT_APPLICABLE;
    }

    my $updated = Cpanel::FileUtils::Modify::match_replace(
        CONF(),
        [
            # The '.*\R?' pattern with the 'm' modifier and *without* the 's' modifier matches everything on a
            # single line up to and *including* the next optional line-break character(s), so that an empty
            # replacement deletes the entire line.
            { match => qr/^api=yes.*\R?/m,             replace => q{} },
            { match => qr/^api-key=.*\R?/m,            replace => q{} },
            { match => qr/^webserver=yes.*\R?/m,       replace => q{} },
            { match => qr/^webserver-password=.*\R?/m, replace => q{} },
        ]
    );

    if ( !$updated ) {
        $self->loginfo('There are no PowerDNS API or webserver keys in the conf file.');
        return $self->PRE_POST_NOT_APPLICABLE;
    }

    $self->loginfo('Cleared PowerDNS API and webserver keys.');
    return $self->PRE_POST_OK;
}

=head2 POST ACTIONS

Abort as "not applicable" if PowerDNS is not configured as the local DNS server.

Otherwise, run scripts/migrate-pdns-conf to add the missing api, api-key, and
webserver-password configuration, and restart PowerDNS.

=cut

sub _post ($self) {

    if ( !$self->common->_exists( CONF() ) ) {
        $self->loginfo('PowerDNS API and webserver configuration does not exist.');
        return $self->PRE_POST_NOT_APPLICABLE;
    }

    $self->common->run_command( MIGRATE_PDNS_CONF(), '--no-notify' );
    $self->need_restart('pdns');
    $self->loginfo('Regenerated PowerDNS API and webserver keys.');

    return $self->PRE_POST_OK;
}

1;
