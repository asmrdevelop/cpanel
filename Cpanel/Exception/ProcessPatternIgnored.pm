package Cpanel::Exception::ProcessPatternIgnored;

# cpanel - Cpanel/Exception/ProcessPatternIgnored.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::ProcessPatternIgnored

=head1 SYNOPSIS

    Cpanel::Exception::create( 'ProcessPatternIgnored', [ pid => $self->{'_pid'}->pid(), cmdline => $found ] );

=head1 DESCRIPTION

This exception class is for representing when a process is excluded
from matching by Cpanel::Services::Command::should_ignore_this_command

=cut

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Parameters:
#   pid
#   cmdline
sub _default_phrase {
    my ($self) = @_;

    my $cmdline = $self->{'_metadata'}{'cmdline'};
    local $self->{'_metadata'}{'cmdline'} = join( q< >, @$cmdline ) if 'ARRAY' eq ref $cmdline;

    # Cpanel::Services::Command::should_ignore_this_command match
    return Cpanel::LocaleString->new(
        'The process with ID “[_1]” was invoked with the command “[_2]”, which the system explicitly ignores.',
        @{ $self->{'_metadata'} }{qw(pid cmdline)},
    );
}

1;
