package Cpanel::Market::SSL::DCV;

# cpanel - Cpanel/Market/SSL/DCV.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Market::SSL::DCV

=head1 SYNOPSIS

See L<Cpanel::Market::SSL::DCV::Root> and L<Cpanel::Market::SSL::DCV::User>
for the actual interfaces to use.

=head1 DESCRIPTION

The addition of DNS-based DCV in v74 makes DCV setup for Market SSL purchases
significantly more complicated. This module encapsulates that complexity to
ensure that it’s correct and consistently applied.

Note that there’s nothing inherently “Market” about this logic; it would be
good in the future to refactor this to work as naturally for AutoSSL as for
Market. A “DCV provider” module would implement the interface that this
logic expects; the Market and AutoSSL provider modules would then refer to
their respective “DCV provider”.

This *may* only be useful for Comodo’s DCV process.

=head1 PRIVILEGED VS. UNPRIVILEGED

The main reason for the complexity of this logic is that whereas
HTTP setup happens as a user, DNS setup happens as root.
When running as root we can just drop privileges for the HTTP part,
but when running as the user we have to make an admin call to escalate
privileges for the DNS part.

(As implemented at the time of this writing,
the admin call just calls into the root logic in this same module.)

=head1 VALIDATION

To avoid duplication of logic, validation of the username and domains
(between both the CSR and the C<domain_dcv_method>) happens here. We verify
that the given domains all exist on the CSR, and for root-level operation
we verify that all of the given domains are ones that the user controls.

=head1 ERROR HANDLING

All functions in this module throw exceptions on error.

=cut

use Try::Tiny;

use Cpanel::Exception       ();
use Cpanel::Domain::Authz   ();
use Cpanel::Market          ();
use Cpanel::OrDie           ();
use Cpanel::Set             ();
use Cpanel::SSL::DCV::Utils ();

sub _prepare_for_dcv {
    my (%opts) = @_;

    my ( $http_domains_ar, $dns_domains_ar ) = Cpanel::SSL::DCV::Utils::dcv_method_hash_to_http_and_dns(
        $opts{'domain_dcv_method'},
    );

    my $provider_ns = Cpanel::Market::get_and_load_module_for_provider( $opts{'provider'} );

    require Cpanel::CommandQueue;
    my $queue_obj = Cpanel::CommandQueue->new();

    if (@$http_domains_ar) {
        $queue_obj->add(
            sub {
                my $setuid = $opts{'setuid_if_needed'}->();

                $provider_ns->can('prepare_system_for_domain_control_validation')->(
                    %{ $opts{'provider_args'} },
                    domains => $http_domains_ar,
                );
            },
            sub {
                my $setuid = $opts{'setuid_if_needed'}->();

                $provider_ns->can('undo_domain_control_validation_preparation')->(
                    %{ $opts{'provider_args'} },
                );
            },
            'undo HTTP DCV prep',
        );
    }

    if (@$dns_domains_ar) {
        $queue_obj->add(

            # This coderef argument should return another coderef
            $opts{'create_dns_dcv_setup_callback'}->( $provider_ns, $dns_domains_ar ),
        );
    }

    $queue_obj->run();

    return;
}

sub _undo_dcv_preparation {
    my (%opts) = @_;

    my ( $http_domains_ar, $dns_domains_ar ) = Cpanel::SSL::DCV::Utils::dcv_method_hash_to_http_and_dns(
        $opts{'domain_dcv_method'},
    );

    my $provider_ns = Cpanel::Market::get_and_load_module_for_provider( $opts{'provider'} );

    if (@$http_domains_ar) {
        try {
            my $setuid = $opts{'setuid_if_needed'}->();

            $provider_ns->can('undo_domain_control_validation_preparation')->(
                %{ $opts{'provider_args'} },
            );
        }
        catch { warn $_ };
    }

    if (@$dns_domains_ar) {
        try {
            $opts{'undo_dns_dcv_setup_callback'}->( $provider_ns, $dns_domains_ar );
        }
        catch { warn $_ };
    }

    return;
}

sub _validate_username_csr_and_domains_for_prepare {
    my ( $username, $csr, $domain_dcv_method_hr ) = @_;

    my $domains_ar = [ keys %$domain_dcv_method_hr ];

    my $csr_parse = _verify_that_csr_contains_all_given_domains(
        $csr, $domains_ar,
    );

    Cpanel::Domain::Authz::validate_user_control_of_domains__allow_wildcard(
        $username,
        $csr_parse->{'domains'},
    );

    _verify_that_all_csr_domains_are_given(
        $domains_ar,
        $csr_parse,
    );

    return;
}

sub _validate_username_csr_and_domains_for_undo {
    my ( $username, $csr, $domain_dcv_method_hr ) = @_;

    my $domains_ar = [ keys %$domain_dcv_method_hr ];

    my $csr_parse = _verify_that_csr_contains_all_given_domains(
        $csr, $domains_ar,
    );

    _verify_that_all_csr_domains_are_given(
        $domains_ar,
        $csr_parse,
    );

    my $unowned_ar = Cpanel::Domain::Authz::get_unowned_domains__allow_wildcard(
        $username,
        $csr_parse->{'domains'},
    );

    if (@$unowned_ar) {
        warn "DCV preparation undo: ignoring unowned domain(s) for user “$username”: @$unowned_ar";

        delete @{$domain_dcv_method_hr}{@$unowned_ar};
    }

    return;
}

sub _verify_that_csr_contains_all_given_domains {
    my ( $csr, $domains_ar ) = @_;

    require Cpanel::SSL::Utils;

    my $csr_parse = Cpanel::OrDie::multi_return(
        sub { Cpanel::SSL::Utils::parse_csr_text($csr) },
    );

    my @domains_not_on_csr = Cpanel::Set::difference(
        $domains_ar,
        $csr_parse->{'domains'},
    );

    if (@domains_not_on_csr) {

        # We don’t expect this to reach end users.
        die Cpanel::Exception->create_raw("CSR lacks domain(s) which is/are in “domain_dcv_method”: @domains_not_on_csr");
    }

    return $csr_parse;
}

sub _verify_that_all_csr_domains_are_given {
    my ( $domains_ar, $csr_parse_hr ) = @_;

    if ( !$domains_ar ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'domain_dcv_method' ] );
    }

    my @missing = Cpanel::Set::difference(
        $csr_parse_hr->{'domains'},
        $domains_ar,
    );

    if (@missing) {
        die Cpanel::Exception->create_raw("“domain_dcv_method” lacks domain(s) which is/are in CSR: @missing");
    }

    return;
}

1;
