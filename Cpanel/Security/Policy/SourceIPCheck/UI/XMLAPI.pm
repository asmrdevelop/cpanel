package Cpanel::Security::Policy::SourceIPCheck::UI::XMLAPI;

# cpanel - Cpanel/Security/Policy/SourceIPCheck/UI/XMLAPI.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::SecurityPolicy::UI ();
use Cpanel::Locale::Lazy 'lh';

sub new {
    my ( $class, $policy ) = @_;
    die "No policy object supplied.\n" unless defined $policy;
    return bless { 'policy' => $policy }, $class;
}

sub process {
    my ( $self, $formref, $sec_ctxt ) = @_;

    my $user;
    if ( $sec_ctxt->{'is_possessed'} ) {
        $user = $sec_ctxt->{'possessor'};
    }
    else {
        $user = $sec_ctxt->{'user'};
    }
    $user =~ /([\w\-]+)/;
    $user = $1;
    $user =~ s/\///g;

    Cpanel::SecurityPolicy::UI::xml_simple_errormsg( lh()->maketext('You are logging in from an unrecognized computer or network.') );

    return {};
}

1;
