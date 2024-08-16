package Cpanel::Validate::Component::Domain::IsHostname;

# cpanel - Cpanel/Validate/Component/Domain/IsHostname.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use base qw ( Cpanel::Validate::Component );

use Cpanel::Exception          ();
use Cpanel::Config::LoadCpConf ();
use Cpanel::Hostname           ();
use Whostmgr::Func             ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain ));
    $self->add_optional_arguments(qw( allowresellershostnamedomainsubdomains allowparkhostnamedomainsubdomains validation_context ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    if ( !defined $self->{'allowresellershostnamedomainsubdomains'} || !defined $self->{'allowparkhostnamedomainsubdomains'} ) {
        my $cpanel_config_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        $self->{'allowresellershostnamedomainsubdomains'} = $cpanel_config_ref->{'allowresellershostnamedomainsubdomains'} ? 1 : 0;
        $self->{'allowparkhostnamedomainsubdomains'}      = $cpanel_config_ref->{'allowparkhostnamedomainsubdomains'}      ? 1 : 0;
    }

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my $domain = $self->{'domain'};

    my $hostname = Cpanel::Hostname::gethostname();
    if ( $hostname eq $domain ) {
        die Cpanel::Exception::create(
            'DomainNameNotAllowed',
            'You may not create a domain with a name that is the server’s hostname.'
        );
    }

    if ( $self->is_whm_context() ) {
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        if ( !$self->{'allowresellershostnamedomainsubdomains'} && !Whostmgr::ACLS::hasroot() ) {
            if ( Whostmgr::Func::is_true_subdomain_of_domain( $domain, $hostname ) ) {
                die Cpanel::Exception::create( 'DomainNameNotAllowed', 'You do not have permission to create subdomains of the server’s hostname.' );
            }
        }
    }
    else {
        if ( !$self->{'allowparkhostnamedomainsubdomains'} ) {
            if ( Whostmgr::Func::is_true_subdomain_of_domain( $domain, $hostname ) ) {
                die Cpanel::Exception::create( 'DomainNameNotAllowed', 'You do not have permission to create subdomains of the server’s hostname.' );
            }
        }
    }

    return;
}

1;
