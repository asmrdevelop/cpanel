package Cpanel::Init::Script;

# cpanel - Cpanel/Init/Script.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Cpanel::LoadModule ();
use Cpanel::OS         ();

use Carp qw(croak);

has 'init_dir'   => ( is => 'ro', init_arg => 'init_dir' );
has 'service'    => ( is => 'rw' );
has 'start_prio' => ( is => 'rw', default => '82' );
has 'stop_prio'  => ( is => 'rw', default => '82' );
has 'user'       => ( is => 'rw' );
has 'pidfile'    => ( is => 'rw' );
has 'regex'      => ( is => 'rw' );
has 'script' => (
    is      => 'rw',
    default => sub { [] }
);
has 'commands' => (
    is      => 'rw',
    default => sub { {} }
);
has 'template' => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my ($self)               = @_;
        my $os_specific_template = '/usr/local/cpanel/etc/init/scripts/templates/' . Cpanel::OS::service_manager() . '.tmpl';
        my $generic_template     = '/usr/local/cpanel/etc/init/scripts/templates/generic.tmpl';
        return -e $os_specific_template ? $os_specific_template : $generic_template;
    }
);

sub _generate_shell_code {
    my ( $self, $block ) = @_;

    my $commands = $self->commands;
    my $shellcode;

    if ( ref( $commands->{$block}{'exec'}->[0] ) ) {
        my @shell_cmds;
        foreach my $cmd ( @{ $commands->{$block}{'exec'} } ) {
            push @shell_cmds, join( ' ', @{$cmd} ) . ( ( !$commands->{$block}{'showoutput'} ) ? ' >/dev/null 2>&1' : '' );
        }
        if ( $commands->{$block}{'chained'} ) {
            $shellcode = join( ' && ', @shell_cmds );
        }
        else {
            $shellcode = join( "\n    ", @shell_cmds );
        }
    }
    else {
        $shellcode .= join( ' ', @{ $commands->{$block}{'exec'} } ) . ( ( !$commands->{$block}{'showoutput'} ) ? ' >/dev/null 2>&1' : '' );
    }

    return $shellcode;
}

sub load {
    my ( $self, $args ) = @_;

    croak 'Arguments must be a hash' if ref $args ne 'HASH';

    $self->service( $args->{'service'} );
    $self->start_prio( $args->{'start_prio'} ) if exists $args->{'start_prio'};
    $self->stop_prio( $args->{'stop_prio'} )   if exists $args->{'stop_prio'};
    $self->user( $args->{'user'} );
    $self->pidfile( $args->{'pidfile'} );
    $self->regex( $args->{'regex'} );
    $self->commands( $args->{'commands'} );

    return;
}

sub build {
    my ($self)   = @_;
    my $template = $self->template;
    my $commands = $self->commands;

    my $start  = $self->_generate_shell_code('start');
    my $stop   = $self->_generate_shell_code('stop');
    my $status = $self->_generate_shell_code('status');

    Cpanel::LoadModule::load_perl_module('Cpanel::Template');
    my $script = Cpanel::Template::process_template(
        'cpservice',
        {
            'print'       => 0,
            template_file => $template,
            service       => $self->service,
            start_prio    => $self->start_prio,
            stop_prio     => $self->stop_prio,
            user          => $self->user,
            pidfile       => $self->pidfile,
            regex         => $self->regex,
            start         => $start,
            stop          => $stop,
            status        => $status,
        },
    );

    my @script = split /\n/, $$script;

    return $self->script( \@script );
}

sub install {
    my ($self) = @_;

    my $init_dir = $self->init_dir;
    my $service  = $self->service;
    my $file     = $init_dir . '/' . $service;

    if ( open my $initscript, '>', $file ) {
        foreach my $line ( @{ $self->script } ) {
            print {$initscript} $line . "\n";
        }
    }
    chmod( oct(755), $file );

    return 1;
}

1;
