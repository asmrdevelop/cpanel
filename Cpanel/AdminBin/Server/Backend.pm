package Cpanel::AdminBin::Server::Backend;

# cpanel - Cpanel/AdminBin/Server/Backend.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::AdminBin::Server::Backend - Units of cpsrvd’s admin server logic

=head1 DESCRIPTION

This module is only intended to be called from L<Cpanel::AdminBin::Server>.
If you see anything here that you want to reuse, please refactor it to
another module, then call that module from this one.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie            ();
use Cpanel::Env                ();
use Cpanel::Exception          ();
use Cpanel::LoadFile::ReadFast ();
use Cpanel::ProcessInfo        ();
use Cpanel::Socket::Constants  ();
use Cpanel::Filesys::Virtfs    ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ($SERIALIZED, $FH) = read_request_from_socket($SOCKET)

Returns the serialized payload of the request as well as, if given,
the filehandle that the caller passed.

=cut

sub read_request_from_socket {
    my ($socket) = @_;

    Cpanel::Autodie::recv_sigguard( $socket, my $buf, 1, $Cpanel::Socket::Constants::MSG_PEEK );

    my $fh;

    # IO::FDPass sends a single NUL byte when it passes a file descriptor.
    # Let’s assume that that won’t change.
    if ( $buf eq "\0" ) {
        require Cpanel::FDPass;

        $fh = Cpanel::FDPass::recv($socket) or do {
            die "Received no file descriptor! ($!)";
        };
    }

    # This used to look for "\r\n\r\n", but that seems unneeded?
    Cpanel::LoadFile::ReadFast::read_all_fast( $socket, my $serialized );

    return ( $serialized, $fh );
}

#----------------------------------------------------------------------

=head2 $resp_hr = run_admin_module( %OPTS )

The dispatch layer for subclasses of L<Cpanel::Admin::Base>.

%OPTS are:

=over

=item C<perl_module> - The full name of the Perl module that
houses the function to run.

=item C<function> - The name of the function to run.

=item C<args> - An array reference of args for the C<function>.

=item C<uid> - The calling user’s UID.

=item C<wantarray> - The C<wantarray> value from which to determine
the Perl context (void, scalar, or list) in which to call the function.

=item C<env> - A hash reference to assign to C<%ENV> before C<function>
is called.

=item C<passed_fh> - The filehandle, if any, that the caller gave in
the request. (i.e., for streaming)

=back

The return is a hash reference with the following members:

=over

=item * C<status> - Truthy on success; falsy otherwise.

=item * C<payload> - Given on success only. Always an array reference.
(This is the return of the passed module’s C<run()> method.)

=item * C<error_id>, C<class>, C<error_string> - Given on failure only.
Derived from the return
of the passed module’s C<handle_untrapped_exception()> method.

=back

=cut

sub run_admin_module {
    my (%OPTS) = @_;

    local %ENV;
    if ( $OPTS{'env'} ) {
        %ENV = %{ $OPTS{'env'} };
    }

    $ENV{'PATH'} = Cpanel::Env::get_safe_path();

    # Important or else stuff like “[asis,IP]” gets into the strings
    # that we give back to the caller.
    local $Cpanel::Exception::LOCALIZE_STRINGS = 1;

    my $payload_ar = eval {

        # cpsrvd has a $SIG{'__DIE__'} handler that no-ops when $^S is
        # truthy; however, $^S doesn’t reliably indicate that we’re in
        # an eval because in cases like this:
        #
        #   use constant Foo => eval { die 'haha' };
        #
        # … it’s possible for $^S to be undef. So since we know we’re
        # in an eval anyway, let’s local out $SIG{'__DIE__'} here.
        #
        local $SIG{'__DIE__'};

        $OPTS{'perl_module'}->run(
            %OPTS{ 'username', 'uid', 'function', 'args', 'wantarray', 'passed_fh' },
        );
    };

    my %data;

    if ($payload_ar) {
        %data = (
            status  => 1,
            payload => $payload_ar,
        );
    }
    else {
        my ( $err_id, $err_class, $err_string, $err_metadata ) = $OPTS{'perl_module'}->handle_untrapped_exception($@);

        %data = (
            status         => 0,
            error_id       => $err_id,
            class          => $err_class,
            error_string   => $err_string,
            error_metadata => $err_metadata,
        );
    }

    return \%data;
}

