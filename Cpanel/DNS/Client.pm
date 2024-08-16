package Cpanel::DNS::Client;

# cpanel - Cpanel/DNS/Client.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DNS::Client

=head1 SYNOPSIS

    my @non_tlds = Cpanel::DNS::Client::get_possible_registered("foo.bar.com");

=cut

#----------------------------------------------------------------------

use Cpanel::PublicSuffix ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @non_tlds = get_possible_registered( $DOMAIN )

Returns all of the possible registered domains among $DOMAIN and its
parent domains, sorted longest-first.

For example, if the input is C<foo.bar.gc.ca>, the return will be
C<foo.bar.gc.ca> and C<bar.gc.ca>.

This function uses the Public Suffix list to determine whether
a given name is a TLD.

If called in scalar context, this returns the number of
domains that would be returned in list context.

=cut

sub get_possible_registered ($domain) {

    _trim_wildcard( \$domain );

    my @names;

    my @pieces = split m<\.>, $domain;

    my $found_registered;

    for my $n ( 0 .. $#pieces ) {
        my $name = join( '.', @pieces[ ( $#pieces - $n ) .. $#pieces ] );

        $found_registered ||= !Cpanel::PublicSuffix::domain_isa_tld($name);

        unshift @names, $name if $found_registered;
    }

    return @names;
}

#----------------------------------------------------------------------

=head2 @tlds = get_possible_tlds( $DOMAIN )

This compares $DOMAIN and all of its parent domains against the
Public Suffix list; any such name that is a TLD is returned in the
return list. The list is ordered longest-first.

For example, as of July 2020 C<canada.gc.ca> yields a return of
C<gc.ca> and C<ca>.

If called in scalar context, this returns the number of
domains that would be returned in list context.

=cut

sub get_possible_tlds ($domain) {
    my @labels = split m<\.>, $domain;

    my @tlds;
    for my $n ( 0 .. $#labels ) {
        my @labels2 = @labels;

        my @these_labels = splice( @labels2, -1 - $n );
        my $name         = join '.', @these_labels;

        if ( Cpanel::PublicSuffix::domain_isa_tld($name) ) {
            unshift @tlds, $name;
        }
        else {
            last;
        }
    }

    return @tlds;
}

#----------------------------------------------------------------------

=head2 @possible = get_possible_registered_or_tld( $DOMAIN )

Like C<get_possible_registered()>, but if $DOMAIN is itself a TLD,
the returned list will consist of $DOMAIN rather than being empty.

This isn’t as crazy as it sounds because
L<the public suffix list|https://publicsuffix.org/> includes wildcards,
which means that—as of this writing, anyway—names like L<hjjh.mm>
and L<cpanelrocks.bd> are TLDs.

=cut

sub get_possible_registered_or_tld ($domain) {
    _trim_wildcard( \$domain );

    my @possible = get_possible_registered($domain);

    @possible = ($domain) if !@possible;

    return @possible;
}

#----------------------------------------------------------------------

sub _trim_wildcard ($domain_sr) {
    substr( $$domain_sr, 0, 2, q<> ) if 0 == rindex( $$domain_sr, '*.', 0 );

    return;
}

1;
