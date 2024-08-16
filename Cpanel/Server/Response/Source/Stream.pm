package Cpanel::Server::Response::Source::Stream;

# cpanel - Cpanel/Server/Response/Source/Stream.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use parent 'Cpanel::Server::Response::Source';

# input_handle    - an object (typically an IO::Handle) that the data will be read from
# content-length  - The length of the content to be read from input_handle if known
sub new {
    my ( $class, %OPTS ) = @_;

    my $self = $class->SUPER::new(%OPTS);

    foreach my $required (qw(input_handle content-type content-length)) {
        if ( !defined $OPTS{$required} ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'MissingParameter', [ name => $required ] );
        }
    }

    $self->{'input_handle'}   = $OPTS{'input_handle'};
    $self->{'content-length'} = $OPTS{'content-length'};

    return bless $self, $class;
}

1;
__END__
