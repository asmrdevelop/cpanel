
# cpanel - Cpanel/Exception/Store/PartialSuccess.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Exception::Store::PartialSuccess;

use strict;
use warnings;

use parent               qw( Cpanel::Exception );
use Cpanel::LocaleString ();

=head1 NAME

Cpanel::Exception::Store::PartialSuccess

=head1 DESCRIPTION

Used for communicating non-fatal error information back to the caller when a cPanel Store
related operation encounters a problem that should be reported to the user without being
considered a full failure.

This exception is caught and handled by C<Whostmgr::Store>, which converts it into an
altered success message with additional detail.

=head1 SYNOPSIS

  use Cpanel::Exception;

  ...

  important_operation()
    or die 'The important thing failed';

  less_important_operation()
    or die Cpanel::Exception::create(
        'Store::PartialSuccess',
        [
            detail => 'The less important thing failed',
        ],
    );

=head1 METHODS

=head2 _default_phrase()

The default phrase should not be used in practice. Instead, your application
should check for this exception, pull the detail out using the C<detail()>
method, and insert it into a better, application-specific message.

=cut

sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The [asis,cPanel Store] operation partially succeeded: [_1]',
        $self->detail,
    );
}

=head2 detail()

Returns a string containing the additional detail about what failed.

=cut

sub detail {
    my ($self) = @_;
    return $self->get('detail');
}

1;
