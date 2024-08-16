package Cpanel::Security::Policy::PasswordAge::UI::JsonApi;

# cpanel - Cpanel/Security/Policy/PasswordAge/UI/JsonApi.pm
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
    my ( $self, $formref, $sec_ctxt, $cpconf_ref ) = @_;

    my $user;
    if ( $sec_ctxt->{'is_possessed'} ) {
        $user = $sec_ctxt->{'possessor'};
    }
    else {
        $user = $sec_ctxt->{'user'};
    }
    $user =~ /([\w\-]+)/;
    $user = $1;

    my $days_since_change = int( time / ( 60 * 60 * 24 ) - $sec_ctxt->{'pass_change_time'} );

    my $policy = $self->{'policy'};
    my $msg    = join(
        ' ',
        lh()->maketext( 'You have not changed your password in [quant,_1,day,days].',                                                                            $days_since_change ),
        lh()->maketext( 'The current security policy requires that you change your password every [quant,_1,day,days] to avoid your account being compromised.', $policy->conf_value( $cpconf_ref, 'maxage' ) ),
    );

    Cpanel::SecurityPolicy::UI::json_simple_errormsg($msg);
    return {};
}

1;
