package Cpanel::STDERRCapture;

# cpanel - Cpanel/STDERRCapture.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# =======================================================
# *******************************************************
#     ___  ___________________   ________________  _   __
#    /   |/_  __/_  __/ ____/ | / /_  __/  _/ __ \/ | / /
#   / /| | / /   / / / __/ /  |/ / / /  / // / / /  |/ /
#  / ___ |/ /   / / / /___/ /|  / / / _/ // /_/ / /|  /
# /_/  |_/_/   /_/ /_____/_/ |_/ /_/ /___/\____/_/ |_/
#
# *******************************************************
# =======================================================
#
# DO NOT USE THIS MODULE IN NEW CODE.
# It is here for one legacy use case, the removal of which is not currently practical.

use strict;
use Cpanel::Logger;

our $logger;

sub TIEHANDLE {
    my $class = shift;
    return bless [], $class;
}

# Capture output and send it to the logger object.
sub PRINT {
    my $self = shift;
    $logger ||= Cpanel::Logger->new();
    chomp( my $msg = "@_" );
    return $logger->info($msg);
}

# printf is equivalent to print FILEHANDLE sprintf(FORMAT, LIST).
sub PRINTF {
    my ( $self, $format, @vars ) = @_;
    $logger ||= Cpanel::Logger->new();
    my $msg = sprintf( $format, @vars );
    return $logger->info($msg);
}

# read() returns 0 at end-of-file.
sub READ {
    return 0;
}

# WRITE actually maps from syswrite, not write.
sub WRITE {
    my ( $self, $msg ) = @_;
    $logger ||= Cpanel::Logger->new();
    chomp $msg;
    return $logger->info($msg);
}

# perl -MDevel::Peek -e'my $a = readline STDERR; Devel::Peek::Dump($a);'
sub READLINE {
    return q{};
}

# getc() returns undef at end-of-file.
sub GETC {
    return undef;
}

# $logger is already open for business
sub OPEN {
    return 1;
}

# $logger doesn't care about encoding
sub BINMODE {
    return 1;
}

# perl -e 'print eof STDERR;'
sub EOF {
    return 1;
}

# perl -e 'print tell STDERR;'
sub TELL {
    return 0;
}

# perl -e 'print fileno(STDERR)'
sub FILENO {
    return 2;
}

# According to Tie/Filehandle.pm, SEEK should test for end-of-file.
sub SEEK {
    return 1;
}

# $logger object need not be closed...
sub CLOSE {
    return 1;
}

# ...nor destroyed.
sub DESTROY {
    return 1;
}

1;
