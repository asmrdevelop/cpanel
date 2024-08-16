package Cpanel::SecurityPolicy::Default::UI::Text;

# cpanel - Cpanel/SecurityPolicy/Default/UI/Text.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use warnings;
use strict;

use Cpanel::Locale ();

sub new {
    my ( $class, $policy ) = @_;
    die "No policy object supplied.\n" unless defined $policy;
    return bless { 'policy' => $policy }, $class;
}

sub process {
    my ($self) = @_;

    main::text_header();
    print qq(@{[$self->{'policy'}->name]} check failed.);

    return;
}

1;
