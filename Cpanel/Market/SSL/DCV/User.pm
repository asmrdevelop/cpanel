package Cpanel::Market::SSL::DCV::User;

# cpanel - Cpanel/Market/SSL/DCV/User.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Market::SSL::DCV::User

=head1 SYNOPSIS

    Cpanel::Market::SSL::DCV::User::prepare_for_dcv(...);
    Cpanel::Market::SSL::DCV::User::undo_dcv_preparation(...);

=head1 DESCRIPTION

This module contains root’s logic for DCV setup. See
L<Cpanel::Market::SSL::DCV> for some general notes on DCV.

=cut

use parent qw( Cpanel::Market::SSL::DCV );

=head1 FUNCTIONS

=head2 prepare_for_dcv( %OPTS )

Does a DCV preparation (HTTP and DNS) as a user. %OPTS is the same as
for C<Cpanel::Market::SSL::DCV::Root::prepare_for_dcv()>
except that C<username> is not needed.

=cut

use Cpanel::Exception ();

sub prepare_for_dcv {
    my (%opts) = @_;

    _prevalidate_as_user(
        '_validate_username_csr_and_domains_for_prepare',
        \%opts,
    );

    return __PACKAGE__->can('_prepare_for_dcv')->(
        %opts,
        setuid_if_needed              => sub { },
        create_dns_dcv_setup_callback => sub {
            my ( undef, $dns_dcv_domains ) = @_;

            require Cpanel::AdminBin::Call;
            return sub {
                Cpanel::AdminBin::Call::call(
                    'Cpanel', 'market', 'PROVIDER_DNS_DCV_SETUP',
                    %opts{'provider'},
                    provider_args => {
                        %{ $opts{'provider_args'} },
                        domains => $dns_dcv_domains,
                    },
                );
            };
        },
    );
}

=head2 undo_dcv_preparation( %OPTS )

Undoes a DCV preparation (HTTP and DNS) as a user. %OPTS is the same as
for C<undo_dcv_preparation()> except that C<username> is not needed.

=cut

sub undo_dcv_preparation {
    my (%opts) = @_;

    _prevalidate_as_user(
        '_validate_username_csr_and_domains_for_undo',
        \%opts,
    );

    return __PACKAGE__->can('_undo_dcv_preparation')->(
        %opts,
        setuid_if_needed            => sub { },
        undo_dns_dcv_setup_callback => sub {
            my ( undef, $dns_dcv_domains ) = @_;

            require Cpanel::AdminBin::Call;
            Cpanel::AdminBin::Call::call(
                'Cpanel', 'market', 'PROVIDER_DNS_DCV_TEARDOWN',
                %opts{'provider'},
                provider_args => {
                    %{ $opts{'provider_args'} },
                    domains => $dns_dcv_domains,
                },
            );
        },
    );
}

sub _prevalidate_as_user {
    my ( $validate_fn, $opts_hr ) = @_;

    my $username = Cpanel::PwCache::getusername();
    if ( 'root' eq $username ) {
        die Cpanel::Exception::create('RootProhibited');
    }

    require Cpanel::PwCache;
    my $csr_parse = __PACKAGE__->can($validate_fn)->(
        $username,
        $opts_hr->{'provider_args'}{'csr'},
        $opts_hr->{'domain_dcv_method'},
    );

    return $csr_parse;
}

1;
