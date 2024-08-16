package Whostmgr::UI::Authz;

# cpanel - Whostmgr/UI/Authz.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::UI::Authz

=head1 SYNOPSIS

    my $can_load_yn = Whostmgr::UI::Authz::url_is_allowed('/scripts/tweaksettings');

=head1 DESCRIPTION

This module provides easy logic to enforce UI authorization—i.e., whether
a given UI is usable (by the current WHM user).

=cut

#----------------------------------------------------------------------

use Whostmgr::DynamicUI::Loader ();
use Whostmgr::Theme             ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = url_is_allowed( $URL )

Returns a boolean that indicates whether the application at the given C<$URL>
is available to the current user.

C<$URL> should match a C<url> entry in the current WHM theme’s
F<dynamicui.conf>. (NB: The default WHM one is at
F</usr/local/cpanel/whostmgr/docroot/themes/x/dynamicui.conf>.)

=cut

sub url_is_allowed {
    my ($url) = @_;

    my $dynui_data = _load_and_filter( Whostmgr::Theme::getthemedir() . '/dynamicui.conf' );

    return ( grep { $_->{'url'} eq $url } map { @{ $_->{'items'} } } @{ $dynui_data->{'groups'} } ) && 1;
}

# mocked in tests
*_load_and_filter = \*Whostmgr::DynamicUI::Loader::load_and_filter;

1;
