package Cpanel::DNS::Unbound::Singleton;

# cpanel - Cpanel/DNS/Unbound/Singleton.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 Cpanel::DNS::Unbound::Singleton

Cpanel::DNS::Unbound::Singleton - Cached L<DNS::Unbound> instance

=head1 SYNOPSIS

    my $unbound = Cpanel::DNS::Unbound::Singleton::get();

=head1 DESCRIPTION

This module creates a globally-cached L<DNS::Unbound> instance
that different wrappers around that module can use. Having everything that
uses DNS::Unbound call this module ensures optimal use of libunbound’s
caching.

=cut

#----------------------------------------------------------------------

use DNS::Unbound                            ();
use Cpanel::DNS::Unbound::Workarounds::Read ();
use Cpanel::DNS::Unbound::ResolveMode       ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $obj = get()

Returns the module’s cached DNS::Unbound instance.

=cut

my $unbound_obj;
my $mock;

my $tried_to_load_mock;
my $can_mock;

sub get {
    $tried_to_load_mock ||= do {
        local $@;
        eval {

            # This defeats the check-module-shipped build check:
            my $to_require = 'Cpanel/SSL/DCV/Mock.pm';
            require $to_require;
            $can_mock = 1;
        };
        1;
    };

    if ( !$unbound_obj ) {
        $unbound_obj = DNS::Unbound->new()->enable_threads();
        Cpanel::DNS::Unbound::Workarounds::Read::enable_workarounds_on_unbound_object($unbound_obj);

        Cpanel::DNS::Unbound::ResolveMode::set_up($unbound_obj);

        $mock = $can_mock && Cpanel::SSL::DCV::Mock::create_mock_if_configured($unbound_obj);    # PPI NO PARSE - only loaded in dev environment
    }

    return $unbound_obj;
}

=head2 clear()

Deletes the module’s cached DNS::Unbound instance. Nothing is returned.

=cut

sub clear {
    undef $mock;
    undef $unbound_obj;

    return;
}

END {
    clear();
}

1;
