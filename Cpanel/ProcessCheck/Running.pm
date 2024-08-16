package Cpanel::ProcessCheck::Running;

# cpanel - Cpanel/ProcessCheck/Running.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Proc::PID ();
use Cpanel::Exception ();
use Cpanel::PwUtils   ();

#This takes:
#   pid
#   pattern
#   user    (name or UID)
sub new {
    my ( $class, %OPTS ) = @_;

    my $pattern = $OPTS{'pattern'};

    if ( !length $pattern ) {
        die Cpanel::Exception::create( 'MissingParameter', 'Supply the “[_1]” parameter.', ['pattern'] );
    }
    elsif ( ref($pattern) && !UNIVERSAL::isa( $pattern, 'Regexp' ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” must be either a scalar or a regular expression reference.', ['pattern'] );
    }

    my $self = {
        _pid                 => Cpanel::Proc::PID->new( $OPTS{'pid'} ),
        _uid                 => Cpanel::PwUtils::normalize_to_uid( $OPTS{'user'} ),
        _pattern             => $pattern,
        _use_services_ignore => $OPTS{'use_services_ignore'} ? 1 : 0,
    };

    return bless $self, $class;
}

sub pid_object {
    my ($self) = @_;

    return $self->{'_pid'};
}

sub check_all {
    my ($self) = @_;

    my $pid_obj = $self->{'_pid'};

    # This die()s when the process isn’t running anymore.
    my $cmdline_ar = $pid_obj->cmdline();

    my $found = "@$cmdline_ar";

    my $regexp = $self->{'_pattern'};
    if ( !ref $regexp ) {
        $regexp = qr(\Q$self->{'_pattern'}\E)i;
    }

    my $suppress = Cpanel::Exception::get_stack_trace_suppressor();

    if ( $found !~ $regexp ) {
        die Cpanel::Exception::create( 'ProcessPatternMismatch', [ pid => $self->{'_pid'}->pid(), pattern => $regexp, cmdline => $found ] );
    }

    # Restartsrv uses this to exclude false
    # postives maches when we check to see
    # if a service is online
    if ( $self->{'_use_services_ignore'} ) {
        require Cpanel::Services::Command;
        if ( Cpanel::Services::Command::should_ignore_this_command($found) ) {
            die Cpanel::Exception::create( 'ProcessPatternIgnored', [ pid => $self->{'_pid'}->pid(), cmdline => $found ] );
        }
    }

    my $euid = $pid_obj->uid();
    if ( $euid ne $self->{'_uid'} ) {
        die Cpanel::Exception::create( 'ProcessEuidMismatch', [ pid => $self->{'_pid'}->pid(), expected => $self->{'_uid'}, found => $euid ] );
    }

    return 1;
}

1;
