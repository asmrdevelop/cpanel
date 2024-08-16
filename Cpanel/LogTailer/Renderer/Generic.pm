package Cpanel::LogTailer::Renderer::Generic;

# cpanel - Cpanel/LogTailer/Renderer/Generic.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use bytes;
use strict;

sub new {
    my ($class) = @_;

    my $var;
    my $self = \$var;

    return bless $self, $class;
}

sub render_message {
    my ( $self, $message, $logfile ) = @_;

    local $!;

    my $length = length($message);

    chomp($message);    # chomp after the length is taken so we know were to seek in the file

    #Because IE8 is amazing and, in its DOM, converts non-breaking space
    #(i.e., "\xc2\xa0") into a plain space. So we convert those to two
    #regular spaces to avoid certain compatibility problems.
    $message =~ s/\xc2\xa0/  /g;

    # If we do not have a new line the system will fail to render the message correctly
    my $ret = print "$logfile|$length|$message\n" or warn "Failed to print: $!";

    return $ret;
}

sub keepalive {
    my ($self) = @_;

    local $!;
    my $ret = print ".\n" or warn "Failed to print: $!";

    return $ret;
}

1;
