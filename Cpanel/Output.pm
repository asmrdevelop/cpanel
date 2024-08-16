package Cpanel::Output;

# cpanel - Cpanel/Output.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

# Stolen from Cpanel::Debug
our $debug = ( exists $ENV{'CPANEL_DEBUG_LEVEL'} && $ENV{'CPANEL_DEBUG_LEVEL'} ? int $ENV{'CPANEL_DEBUG_LEVEL'} : 0 );

# Make updatenow.static continue to function
# even though JSON::XS has not yet been installed
# so new cPanel installs continue to function.
eval {
    local $SIG{'__WARN__'};
    local $SIG{'__DIE__'};
    require Cpanel::JSON;
};

###########################################################################
# The intent of this module is to output a JSON encoded message
# to a log file for display processing in another application
# (such as the frontend or a remote server via live_tail_log.cgi).
###########################################################################

my $locale;

# Constants
our $SOURCE_NONE      = '';
our $SOURCE_LOCAL     = 0;
our $SOURCE_REMOTE    = 1;
our $COMPLETE_MESSAGE = 0;
our $PARTIAL_MESSAGE  = 1;

our $PREPENDED_MESSAGE     = 1;
our $NOT_PREPENDED_MESSAGE = 0;

my @constructor_params = qw(
  source
  filehandle
);

###########################################################################
#
# Method:
#   new
#
# Description:
#   Creates a Cpanel::Output object used to display or trap output
#
# Parameters:
#   'filehandle'              -  Optional: A file handle to write the data to (STDOUT is the default)
#   'parent'                  -  Optional: A datastructure that will be passed to the renderer
#                                that is used to display a header or other data to be combined with
#                                message.   See Cpanel::Output::Restore for an example of this use.
#
# Exceptions:
#   none
#
# Returns:
#   A Cpanel::Output object
#
sub new {
    my ( $class, %OPTS ) = @_;

    my $self = { map { ( $_ => $OPTS{$_} ) } @constructor_params };
    bless $self, $class;

    $self->{'filehandle'} ||= \*STDOUT;
    $self->{'_parent'} = $OPTS{'parent'};

    $self->{'_indent_level'} = 0;

    $self->_init( \%OPTS ) if $self->can('_init');

    return $self;
}

###########################################################################
#
# Method:
#   message
#
# Description:
#   Sends a message to wherever the Cpanel::Output object is configured
#   to send them
#
# Parameters:
#   $message_type             - The type of message (Ex. out, warn, error)
#   $message_contents         - The contents of the message (Usually a hashref)
#   $source                   - The source of the message (usually the hostname of a server)
#   $partial_message          - The message is part of a message (usually means more is coming and not to terminate with a new line)
#
# Returns:
#   True or False depending on the systems ability to write the message.
#
sub message {
    my ( $self, $message_type, $msg_contents, $source, $partial_message ) = @_;

    $source ||= $self->{'source'};

    # Cpanel::LoadModule::load_perl_module() not used because
    # it’s too heavyweight, and this is already expensive to
    # write a message.
    die "Could not load Cpanel::JSON" if !$INC{'Cpanel/JSON.pm'};

    return $self->_RENDER(
        {
            'indent'   => $self->{'_indent_level'},
            'pid'      => $$,
            'type'     => $message_type,
            'contents' => $msg_contents,
            'partial'  => $partial_message ? $PARTIAL_MESSAGE : $COMPLETE_MESSAGE,
            $self->_MESSAGE_ADDITIONS( $message_type, $msg_contents ),
            ( $source ? ( 'source' => $source ) : () )
        },
    );
}

# Overridable in subclasses
sub _RENDER {
    my ( $self, $msg_hr ) = @_;

    return syswrite(
        $self->{'filehandle'},
        Cpanel::JSON::Dump($msg_hr) . "\n",
    );
}

#for subclasses
sub _MESSAGE_ADDITIONS { }

#Shortcuts that just pass the data on to sub message.
sub error {
    return $_[0]->message( 'error', @_[ 1 .. $#_ ] );
}

sub warn {
    return $_[0]->message( 'warn', @_[ 1 .. $#_ ] );
}

sub success {
    return $_[0]->message( 'success', @_[ 1 .. $#_ ] );
}

sub out {
    return $_[0]->message( 'out', @_[ 1 .. $#_ ] );
}

sub debug {
    return unless $debug;
    return $_[0]->message( 'debug', @_[ 1 .. $#_ ] );
}

# NOTE: These aliases are here so that Cpanel::Output instances are compatible
# with Cpanel::Logger's interface.
# Suppress warns for updatenow.static.
{
    no warnings qw{once};
    *warning = \&warn;
    *info    = \&out;
}

# End Shortcuts

# Shortcuts for rendering common message types
#
sub output_highlighted_message {
    my ( $self, $message ) = @_;

    # This is a parser for a "generic" log file format:
    #
    # Match error
    # Match httpd: bad user name
    # Match httpd: bad group name
    # [Sat Oct 25 23:19:10.489746 2014] [ssl:error] [pid 21385] AH01876: mod_ssl/2.4.10 c
    # [Sat Oct 25 23:19:10.489746 2014] [ssl:warn] [pid 21385] AH01876: mod_ssl/2.4.10 c
    # However, do not match:
    # --log-error=/var/lib/mysql/box.dev.cpanel.net.err
    # Daemon process created, PID 10705 (stderr kept as-is).
    if ( $message =~ m{(?:(?:(?<!log-)error|(?<![a-zA-Z\.])err)[\]\s:]|:\s*bad \S+ name|\* (?:DIE|FATAL)|\] E )}i ) {
        return $self->error($message);
    }
    elsif ( $message =~ m{(?:warn(?:ing)?[\]\s:]|\] W )}i ) {
        return $self->warn($message);
    }
    else {
        return $self->out($message);
    }

    return 1;
}

sub display_message_set {
    my ( $self, $header, $messages ) = @_;

    $self->message( 'header', "$header\n" );

    {
        local $self->{'_indent_level'} = 1 + ( $self->{'_indent_level'} || 0 );

        foreach my $message ( split( m{\n+}, $messages ) ) {
            $self->output_highlighted_message($message);
        }
    }

    return $self->out("\n");
}

sub decrease_indent_level {
    my ($self) = @_;
    if ( !$self->{'_indent_level'} ) {
        CORE::warn("Implementor error! Cannot decrease indent level below 0");
        return;
    }
    return --$self->{'_indent_level'};
}

sub increase_indent_level {
    my ($self) = @_;
    return ++$self->{'_indent_level'};
}

sub get_indent_level ($self) {
    return $self->{'_indent_level'} || 0;
}

sub reset_indent_level {
    my ($self) = @_;
    return ( $self->{'_indent_level'} = 0 );
}

sub create_indent_guard ($self) {
    local ( $@, $! );
    require Cpanel::Context;
    require Cpanel::Finally;

    Cpanel::Context::must_not_be_void();

    $self->increase_indent_level();

    return Cpanel::Finally->new(
        sub {
            $self->decrease_indent_level();
        }
    );
}

sub set_source {
    my ( $self, $source ) = @_;

    $self->{'source'} = $source;
    return 1;
}

sub TO_JSON {
    return '*Cpanel::Output::dummy';
}
1;
