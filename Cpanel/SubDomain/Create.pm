package Cpanel::SubDomain::Create;

# cpanel - Cpanel/SubDomain/Create.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SubDomain::Create - Subdomain creation logic, aggregated

=head1 SYNOPSIS

    my ($ok, $why) = Cpanel::SubDomain::Create::create_with_phpfpm_setup(
        'the.sublabels',
        'parent-domain.com',
        %other_opts_to_addsubdomain,
    );

=head1 DESCRIPTION

This module wraps the domain creation logic in L<Cpanel::Sub> such that
things like PHP-FPM setup are also included.

It is suggested that new interfaces that create subdomains should use
this module rather than calling directly into L<Cpanel::Sub>. Moreover,
ideally the different subdomain-creating interfaces could unify more
of their logic and put it into this module.

=cut

#----------------------------------------------------------------------

use Cpanel::PHPFPM::Config ();
use Cpanel::RedirectFH     ();
use Cpanel::Sub            ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ($ok, $why) = create_with_phpfpm_setup( $SUB_PART, $PARENT_DOMAIN, %OPTS )

Creates a subdomain and “does the needful” with PHP-FPM for the new web vhost.
%OPTS are the values to give to L<Cpanel::Sub>’s C<addsubdomain()> function,
which this function calls internally.

Returns two scalars: 1) Whether subdomain creation succeeded (boolean),
and 2) if it failed, the reason why (as a string).

=cut

sub create_with_phpfpm_setup ( $sub_part, $parent_domain, @opts_kv ) {    ## no critic qw(ManyArgs) - mis-parse
    my ( $ok, $result ) = create_without_phpfpm_setup( $sub_part, $parent_domain, @opts_kv );

    if ( $ok && Cpanel::PHPFPM::Config::get_default_accounts_to_fpm() ) {
        _do_phpfpm( $sub_part, $parent_domain );
    }

    return ( $ok, $result );
}

=head2 ($ok, $why) = create_without_phpfpm_setup( $SUB_PART, $PARENT_DOMAIN, %OPTS )

Like C<create_with_phpfpm_setup()> but without the PHP-FPM setup. Note that
this is B<NOT> merely a simple wrapper; anything that creates subdomains
should probably call this rather than calling C<addsubdomain()> directly.

=cut

sub create_without_phpfpm_setup ( $sub_part, $parent_domain, @opts_kv ) {    ## no critic qw(ManyArgs) - mis-parse
    my $redirect = Cpanel::RedirectFH->new( \*STDOUT => \*STDERR );

    return Cpanel::Sub::addsubdomain(
        rootdomain => $parent_domain,
        subdomain  => $sub_part,

        @opts_kv,
    );
}

sub _do_phpfpm ( $sub_part, $parent_domain ) {
    my $full_domain_name = "$sub_part.$parent_domain";

    require Cpanel::PHPFPM::ConvertAll;

    Cpanel::PHPFPM::ConvertAll::queue_convert_domain($full_domain_name);

    return;
}

1;
