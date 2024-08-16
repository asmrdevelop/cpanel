package Cpanel::App;

# cpanel - Cpanel/App.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::App - Authoritative source for determination of cpsrvd application

=head1 SYNOPSIS

    if ( Cpanel::App::is_cpanel() ) {
        # ...
    }

    if ( Cpanel::App::is_whm() ) {
        # ...
    }

    if ( Cpanel::App::is_webmail() ) {
        # ...
    }

    my $appname = Cpanel::App::get_normalized_name();

    my $pretty = Cpanel::App::get_context_display_name();

=head1 DESCRIPTION

This module provides authoritative logic for determining whether the
running cpsrvd application is cPanel, WHM, or Webmail.

You should B<NOT> access global scalars like C<$Cpanel::appname> to
discern this information; use this module’s functions instead.

=cut

#----------------------------------------------------------------------

# Don’t access this directly; use the functions that this module exposes.
our $appname;

BEGIN {
    $appname = 'cpanel';
}

our $context = q{};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 is_cpanel()

Returns a boolean that indicates whether the current application is
cPanel or not.

=cut

sub is_cpanel {
    return ( $appname eq 'cpanel' || $appname eq 'cpaneld' ) ? 1 : 0;
}

=head2 is_webmail()

Like C<is_cpanel()> but for Webmail.

=cut

sub is_webmail {
    return ( $appname eq 'webmail' || $appname eq 'webmaild' ) ? 1 : 0;
}

=head2 is_whm()

Like C<is_cpanel()> but for WHM.

=cut

sub is_whm {
    return ( ( $appname eq 'whostmgr' ) || ( $appname eq 'whm' ) || ( $appname eq 'whostmgrd' ) ) ? 1 : 0;
}

#----------------------------------------------------------------------

=head2 get_normalized_name()

Returns a “normalized” form of the current application’s name.
The forms are: C<cpanel>, C<whostmgr>, and C<webmail>.

(Regrettably, C<whostmgr> is inconsistent with the function name
C<is_whm()>.)

=cut

sub get_normalized_name {
    return is_cpanel() ? 'cpanel' : is_whm() ? 'whostmgr' : is_webmail() ? 'webmail' : die "Unknown appname: “$appname”!";
}

#----------------------------------------------------------------------

=head2 get_context_display_name()

Like C<get_normalized_name()> but returns a display-worthy form of the name.
The forms are undocumented (by design); do not write code that attempts
to parse them, as they may change in the future.

=cut

sub get_context_display_name {
    if ( is_webmail() ) {
        return 'Webmail';
    }
    elsif ( is_whm() ) {
        return 'WHM';
    }
    else {
        return "cPanel";
    }
}

1;
