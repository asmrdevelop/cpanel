package Cpanel::SecurityPolicy::Default::UI::XMLAPI;

# cpanel - Cpanel/SecurityPolicy/Default/UI/XMLAPI.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Locale ();

sub new {
    my ( $class, $policy ) = @_;
    die "No policy object supplied.\n" unless defined $policy;
    return bless { 'policy' => $policy }, $class;
}

sub process {
    my ($self) = @_;

    main::xml_header();
    print qq(<?xml version="1.0" ?><cpanelresult>\n<error>@{[$self->{'policy'}->name]} check failed.</error><data>\n<result>0</result>\n<reason>@{[$self->{'policy'}->name]} check failed.</reason>\n</data>\n</cpanelresult>);

    return;
}

1;
