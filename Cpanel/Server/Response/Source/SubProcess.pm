package Cpanel::Server::Response::Source::SubProcess;

# cpanel - Cpanel/Server/Response/Source/SubProcess.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();

use parent 'Cpanel::Server::Response::Source';

use constant input_handle_read_function_name => 'sysread';

# input_handle    - an object (typically an IO::Handle) that the data will be read from
#                   XXX IMPORTANT: “input_handle” MUST have an empty PerlIO buffer!
sub new {
    my ( $class, %OPTS ) = @_;

    my $self = $class->SUPER::new(%OPTS);

    $self->{'input_handle'}                   = $OPTS{'input_handle'} // die Cpanel::Exception::create( 'MissingParameter', [ name => 'input_handle' ] );
    $self->{'input_handle_never_used_perlio'} = 1;

    return bless $self, $class;

}

1;
__END__

package main;

my $header_parser =  Cpanel::Server::Response::Source::SubProcess->new();
my $headers       = "HTTP/1.0 200 OK\r\nContent-Length: 90\r\nFrog: dog\r\nStatus: 200 zombies\r\nServer: lover\r\nConnection: eat\r\nContent-Type: text/html\r\n\r\ndogs\npig\ncow<html>test";
my $ret           = $header_parser->parse_and_consume( \$headers );
print "[$ret][$headers]\n";
use Data::Dumper;
print STDERR Dumper($header_parser);
