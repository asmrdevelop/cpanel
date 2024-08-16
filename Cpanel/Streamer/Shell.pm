package Cpanel::Streamer::Shell;

# cpanel - Cpanel/Streamer/Shell.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Streamer::Shell - shell streamer application

=head1 SYNOPSIS

    #All args are optional.
    my $streamer = Cpanel::Streamer::Shell->new(
        before_exec => sub { ... },
        rows => 24,
        cols => 80,
    );

=head1 DESCRIPTION

This subclass of L<Cpanel::Streamer> runs a shell session.

Note that the C<from> and C<to> file handles are the same object,
an instance of C<IO::Pty>.

This will clear environment variables as per C<Cpanel::Env::clean_env()>
and then set the C<HOME> and C<TERM> environment variables.

The C<before_exec> parameter is a code reference to be executed immediately
prior to the C<exec()> of the shell. This is where you can set additional
environment variables, raise rlimit settings, etc.

=cut

use parent qw(
  Cpanel::Streamer
);

use IO::Pty ();

use Cpanel::Exec    ();
use Cpanel::PwCache ();
use Cpanel::Autodie ();

use constant {
    _DEFAULT_TERMINAL => 'xterm-256color',
};

#Ideally cpsrvd wouldn’t add these unless they’re needed,
#but that’s unlikely to change. This list is in addition to the
#Cpanel::Env::clean_env() run in _before_exec().
use constant _ENV_VARS_TO_CLEAR => (
    'DOCUMENT_ROOT',
    'SERVER_SOFTWARE',
);

use constant {
    CAGEFS_ENTER => '/bin/cagefs_enter.proxied',
};

=head1 METHODS

=head2 I<OBJ>->terminate()

Identical to the inherited method of the same name except that we
send -SIGHUP rather than SIGTERM to the shell process initially.
(If, after a brief wait time, the shell hasn’t finished its business,
it gets SIGKILL.)

=cut

sub terminate {
    my ( $self, @args ) = @_;

    #Shells seem to ignore SIGTERM, while SIGINT just sends CTRL-C
    #to the shell (i.e., to exit the current subprocess).
    require Cpanel::Kill::Single;
    local $Cpanel::Kill::Single::INITIAL_SAFEKILL_SIGNAL = '-HUP';

    return $self->SUPER::terminate(@args);
}

#----------------------------------------------------------------------

#It might be good to make some of the parameters here configurable.
sub _init {
    my ( $self, %args ) = @_;

    my ( $username, $homedir, $shell ) = ( Cpanel::PwCache::getpwuid_noshadow($>) )[ 0, 7, 8 ];

    if ( !length $shell ) {
        die "“$username” (UID $>) has no shell!";
    }

    if ( !Cpanel::Autodie::exists($shell) ) {
        die "Nonexistent shell: “$shell”\n";
    }
    elsif ( !-x $shell ) {
        die "Non-executable shell: “$shell”\n";
    }

    my $pty = IO::Pty->new();

    #tcsh doesn’t support “--login”, only “-l”.
    #Presumably other shells at least support -l.
    my @cmd = ( $shell, '-l' );

    unshift( @cmd, $self->CAGEFS_ENTER ) if $self->_check_for_cagefs();

    my $cpid = Cpanel::Exec::forked(
        \@cmd,
        sub {

            #Do the stuff that can fail first, then set STDERR.

            if ( length $homedir ) {
                chdir $homedir or die "chdir($homedir): $!";
            }

            my $slv = $pty->slave();

            if ( $args{'rows'} ) {
                $slv->set_winsize( $args{'rows'} // 0, $args{'cols'} // 0 );
            }

            $pty->make_slave_controlling_terminal();
            close $pty or warn "child failed to close master pty: $!";

            open \*STDIN,  '<&=', $slv or die "redirect STDIN: $!";
            open \*STDOUT, '>&=', $slv or die "redirect STDOUT: $!";
            open \*STDERR, '>&=', $slv or die "redirect STDERR: $!";

            require Cpanel::Env;
            Cpanel::Env::clean_env();

            delete @ENV{ _ENV_VARS_TO_CLEAR() };

            @ENV{ 'HOME', 'TERM' } = ( $homedir, $self->_DEFAULT_TERMINAL() );

            $args{'before_exec'}->() if $args{'before_exec'};
        }
    );

    #If this isn’t called here, the parent process won’t notice
    #when the child goes away.
    $pty->close_slave();

    $pty->blocking(0);

    $self->import_attrs(
        {
            from => $pty,
            to   => $pty,
            pid  => $cpid,
        }
    );

    return $self;
}

sub _check_for_cagefs {
    my ($self) = @_;

    if ( $> && Cpanel::Autodie::exists( $self->CAGEFS_ENTER ) ) {
        die $self->CAGEFS_ENTER . " is not executable!"            if !-x _;
        die $self->CAGEFS_ENTER . " does not have setuid enabled!" if !-u _;
        return 1;
    }
    return 0;
}

1;
