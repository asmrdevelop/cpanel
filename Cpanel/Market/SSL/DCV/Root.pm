package Cpanel::Market::SSL::DCV::Root;

# cpanel - Cpanel/Market/SSL/DCV/Root.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Market::SSL::DCV::Root

=head1 SYNOPSIS

    Cpanel::Market::SSL::DCV::prepare_for_dcv(...);
    Cpanel::Market::SSL::DCV::undo_dcv_preparation(...);

    Cpanel::Market::SSL::DCV::prepare_for_dns_dcv(...);
    Cpanel::Market::SSL::DCV::undo_dns_dcv_preparation(...);

=head1 DESCRIPTION

This module contains root’s logic for DCV setup. See
L<Cpanel::Market::SSL::DCV> for some general notes on DCV.

=head1 FUNCTIONS

=head2 prepare_for_dcv( %OPTS )

Does a DCV preparation (HTTP and DNS) as root. %OPTS are (all required):

=over

=item * C<provider> - string (e.g., C<cPStore>)

=item * C<username>

=item * C<provider_args> - hash reference; key/value pairs that are passed to
as arguments to the provider’s C<prepare_system_for_domain_control_validation()>
and C<install_dcv_dns_entries()> functions, minus the C<domains> argument.

=item * C<domain_dcv_method> - hash reference; keys are domain names,
and the values are either C<http> or C<dns>. The set of keys must exactly
match the set of domains on the csr.

=back

=cut

use parent qw( Cpanel::Market::SSL::DCV );

use Cpanel::Domain::Authz ();
use Cpanel::Market        ();
use Cpanel::Set           ();

sub prepare_for_dcv {
    my (%opts) = @_;

    die 'Need “username”!' if !$opts{'username'};

    my $csr = $opts{'provider_args'}{'csr'};

    my $csr_parse = __PACKAGE__->can('_validate_username_csr_and_domains_for_prepare')->( $opts{'username'}, $csr, $opts{'domain_dcv_method'} );

    return __PACKAGE__->can('_prepare_for_dcv')->(
        setuid_if_needed              => _get_setuid_cr( \%opts ),
        create_dns_dcv_setup_callback => sub {
            my ( $provider_ns, $dns_dcv_domains ) = @_;

            return sub {
                $provider_ns->can('install_dcv_dns_entries')->(
                    %{ $opts{'provider_args'} },
                    domains => $dns_dcv_domains,
                );
            };
        },

        # %opts must be last since we allow the caller
        # to provide an alternate create_dns_dcv_setup_callback which
        # can be used to prevent dns dcv from being resetup every time
        # autossl polls
        %opts,
    );
}

=head2 undo_dcv_preparation( %OPTS )

Undoes a DCV preparation (HTTP and DNS) as root. %OPTS is the same as
for C<prepare_for_dcv_as_root()>, with the following differences:

=over

=item * C<provider_args> is sent to the provider’s
C<undo_domain_control_validation_preparation()> function.

=item * Unowned domains in C<domain_dcv_method> prompt a warning but are
not treated as fatal.

=back

=cut

sub undo_dcv_preparation {
    my (%opts) = @_;

    die 'Need “username”!' if !$opts{'username'};

    my $csr = $opts{'provider_args'}{'csr'};

    __PACKAGE__->can('_validate_username_csr_and_domains_for_undo')->(
        $opts{'username'},
        $csr,
        $opts{'domain_dcv_method'},
    );

    return __PACKAGE__->can('_undo_dcv_preparation')->(
        %opts,
        setuid_if_needed            => _get_setuid_cr( \%opts ),
        undo_dns_dcv_setup_callback => sub {
            my ( $provider_ns, $dns_dcv_domains ) = @_;

            $provider_ns->can('remove_dcv_dns_entries')->(
                %{ $opts{'provider_args'} },
                domains => $dns_dcv_domains,
            );
        },
    );
}

sub _get_setuid_cr {
    my ($opts_hr) = @_;

    my $username = $opts_hr->{'username'} or die 'need “username”';

    require Cpanel::AccessIds::ReducedPrivileges;

    return sub {
        return Cpanel::AccessIds::ReducedPrivileges->new($username);
    };
}

#----------------------------------------------------------------------

=head2 prepare_for_dns_dcv( %OPTS )

Does a DNS DCV preparation (as root). %OPTS are similar to
those for C<prepare_for_dcv_as_root()>, but without the C<domain_dcv_method>
argument, and C<provider_args> must include C<domains>. All CSR domains
must be owned by the user, and all C<domains> must be on the CSR.

=cut

sub prepare_for_dns_dcv {
    my (%opts) = @_;

    die 'Need “username”!' if !$opts{'username'};

    my $csr_parse = __PACKAGE__->can('_verify_that_csr_contains_all_given_domains')->(
        @{ $opts{'provider_args'} }{ 'csr', 'domains' },
    );

    Cpanel::Domain::Authz::validate_user_control_of_domains__allow_wildcard(
        $opts{'username'},
        $csr_parse->{'domains'},
    );

    _dns_dcv_action(
        'install_dcv_dns_entries',
        \%opts,
    );

    return;
}

=head2 undo_dns_dcv_preparation( %OPTS )

The reverse of C<prepare_for_dns_dcv()>. Takes the same arguments, but
unowned domains in the CSR are nonfatal. Unowned C<domains> in C<provider_args>
are removed prior to the call into the provider’s C<remove_dcv_dns_entries()>
function. (The actual passed-in data structure is unaltered.)

=cut

sub undo_dns_dcv_preparation {
    my (%opts) = @_;

    die 'Need “username”!' if !$opts{'username'};

    my $csr_parse = __PACKAGE__->can('_verify_that_csr_contains_all_given_domains')->(
        @{ $opts{'provider_args'} }{ 'csr', 'domains' },
    );

    my $unowned_given_ar = Cpanel::Domain::Authz::get_unowned_domains__allow_wildcard(
        $opts{'username'},
        $opts{'provider_args'}{'domains'},
    );

    my $substitute_domains;

    if (@$unowned_given_ar) {
        warn "DNS DCV preparation undo: ignoring unowned domain(s) for user “$opts{'username'}”: @$unowned_given_ar";

        $substitute_domains = [
            Cpanel::Set::difference(
                $opts{'provider_args'}{'domains'},
                $unowned_given_ar,
            ),
        ];
    }

    local $opts{'provider_args'}{'domains'} = $substitute_domains if $substitute_domains;

    _dns_dcv_action(
        'remove_dcv_dns_entries',
        \%opts,
    );

    return;
}

sub _dns_dcv_action {
    my ( $func, $opts_hr ) = @_;

    my $provider_ns = Cpanel::Market::get_and_load_module_for_provider( $opts_hr->{'provider'} );

    $provider_ns->can($func)->( %{ $opts_hr->{'provider_args'} } );

    return;
}

1;
