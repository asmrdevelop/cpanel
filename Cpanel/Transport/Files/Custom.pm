
# cpanel - Cpanel/Transport/Files/Custom.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Files::Custom;

use strict;
use Cpanel::Locale              ();
use Cpanel::Transport::Response ();

use parent 'Cpanel::Transport::Files';
my $locale;

sub new {
    my ( $class, $OPTS, $CFG ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    _check_host($OPTS);

    my $self = bless $OPTS, $class;
    $self->{'config'} = $CFG;

    return $self;
}

sub _missing_parameters {
    my ($param_hashref) = @_;

    my @result = ();
    foreach my $key (qw/script/) {
        if ( !defined $param_hashref->{$key} ) {
            push @result, $key;
        }
    }

    my %defaults = (
        'path'    => '',
        'timeout' => '30',
    );
    foreach my $key ( keys %defaults ) {
        if ( !defined $param_hashref->{$key} ) {
            $param_hashref->{$key} = $defaults{$key};
        }
    }

    return @result;
}

sub _get_valid_parameters {
    return qw/host username password path timeout script/;
}

sub _validate_parameters {
    my ($param_hashref) = @_;
    my @result = ();

    if ( !defined $param_hashref->{'script'} or !-x $param_hashref->{'script'} ) {
        push @result, 'script';
    }

    return @result;
}

sub _check_host {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ($OPTS) = @_;

    my @missing = _missing_parameters($OPTS);
    if (@missing) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', __PACKAGE__, \@missing ),
            \@missing
        );
    }

    my @invalid = _validate_parameters($OPTS);
    if (@invalid) {
        die Cpanel::Transport::Exception::InvalidParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” the following parameters were invalid: [list_and,_2]', __PACKAGE__, \@invalid ),
            \@invalid
        );
    }

    # This is the remote directory we are under
    # We can't use chdir/pwd in the traditional sense since
    # we have to restart the script each time
    $OPTS->{'remote_dir'} = '/';
    return $OPTS->{'remote_dir'};
}

#
# Invokes the script to run the command.  Call with command + args
# Dies if it encounters an error
#
sub _run_command {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ( $self, $cmd, @args ) = @_;

    # We are going to pass to the script:  cmd, remote_dir, args, & optionally host, user, pw
    unshift @args, $self->{'remote_dir'};
    unshift @args, $cmd;
    push @args, $self->{'host'}     if $self->{'host'};
    push @args, $self->{'username'} if $self->{'username'};

    # Read timeout is the main governor of exiting early. If your script
    # does not print something by your timeout, we should exit early.
    # Overall, however, I see no justifiable reason for having a custom
    # transport run longer than 24 hours, as by that point, a new backup
    # process could feasibly have been started.
    require Cpanel::SafeRun::Object;
    my $run = Cpanel::SafeRun::Object->new(
        'program'      => $self->{'script'},
        'args'         => \@args,
        'timeout'      => 86400,
        'read_timeout' => $self->{'timeout'},
        'before_exec'  => sub { $ENV{'PASSWORD'} = $self->{'password'} || '' },
    );

    if ( $run->CHILD_ERROR() ) {
        my $msg = join( q< >, map { $run->$_() // () } qw( stderr ) ) || $run->autopsy();
        die Cpanel::Transport::Exception->new( \@_, 0, 'Connection Timeout' ) if $run->timed_out();
        die Cpanel::Transport::Exception->new( \@_, 0, $msg );
    }

    return $run->stdout();
}

#
# Copy a file to our destination directory
#
sub _put {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ( $self, $local, $remote ) = @_;

    $self->_run_command( 'put', $local, $remote );

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

#
# Get a file from the destination directory
#
sub _get {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ( $self, $remote, $local ) = @_;

    $self->_run_command( 'get', $remote, $local );

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _ls {    ## no critic(RequireArgUnpacking) - passing all args for exception/response
    my ( $self, $path ) = @_;

    my $results = $self->_run_command( 'ls', $path );
    my @ls      = split /\n/, $results;

    if ( !@ls ) {
        die Cpanel::Transport::Exception::PathNotFound->new(
            \@_, 0,
            $locale->maketext( 'The specified path does not exist: [_1]', $path )
        );
    }

    my @response = map { $self->_parse_ls_response($_) } @ls;
    return Cpanel::Transport::Response::ls->new( \@_, 1, 'OK', \@response );
}

sub _mkdir {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ( $self, $path ) = @_;

    $self->_run_command( 'mkdir', $path );

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _chdir {    ## no critic(RequireArgUnpacking) - passing all args for exception/response
    my ( $self, $path ) = @_;

    # The script should throw an error if the directory is invalid
    # And it should return the new path it is now under, i.e. a pwd
    $self->{'remote_dir'} = $self->_run_command( 'chdir', $path );

    # If we got back nothing, throw an error
    unless ( $self->{'remote_dir'} ) {
        die Cpanel::Transport::Exception->new( \@_, 0, $locale->maketext( 'Invalid path passed to “[_1]”: [_2]', 'chdir()', $path ) );
    }

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _rmdir {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ( $self, $path ) = @_;

    $self->_run_command( 'rmdir', $path );

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _delete {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ( $self, $path ) = @_;

    $self->_run_command( 'delete', $path );

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _pwd {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ($self) = @_;

    return Cpanel::Transport::Response->new( \@_, 1, 'OK', $self->{'remote_dir'} );
}

1;
