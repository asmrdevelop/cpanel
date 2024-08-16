package Cpanel::TaskProcessors::SpriteTasks;

# cpanel - Cpanel/TaskProcessors/SpriteTasks.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::SpriteTasks::SpriteGenerator;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'sprite_generator',
                'cmd'    => '/usr/local/cpanel/bin/sprite_generator',
            }
        );

        return;
    }

}

sub to_register {
    return ( [ 'sprite_generator', Cpanel::TaskProcessors::SpriteTasks::SpriteGenerator->new() ] );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::SpriteTasks - Task processor for running some Sprite Account maintenance

=head1 VERSION

This document describes Cpanel::TaskProcessors::SpriteTasks version 0.0.1


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::SpriteTasks;

=head1 DESCRIPTION

Implement the code for the I<sprite_generator> Tasks. These are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::SpriteTasks::to_register

Used by the L<cPanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::SpriteTasks::SpriteGenerator

This is a thin wrapper around sprite_generator

=head1 INCOMPATIBILITIES

None reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2019, cPanel, L.L.C All rights reserved.
