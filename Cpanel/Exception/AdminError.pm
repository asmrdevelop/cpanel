package Cpanel::Exception::AdminError;

# cpanel - Cpanel/Exception/AdminError.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#----------------------------------------------------------------------

=encoding utf-8

=head1 NAME

Cpanel::Exception::AdminError

=head1 SYNOPSIS

    die Cpanel::Exception::create( 'AdminError', [ class => $class, message => $message ] )

=head1 DESCRIPTION

This error class is how admin modules indicate specific failures to
a user process. If this error is thrown in an admin function and not trapped,
the admin dispatch layer will convert it into something that the
user process will receive.

=head1 PARAMETERS

Give either (or both) of the following:

=over

=item * C<class> - A class that the user process should use to recreate
the error. This should be a subclass of L<Cpanel::Exception>. If not given,
the user process will use L<Cpanel::Exception>.

=item * C<message> - A human-readable string that describes the failure.

=back

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

# Params:
#   class
#   message
sub _default_phrase {
    my ($self) = @_;

    my $class = $self->get('class');
    my $msg   = $self->get('message');

    if ( defined $class ) {
        if ( defined $msg ) {
            return Cpanel::LocaleString->new( 'An error ([_1]) occurred: [_2]', $class, $msg );
        }

        return Cpanel::LocaleString->new( 'An error ([_1]) occurred.', $class );
    }
    elsif ( defined $msg ) {
        return Cpanel::LocaleString->new( 'An error occurred: [_1]', $msg );
    }

    warn( ref($self) . ' created with no data!' );
    return Cpanel::LocaleString->new('An unknown error occurred.');
}

1;
