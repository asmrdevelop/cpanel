package Cpanel::SecurityPolicy::Default::UI::HTML;

# cpanel - Cpanel/SecurityPolicy/Default/UI/HTML.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::SecurityPolicy::UI ();

sub new {
    my ( $class, $policy ) = @_;
    die "No policy object supplied.\n" unless defined $policy;
    return bless { 'policy' => $policy }, $class;
}

sub process {
    my ($self) = @_;

    Cpanel::SecurityPolicy::UI::html_header();
    print qq(<h1>@{[$self->{'policy'}->name]} check failed.</h1>);
    Cpanel::SecurityPolicy::UI::html_footer();

    return;
}

1;
