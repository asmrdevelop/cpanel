package Cpanel::WildcardDomain;

# cpanel - Cpanel/WildcardDomain.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WildcardDomain

=head1 DESCRIPTION

There are more functions here than the POD currently lists;
see the code for details.

=cut

#----------------------------------------------------------------------

use Cpanel::ArrayFunc::Uniq      ();
use Cpanel::WildcardDomain::Tiny ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=cut

our $PREFIX = '_wildcard_';

my $old_prefix = 'wildcard_safe';

*contains_wildcard_domain = *Cpanel::WildcardDomain::Tiny::contains_wildcard_domain;
*is_wildcard_domain       = *Cpanel::WildcardDomain::Tiny::is_wildcard_domain;

# This function should be used for log paths, file paths, and the ServerName directive in apache
sub encode_wildcard_domain {
    return $_[0]   if index( $_[0], '*' ) == -1;
    return $PREFIX if $_[0] eq '*';
    return $_[0] =~ s/^\*\./$PREFIX./ro;
}

# This function should be only be used for the custom vhost include path in apache
# There were other legacy encoding formats, but this is the only one still in use
sub encode_legacy_wildcard_domain {
    return $_[0]       if index( $_[0], '*' ) == -1;
    return $old_prefix if $_[0] eq '*';
    return $_[0] =~ s{\A\*\.}{$old_prefix\.}ro;
}

# This will decode either the current or legacy wildcard encoding
sub decode_wildcard_domain {
    return $_[0] if index( $_[0], '_' ) == -1;
    return $_[0] =~ s/^(?:$PREFIX|$old_prefix)\./*./ro;
}

sub strip_wildcard {
    return $_[0] =~ s{\A(?:\*|$PREFIX|$old_prefix)\.}{}ro;
}

sub safe_domain {
    my $domain = shift;
    return unless defined $domain;
    return encode_wildcard_domain($domain) if is_wildcard_domain($domain);
    return $domain;
}

#
# Returns 1 if the domains match
# Returns 0 if no match
#
# This function understands wildcards
# and will permit matching a domain to a wildcard domain
# (ex.  dog.koston.org  == *.koston.org)
#
# Note that *.koston.org does NOT match koston.org!
#
sub wildcard_domains_match {
    my ( $domain_1, $domain_2 ) = @_;

    return 1 if $domain_1 eq $domain_2;

    # must have the same number of dots to match
    return 0 if ( $domain_1 =~ tr/\.// ) != ( $domain_2 =~ tr/\.// );

    if ( substr( $domain_1, 0, 2 ) eq '*.' ) {

        # possible_wildcard AKA $domain_1 *.cowpig.org becomes cowpig.org
        # domain_to_match AKA $domain_2 dog.cowpig.org becomes cowpig.org
        return 1 if substr( $domain_1, 1 ) eq substr( $domain_2, index( $domain_2, '.' ) );
    }
    elsif ( substr( $domain_2, 0, 2 ) eq '*.' ) {

        # possible_wildcard AKA $domain_2 *.cowpig.org becomes cowpig.org
        # domain_to_match AKA $domain_1 dog.cowpig.org becomes cowpig.org

        return 1 if substr( $domain_2, 1 ) eq substr( $domain_1, index( $domain_1, '.' ) );
    }

    return 0;
}

#----------------------------------------------------------------------

=head2 @wc_domains = to_wildcards( @DOMAINS )

Replaces @DOMAINS with substitutive wildcards, eliminates duplicate
wildcards, and returns the result.

NB: Behavior is undefined if any member of @DOMAINS isn’t a domain.

=cut

sub to_wildcards (@domains) {
    substr( $_, 0, index( $_, '.' ), '*' ) for @domains;

    return Cpanel::ArrayFunc::Uniq::uniq(@domains);
}

#----------------------------------------------------------------------

1;    # Magic true value required at end of module
