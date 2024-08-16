package Cpanel::SafeRun::Extra;

# cpanel - Cpanel/SafeRun/Extra.pm                 Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::SafeRun::Object';

use Cpanel::IOCallbackWriteLine ();

=encoding utf-8

=head1 NAME

Cpanel::SafeRun::Extra - SafeRun::Object with some extra options

=head1 SYNOPSIS

    use Cpanel::SafeRun::Extra ();

    my $run = Cpanel::SafeRun::Extra->new( # or new_or_die, ...

            ## Use any regular option from SafeRun::Object

            'program' => q[/bin/your-command],
            'args'    => \@some_args,
            ...,

            ## Add some extra arguments parsed by SafeRun::Extra

            ## capture the output to a buffer (SV)

            stdout_buffer => \$stdout_buffer,
            stderr_buffer => \$sterr_buffer,
            # or set both at the same time
            buffer        => \$stdout_and_stderr_buffer,

            ## provide a logger to log stdout and stderr output

            logger        => $logger_object,

            ## keep some env (use one syntax)

            ## - preserve a single env
            envs          => 'ONLY_ONE',
            ## - preserve multiple envs
            envs          => [ qw{ KEEP MULTIPLE ENV } ],
            ## - set multiple env values
            envs          => { KEY => 'value', ... },
    );

=head1 DESCRIPTION

This package provides some syntactic sugar on top of Cpanel::SafeRun::Object.
It teaches a few extra common and useful options to avoid some boilerplates.

=over

=item env - scalar, ArrayRef, or HashRef

List the keys of ENV you want to preserve during the call.
When used as a HashRef you are also providing the values to use.

=item logger - a logger object

This will automatically log the output to the level 'info' (stdout) and 'error' (stderr).

=item stderr_buffer - scalar reference

Allow to accumulate stderr output.

=item stdout_buffer -  scalar reference

Allow to accumulate stdout output.

=item buffer - scalar reference

This is an alias for `sterr_buffer` and `stdout_buffer` to avoid defining both
to the same value.

=back

=cut

sub new ( $class, %opts ) {

    my $_opts = bless \%opts, 'Cpanel::SafeRun::Extra::Opts';

    $_opts->_handle_logger;
    $_opts->_handle_buffers;
    $_opts->_handle_keep_env;
    $_opts->_setup_hooks;

    return $class->SUPER::new( $_opts->%* );
}

1;

package    # internal package
  Cpanel::SafeRun::Extra::Opts;

use Cpanel::Exception ();

=head2 _handle_keep_env( $self )

Internal helper to preserve environment variables using the 'envs' option.
This can be a sclar, ArrayRef or HashRef.

=cut

sub _handle_keep_env ($self) {

    my $keep_env = delete $self->{envs};
    return                  unless defined $keep_env;
    $keep_env = [$keep_env] unless ref $keep_env;

    my %_env;
    if ( ref $keep_env eq 'ARRAY' ) {
        return unless scalar $keep_env->@*;
        foreach my $k ( $keep_env->@* ) {
            $_env{$k} = $ENV{$k};
        }
    }
    elsif ( ref $keep_env eq 'HASH' ) {
        return unless scalar keys $keep_env->%*;
        %_env = %$keep_env;
    }

    my $original = $self->{before_exec};

    # plug the before_exec option
    $self->{before_exec} = sub {

        # restore the explicitely requested env
        @ENV{ keys %_env } = values %_env;
        $original->() if $original;
        return;
    };

    return;
}

=head2 _handle_logger( $self )

Internal helper to provide some 'stdout' and 'stderr' hooks
using the standard logger.

=cut

sub _handle_logger ($self) {
    return unless ref $self;

    return unless defined $self->{logger};
    my $logger = delete $self->{logger};

    if ( my $log = $logger->can('info') ) {
        $self->_add_hook(
            'stdout',
            sub ($line) {
                return unless defined $line;
                $log->( $logger, $line );
                return;
            }
        );
        $self->_add_hook(
            'stderr',
            sub ($line) {
                return unless defined $line;
                $log->( $logger, $line );
                return;
            }
        );
    }

    return;
}

=head2 _handle_buffers( $self )

Internal helper to provide some 'stdout' and 'stderr' hooks
using the standard logger.

=cut

sub _handle_buffers ($self) {

    if ( $self->{buffer} ) {    # one to rule all
        my $buffer = delete $self->{buffer};
        $self->{stderr_buffer} //= $buffer;
        $self->{stdout_buffer} //= $buffer;
    }

    if ( my $buffer = $self->{stderr_buffer} ) {
        $self->_add_hook(
            'stderr',
            sub ($line) {
                return unless length $line;
                $$buffer //= '';
                $$buffer .= $line;
                return;
            }
        );
    }

    if ( my $buffer = $self->{stdout_buffer} ) {
        $self->_add_hook(
            'stdout',
            sub ($line) {
                return unless length $line;
                $$buffer //= '';
                $$buffer .= $line;
                return;
            }
        );
    }

    return;
}

sub _add_hook ( $self, $level, $hook ) {
    my $k = qq[_hooks_for_$level];

    $self->{$k} //= [];
    push $self->{$k}->@*, $hook;

    return;
}

sub _setup_hooks ($self) {

    foreach my $level (qw{stdout stderr}) {

        my $hooks = delete $self->{"_hooks_for_$level"};
        next unless $hooks;

        if ( defined $self->{$level} ) {
            die Cpanel::Exception::create_raw( 'InvalidParameter', "Cannot capture output when “$level” parameter is used." );
        }

        $self->{$level} = Cpanel::IOCallbackWriteLine->new(
            sub ($line) {
                foreach my $h (@$hooks) {
                    $h->($line);
                }
                return;
            }
        );
    }

    return;
}

1;
