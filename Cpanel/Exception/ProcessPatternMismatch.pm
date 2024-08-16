package Cpanel::Exception::ProcessPatternMismatch;

# cpanel - Cpanel/Exception/ProcessPatternMismatch.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Parameters:
#   pid
#   pattern
#   cmdline
sub _default_phrase {
    my ($self) = @_;

    my $cmdline = $self->{'_metadata'}{'cmdline'};
    local $self->{'_metadata'}{'cmdline'} = join( q< >, @$cmdline ) if 'ARRAY' eq ref $cmdline;

    return Cpanel::LocaleString->new(
        'The process with ID “[_1]” was invoked with the command “[_2]”, which does not match the given pattern: [_3]',
        @{ $self->{'_metadata'} }{qw(pid cmdline pattern)},
    );
}

1;
