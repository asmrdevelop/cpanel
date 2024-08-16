package Cpanel::API::DCV;

# cpanel - Cpanel/API/DCV.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Imports;

use Cpanel::JSON                 ();
use Cpanel::SSL::DCV             ();
use Cpanel::WildcardDomain::Tiny ();

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::API::DCV

=head1 FUNCTIONS

=head2 check_domains_via_http

This accepts a list of C<domain>s (C<domain>, C<domain-1>, etc.)
and DCV file constraints and returns a hash for each domain:

    {
        redirects_count => the number of HTTP redirects that the DCV check followed

        failure_reason => {
            - undef, if the domain has 1+ domains on the server and 0 elsewhere
            - string: which DCV criteria are not met
        }
    }

So, if I pass in:

=over

=item C<domain> = C<this-resolves.com>

=item C<domain-1> = C<redirects-then-does-not-resolve.com>

=item C<domain-2> = C<resolves-after-redirects.com>

=back

… I’ll get back something like:

    [
        {
            failure_reason => undef,
            redirects_count => 0,
            redirects => [],
        },
        {
            failure_reason => 'This is why I don’t like your domain …',
            redirects_count => 1,
            redirects => [
                { .. }, #cf. HTTP::Tiny’s “redirects”
            ],
        },
        {
            failure_reason => undef,
            redirects_count => 2,
            redirects => [ .. ],
        },
    ]

The (optional) DCV file constraint inputs are as follows:

=over

=item C<dcv_file_allowed_characters> - A JSON-encoded arrayref of characters that can be in the random part of the DCV filename

=item C<dcv_file_random_character_count> - An integer that represents the number of characters in the random part of the DCV filename

=item C<dcv_file_extension> - The extension, if any, of the DCV file.

=item C<dcv_file_relative_path> - The subdirectory relative to the domain’s document root where to create the DCV file

=item C<dcv_user_agent_string> - The HTTP user agent string to use for DCV.

=item C<dcv_max_redirects> - The maximum number of HTTP redirects the provider allows

=back

=cut

sub check_domains_via_http {
    my ( $args, $result ) = @_;

    my @domains = _get_input_domains($args);

    my @wildcards = grep { Cpanel::WildcardDomain::Tiny::is_wildcard_domain($_) } @domains;
    if (@wildcards) {
        $result->raw_error( locale()->maketext( 'You submitted [quant,_1,wildcard domain,wildcard domains]: [list_and_quoted,_2]. Certificate authorities no longer accept [asis,HTTP]-based [output,abbr,DCV,Domain Control Validation] for wildcard domains.', 0 + @wildcards, \@wildcards ) );
        return 0;
    }

    my @result = Cpanel::SSL::DCV::verify_domains(
        domains => \@domains,
        %{ _get_dcv_config_args($args) },
    );

    delete $_->{'lacks_docroot'} for @result;

    $result->data( \@result );

    return 1;
}

=head2 check_domains_via_dns

Similar to C<check_domains_via_http>, but does a DNS-based DCV check instead.
This follows the logic in L<Cpanel::SSL::DCV::DNS>.

The inputs are:

=over

=item C<domain>* - The domain(s) to verify.

=back

The return is an array of hash references. It’s the same array as
C<Cpanel::SSL::DCV::DNS::User::verify_domains()> returns, but with
C<domain> added to each hash as a convenience.

=cut

sub check_domains_via_dns {
    my ( $args, $result ) = @_;

    my @domains = _get_input_domains($args);

    local $SIG{'__WARN__'} = sub {
        $result->raw_message( shift() );
    };

    require Cpanel::SSL::DCV::DNS::User;
    my $dcv_ar = Cpanel::SSL::DCV::DNS::User::verify_domains(
        domains => \@domains,
    );

    #A courtesy to API callers.
    for my $idx ( 0 .. $#domains ) {
        $dcv_ar->[$idx]{'domain'} = $domains[$idx];
        if ( $dcv_ar->[$idx]{'failure_reason'} && try { $dcv_ar->[$idx]{'failure_reason'}->isa('Cpanel::LocaleString') } ) {
            $dcv_ar->[$idx]{'failure_reason'} = $dcv_ar->[$idx]{'failure_reason'}->to_string();
        }
    }

    $result->data($dcv_ar);

    return 1;
}

sub _get_input_domains {
    my ($args) = @_;
    return $args->get_length_required_multiple('domain');
}

#----------------------------------------------------------------------

# Like check_domains_via_http(), but only returns a list of error strings
# (or undef for no error).
#
# This function is left in for legacy compatibility but should no longer
# be used. The additional information from check_domains_via_http()
# is always relevant.
#
sub ensure_domains_can_pass_dcv {
    my ( $args, $result ) = @_;

    my @domains = _get_input_domains($args);

    my @verif = Cpanel::SSL::DCV::verify_domains(
        domains => \@domains,
        %{ _get_dcv_config_args($args) },
    );

    $result->data( [ map { $_->{'failure_reason'} } @verif ] );

    return 1;
}

sub _get_dcv_config_args {
    my ($args) = @_;

    my $dcv_file_allowed_characters = $args->get('dcv_file_allowed_characters');

    $dcv_file_allowed_characters = Cpanel::JSON::Load($dcv_file_allowed_characters) if length $dcv_file_allowed_characters;

    return {
        dcv_file_extension              => ( $args->get('dcv_file_extension')              || '' ),
        dcv_file_random_character_count => ( $args->get('dcv_file_random_character_count') || '' ),
        dcv_file_relative_path          => ( $args->get('dcv_file_relative_path')          || '' ),
        dcv_user_agent_string           => ( $args->get('dcv_user_agent_string')           || '' ),
        dcv_max_redirects               => ( $args->get('dcv_max_redirects')               || '' ),
        dcv_file_allowed_characters     => ( $dcv_file_allowed_characters                  || '' ),
    };
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    check_domains_via_dns => $allow_demo,
);

1;
