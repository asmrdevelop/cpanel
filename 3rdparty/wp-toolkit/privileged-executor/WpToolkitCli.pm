#  Copyright 1999-2021. Plesk International GmbH. All rights reserved.

package Cpanel::Admin::Modules::Cpanel::WpToolkitCli;

use strict;

use parent ('Cpanel::Admin::Base');

use constant _actions => (
    'execute_command',
);
use IPC::Run;

sub execute_command {
    my ($self, @args) = @_;

    my @commandArgs = ('/usr/local/bin/wp-toolkit', '--not-root-gate');

    push(@commandArgs, '-account-name');
    push(@commandArgs, $self->get_caller_username());

    push(@commandArgs, '-command-code');
    push(@commandArgs, shift(@args));

    push(@commandArgs, '-format');
    push(@commandArgs, 'json');

    @commandArgs = (@commandArgs, @args);

    IPC::Run::run \@commandArgs, \undef, \my $stdout, \my $stderr;

    return ($stdout, $stderr, $?);
}

1;
