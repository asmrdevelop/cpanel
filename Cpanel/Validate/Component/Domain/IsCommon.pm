package Cpanel::Validate::Component::Domain::IsCommon;

# cpanel - Cpanel/Validate/Component/Domain/IsCommon.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use base qw ( Cpanel::Validate::Component );

use Cpanel::LoadFile           ();
use Cpanel::ConfigFiles        ();
use Cpanel::Config::LoadCpConf ();
use Cpanel::Exception          ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain ));
    $self->add_optional_arguments(qw( blockcommondomains ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    if ( !defined $self->{'blockcommondomains'} ) {
        my $cpanel_config_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        $self->{'blockcommondomains'} = $cpanel_config_ref->{'blockcommondomains'} ? 1 : 0;
    }

    return;
}

my %_all_commondomains;

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ( $domain, $block_common_domains ) = @{$self}{ $self->get_validation_arguments() };

    if ($block_common_domains) {
        my $exception = Cpanel::Exception::create( 'DomainNameNotAllowed', 'The system cannot create the common domain “[_1]”. You must choose a different domain name.', [$domain] );

        _load_all_common_domains() if !scalar keys %_all_commondomains;
        my $lc_domain = $domain;
        $lc_domain =~ tr{A-Z}{a-z};

        my @domain_parts;
        foreach my $part ( reverse split( m{\.}, $lc_domain ) ) {
            unshift @domain_parts, $part;    # com, cpanel.com, my.cpanel.com
            if ( $_all_commondomains{ join( '.', @domain_parts ) } ) {
                die $exception;
            }
        }
    }

    return;
}

sub _load_all_common_domains {

    # Check the cpanel-provided list of common domains as well as a site-specific list.
    for my $file (@Cpanel::ConfigFiles::COMMONDOMAINS_FILES) {
        my $contents = Cpanel::LoadFile::load_if_exists($file);

        # loadfile used here to preserve legacy behavior
        next if !length $contents;
        foreach my $common_domain ( split( m{\n}, $contents ) ) {

            # Make sure that the domains we read have nothing unusual
            # (no leading or trailing dots, no doubled dots, no spaces).
            $common_domain =~ tr{ \r\n\f\t}{}d;
            $common_domain =~ tr{.}{}s;
            $common_domain =~ tr{A-Z}{a-z};
            substr( $common_domain, 0, 1, '' ) if index( $common_domain, '.' ) == 0;
            chop($common_domain)               if length $common_domain && substr( $common_domain, -1, 1 ) eq '.';
            next                               if !$common_domain;
            $_all_commondomains{$common_domain} = 1;
        }
    }
    return 1;
}

# For testing only
sub _clear_cache {
    %_all_commondomains = ();
    return;
}

1;
