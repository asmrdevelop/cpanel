package Cpanel::SecurityPolicy::Default::UI::JsonApi;

# cpanel - Cpanel/SecurityPolicy/Default/UI/JsonApi.pm
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
    my ( $self, $acctref, $formref ) = @_;

    main::json_header();

    my $error_string = qq({"data":{"reason":"@{[$self->{'policy'}->name]} check failed","result":"0"},"error":"@{[$self->{'policy'}->name]} check failed","type":"text"});

    if ( $formref && $formref->{'cpanel_jsonapi_apiversion'} eq '2' ) {

        #json api is only wrapped in cpanelresult for api2
        $error_string = qq[{"cpanelresult":$error_string}];
    }
    print $error_string . "\r\n";
    return;
}

1;