#----------------------------------------------------------------------

use constant {
    _CPWRAP_BIN_PATH => '/usr/local/cpanel/bin/cpwrap',
};

# Accessed from tests
our $_SKIP_PARENT_CHECK_PATH = '/var/cpanel/skipparentcheck';

=head2 $name = get_rejected_caller_name( $PID, $USER, @ALLOWED_PARENTS )

This implements the parent-check authorization component of
the admin system.

An exception is thrown if @ALLOWED_PARENTS is empty;
this implements cpsrvd’s proscription against that pattern.

If the given $PID refers to a process whose executable path is not
on the module’s list of allowed caller binaries, then the $PID’s
executable path is returned. This state means the request has failed
the parent check and needs to be rejected.

If the given $PID does not refer to a running process,
a L<Cpanel::Exception::ProcessNotRunning> instance is thrown.

Otherwise (i.e., in the success case), undef is returned.

$USER is the username who is attempting to call this adminbin
program, it's required to safely remove jailshell related path
prefixes.

=cut

sub get_rejected_caller_name {
    my ( $caller_pid, $caller_user, @allowed_parents ) = @_;

    die 'Allowed-parents list must not be empty!' if !@allowed_parents;

    my $rejected;

    if ( !grep { $_ eq '*' } @allowed_parents ) {
        if ( !Cpanel::Autodie::exists($_SKIP_PARENT_CHECK_PATH) ) {
            my $caller = Cpanel::ProcessInfo::get_pid_exe($caller_pid) // do {
                die Cpanel::Exception::create( 'ProcessNotRunning', [ pid => $caller_pid ] );
            };

            # If we're called by a user inside a jailed shell the "jail path" will
            # be prepended to our parent exe path
            # e.g. /usr/local/cpanel/cpanel shows up as:
            # /home/virtfs/cpuser/usr/local/cpanel/cpanel

            my $virtfs_dir = $Cpanel::Filesys::Virtfs::virtfs_dir;

            # Some setups move the virtfs directory to an alternat "home" volume
            # and symlink to it from /home/virtfs, we need to check for this.
            # So if $virtfs_dir is a symlink and it is linked to an actual
            # directory, then use that as the $virtfs_dir
            # If it is not a link, or the link is dead, then we don't do the
            # substitution
            if ( defined( my $virtfs_target = readlink $virtfs_dir ) ) {
                if ( -d $virtfs_target ) {
                    $virtfs_dir = $virtfs_target;
                    $virtfs_dir =~ s{/$}{};
                }
            }

            $caller =~ s{^\Q$virtfs_dir/$caller_user\E}{};

            if ( $caller eq _CPWRAP_BIN_PATH() ) {

                # We really care who called cpwrap at this point
                $caller = Cpanel::ProcessInfo::get_pid_exe( Cpanel::ProcessInfo::get_parent_pid($caller_pid) );
                $caller =~ s{^\Q$virtfs_dir/$caller_user\E}{};
            }

            my $is_ok;

            # Reject perl specifically in case someone puts
            # a perl interpreter as one of the @allowed_parents.
            if ( _path_is_perl($caller) ) {
                warn "Uncompiled Perl caller ($caller) is forbidden; see Cpanel::Admin::Base’s documentation for details.\n";
            }
            elsif ( grep { $_ eq $caller } @allowed_parents ) {
                $is_ok = 1;
            }

            $rejected = $caller if !$is_ok;
        }
    }

    return $rejected;
}

# mocked in tests
sub _path_is_perl ($path) {
    return ( '/perl' eq substr( $path, -5 ) );
}

1;
