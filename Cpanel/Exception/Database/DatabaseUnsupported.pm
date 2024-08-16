package Cpanel::Exception::Database::DatabaseUnsupported;

# cpanel - Cpanel/Exception/Database/DatabaseUnsupported.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

=encoding utf-8

=head1 NAME

Cpanel::Exception::Database::DatabaseUnsupported

=head1 SYNOPSIS

 Cpanel::Exception::create( 'Database::DatabaseUnsupported', [
    version => $target_version,
    os => $current_os
 ]);

=head1 DESCRIPTION

This exception class is for representing when a user tries to upgrade to a
unsupported database version for their operating system

=cut

sub _default_phrase {
    my ($self) = @_;
    return Cpanel::LocaleString->new(
        "[_1] is not supported on [_2].",
        $self->get('version'),
        $self->get('os'),
    );
}

1;
