package Cpanel::Validate::Component::Domain::HasDynamicDns;

# cpanel - Cpanel/Validate/Component/Domain/HasDynamicDns.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Validate::Component::Domain::HasDynamicDns

=head1 SYNOPSIS

    package My::DomainCreation::Validator;

    use parent qw (
        Cpanel::Validate::DomainCreation
    );

    use Cpanel::Validate::Component::Domain::HasDynamicDns;

    sub init {
        $self->add_validation_components(
            Cpanel::Validate::Component::Domain::HasDynamicDns->new(%args),
        ),
    };

=head1 DESCRIPTION

This class implements a validation check that ensures a prospective
new domain name doesn’t conflict with an existing Dynamic DNS domain.

=cut

#----------------------------------------------------------------------

use parent qw ( Cpanel::Validate::Component );

# Exposed for testing
our $_DDNS_TIMEOUT = 30;

#----------------------------------------------------------------------

=head1 METHODS

The following implement the interface required by the parent class:

=over

=item * C<init()>

=item * C<validate()>

=back

=cut

sub init ( $self, %OPTS ) {
    my @req_args = qw( domain ownership_user );
    $self->add_required_arguments(@req_args);

    # Needed to detect context correctly:
    my @opt_args = qw( validation_context );
    $self->add_optional_arguments(@opt_args);

    @{$self}{ @req_args, @opt_args } = @OPTS{ @req_args, @opt_args };

    return;
}

sub validate ($self) {

    $self->validate_arguments();

    require Cpanel::DynamicDNS::DomainsCache;
    require Cpanel::PromiseUtils;

    my ( $domain, $username ) = @{$self}{ $self->get_validation_arguments() };

    # For this validation we assume that the system may have subzones
    # across users, e.g., “bob” can own “bob.com” while “jane” owns
    # “jane.bob.com”. Even if the relevant cpanel.config settings are off
    # (as they are by default), we can’t know that those settings weren’t
    # on at some point. This implies that any user could own any domain,
    # which means we have to compare $domain to every DDNS domain.

    my $domain_id_hr = Cpanel::PromiseUtils::wait_anyevent(
        Cpanel::DynamicDNS::DomainsCache::read_p( timeout => $_DDNS_TIMEOUT ),
    )->get();

    if ( my $id = $domain_id_hr->{$domain} ) {
        $self->_die_because_entry_matches_domain( $id, $username, $domain );
    }

    return;
}

#----------------------------------------------------------------------

sub _die_because_entry_matches_domain ( $self, $id, $username, $domain ) {
    local ( $@, $! );

    require Cpanel::WebCalls::Datastore::Read;
    require Cpanel::Exception;

    my $ddns_username = Cpanel::WebCalls::Datastore::Read->get_username_for_id($id);

    my $can_disclose = $self->has_root();
    $can_disclose ||= $self->is_whm_context() && do {
        require Whostmgr::AcctInfo::Owner;
        Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $ddns_username );
    };

    if ($can_disclose) {

        # If it’s root trying to create the domain, then we can
        # disclose full details.
        die Cpanel::Exception->create(
            '“[_1]” already owns a dynamic [asis,DNS] domain named “[_2]”.',
            [ $ddns_username, $domain ],
        );
    }
    elsif ( $ddns_username eq $username ) {

        # If the impediment is under the user’s control, then we can
        # disclose full details.
        die Cpanel::Exception->create(
            'You already own a dynamic [asis,DNS] domain named “[_1]”.',
            [$domain],
        );
    }

    # If the impediment is outside the user’s resources,
    # then we give a generic error.
    die Cpanel::Exception->create(
        'This system already controls a domain named “[_1]”.',
        [$domain],
    );
}

1;
