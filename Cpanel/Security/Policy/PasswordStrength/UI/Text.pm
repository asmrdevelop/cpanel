package Cpanel::Security::Policy::PasswordStrength::UI::Text;

# cpanel - Cpanel/Security/Policy/PasswordStrength/UI/Text.pm
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

    Cpanel::SecurityPolicy::UI::json_simple_errormsg( lh()->maketext('You cannot use the password that you selected because it is too weak and is too easy to guess.') . ' ' . lh()->maketext('Change your password [output,em,now] to ensure that your account remains secure.') );

    return {};
}

1;
