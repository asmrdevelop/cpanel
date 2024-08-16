package Cpanel::Template::Plugin::Quotesafe;

# cpanel - Cpanel/Template/Plugin/Quotesafe.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 DEPRECATED

DO NOT USE THIS MODULE.

Instead use the template toolkit built-in VMethods "dquote" and/or "squote".

http://www.template-toolkit.org/docs/manual/VMethods.html#section_dquote

http://www.template-toolkit.org/docs/manual/VMethods.html#section_squote

=cut

use strict;

use Cpanel::Logger ();

use base 'Template::Plugin::Filter';

my $logger = Cpanel::Logger->new();

sub filter {
    my ( $self, $string ) = @_;
    $logger->deprecated('Deprecated Template Toolkit plugin Quotesafe called.');
    $string =~ s/'/&#39;/g;
    $string =~ s/"/&#34;/g;
    return $string;
}

1;
