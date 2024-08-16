package Cpanel::Security::Policy::PasswordAge::UI::XMLAPI;

# cpanel - Cpanel/Security/Policy/PasswordAge/UI/XMLAPI.pm
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
    my ( $self, $formref, $sec_ctxt, $cpconf_ref ) = @_;

    my $days_since_change = int( time / ( 60 * 60 * 24 ) - $sec_ctxt->{'pass_change_time'} );

    my $user;
    if ( $sec_ctxt->{'is_possessed'} ) {
        $user = $sec_ctxt->{'possessor'};
    }
    else {
        $user = $sec_ctxt->{'user'};
    }
    $user =~ /([\w\-]+)/;
    $user = $1;

    my $policy        = $self->{'policy'};
    my %template_vars = (
        'days_since_change' => $days_since_change,
        'maxage'            => $policy->conf_value( $cpconf_ref, 'maxage' ),
        'policyuser'        => $user,
    );

    Cpanel::SecurityPolicy::UI::xml_header();
    Cpanel::SecurityPolicy::UI::process_template( 'PasswdAge/main.xml.tmpl', \%template_vars );

    return {};
}

1;
