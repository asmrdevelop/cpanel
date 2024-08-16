
# cpanel - Cpanel/DAV/Config/Base.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::DAV::Config::Base;

use strict;
use warnings;
use Cpanel::Locale ();

use constant {
    'HTTP_PORT'  => 2079,
    'HTTPS_PORT' => 2080,
};

=head1 NAME

CPANEL::DAV::Config::Base

=head1 SYNOPSIS

Module for basing other route getter modules, which in turn get Calendar and
Contacts information.

=head1 DESCRIPTION

Used only within the context of the submodules which use them as a parent.
See the dependent modules for examples.

=head1 SEE ALSO

Cpanel::DAV::Config::CCS (will be shipped with the cpanel-ccs-calendarserver
RPM over to /var/cpanel/perl).

=head1 METHODS

=head2 new

Returns the blessed object for the class, with the 'user' STRING passed in
stored within the object's hashref keyed to 'user'.

=cut

sub new {
    my ( $class, $user ) = @_;
    return bless { 'user' => $user }, $class;
}

=head2 PRINCIPAL_PATH

Returns a STRING which is the path to the principal data URL (relative to the
server's root).

=cut

sub PRINCIPAL_PATH {
    return "bogus/principal/$_[0]->{'user'}";
}

=head2 FREEBUSY_PATH

Returns a STRING which is the path to the free/busy data URL (relative to the
server's root).

=cut

sub FREEBUSY_PATH {
    return "bogus/freebusy/$_[0]->{'user'}";
}

=head2 get_best_domains

Returns LIST of the "best" non-SSL and SSL domains for the user you've
instantiated this object for, along with whether the SSL is "self-signed".

Throws if the user doesn't have a domain, or something odd like that.

=cut

sub get_best_domains {
    my ($self) = @_;

    my $user = $self->{'user'};
    my $domain;
    if ( $user =~ m/@/ ) {
        $domain = ( split '@', $user )[1];
    }
    else {
        $domain = $Cpanel::CPDATA{'DNS'} || do {
            require Cpanel::Config::LoadCpUserFile;
            Cpanel::Config::LoadCpUserFile::load_or_die($user)->{'DOMAIN'};
        };

        die "No domain for “$user” detectable!" if !$domain;
    }

    # ASSUMPTION: Following the pattern from mail config data which assumes
    # that mail.<domain> maps to the same server as <domain> does. This should
    # always work with a cPanel user's domain since we create the sub-domain
    # 'mail' for each cPanel user owned domain on the server.
    my $best_non_ssl_domain = 'mail.' . $domain;

    # case CPANEL-241
    # consider Cpanel::Domain::Local::domain_or_ip_is_on_local_server
    # see BoxTrapper_getwebdomain

    require Cpanel::SSL::Domain;
    require Cpanel::SSL::ServiceMap;
    my $ssl_service_group = Cpanel::SSL::ServiceMap::lookup_service_group('dav');
    my ( $ok, $ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( $user, { 'service' => $ssl_service_group, 'add_mail_subdomain' => 1 } );

    die Cpanel::Locale::lh()->maketext( 'Could not find the SSL domain for [_1].', $user ) if !$ok;

    return ( $best_non_ssl_domain, $ssl_domain_info->{ssldomain}, $ssl_domain_info->{is_self_signed} );
}

=head2 get

Returns HASHREF of calendar and contacts information. Very tightly coupled with
Cpanel::DAV::Config::get_calendar_contacts_information. See that module's
subroutine for a better understanding of why/how we're doing this here.

=cut

sub get {
    my ( $self, %args ) = @_;
    return {
        user => $self->{user},
        ssl  => {
            port           => $self->HTTPS_PORT,
            server         => "https://$args{best_ssl_domain}:" . $self->HTTPS_PORT,
            full_server    => "https://$args{best_ssl_domain}:" . $self->HTTPS_PORT . '/' . $self->PRINCIPAL_PATH,
            is_self_signed => $args{is_self_signed},
            calendars      => _expand_list( $args{calendar_list}, 'https://', $args{best_ssl_domain}, $self->HTTPS_PORT ),
            contacts       => _expand_list( $args{contacts_list}, 'https://', $args{best_ssl_domain}, $self->HTTPS_PORT ),
            free_busy      => "https://$args{best_ssl_domain}:" . $self->HTTPS_PORT . '/' . $self->FREEBUSY_PATH,
        },
        no_ssl => {
            port        => $self->HTTP_PORT,
            server      => "http://$args{best_non_ssl_domain}:" . $self->HTTP_PORT,
            full_server => "http://$args{best_non_ssl_domain}:" . $self->HTTP_PORT . '/' . $self->PRINCIPAL_PATH,
            calendars   => _expand_list( $args{calendar_list}, 'http://', $args{best_non_ssl_domain}, $self->HTTP_PORT ),
            contacts    => _expand_list( $args{contacts_list}, 'http://', $args{best_non_ssl_domain}, $self->HTTP_PORT ),
            free_busy   => "http://$args{best_non_ssl_domain}:" . $self->HTTP_PORT . '/' . $self->FREEBUSY_PATH,
        },
    };
}

sub _expand_list {
    my ( $list, $protocol, $domain, $port ) = @_;
    return $list if !$list || ref $list ne 'ARRAY' || !@$list;

    # expand the structure to include the full url to the item.
    my @data;
    foreach my $item (@$list) {
        push @data,
          {
            name        => $item->{name},
            description => $item->{description},
            path        => $item->{path},
            url         => "$protocol$domain:$port" . $item->{path},
          };
    }
    return \@data;
}

1;
