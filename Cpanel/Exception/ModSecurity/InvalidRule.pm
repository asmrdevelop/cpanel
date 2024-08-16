
# cpanel - Cpanel/Exception/ModSecurity/InvalidRule.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Exception::ModSecurity::InvalidRule;

use strict;
use warnings;

use parent 'Cpanel::Exception';

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self)  = @_;
    my ($error) = @{ $self->{'_metadata'} }{qw(error)};
    return Cpanel::LocaleString->new( 'The rule is invalid. [asis,Apache] returned the following error: [_1]', $error );
}

1;
