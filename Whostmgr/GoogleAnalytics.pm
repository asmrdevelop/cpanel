
# cpanel - Whostmgr/GoogleAnalytics.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::GoogleAnalytics;

use strict;
use warnings;

use Cpanel::Encoder::URI;

=head1 Whostmgr::GoogleAnalytics

Library for appending UTM tags to purchase URLs in WHM

=head2 STRING query_string = utm_tags( STRING host, STRING app, STRING campaign, BOOL in_query_string)

Produce an approriate UTM tag query string for google analytics use in WHM.
Optionally can be used as part of another query string via the in_query_string parameter.

=cut

sub utm_tags {
    my ( $host, $app, $campaign, $in_query_string ) = map { Cpanel::Encoder::URI::uri_encode_str($_) // '' } @_;
    my $fragment = $in_query_string ? '&' : '?';
    $fragment .= "utm_source=$host&utm_medium=$app&utm_campaign=$campaign";
    return $fragment;
}

1;
