package Whostmgr::Remote::CommandStream::Legacy;

# cpanel - Whostmgr/Remote/CommandStream/Legacy.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Remote::CommandStream::Legacy

=head1 SYNOPSIS

    my $remoteobj = Whostmgr::Remote::CommandStream::Legacy->new(
        {
            host => 'some.remote.host',
            user => 'johnny',
            password => 'secret!',
            tls_verification => 'on',
        }
    );

=head1 BEFORE USING THIS MODULE

Try to avoid this module unless you need SSH to work as an alternative
transport backend. If you can work with I<just> CommandStream—as
hopefully new projects can—then just use
L<Cpanel::CommandStream::Client::Requestor> directly, possibly refactoring
this module’s WebSocket logic along the way.

If you know you need the WebSocket transport—which, as of this writing,
is the I<only> transport—then you might like
L<Cpanel::CommandStream::Client::WebSocket>.

=head1 DESCRIPTION

This class creates a L<Cpanel::CommandStream::Client::Requestor> instance
using cpsrvd’s CommandStream WebSocket endpoint
(cf. L<Cpanel::Server::WebSocket::whostmgr::CommandStream>). It then
wraps that object with logic that attempts to implement
L<Whostmgr::Remote>’s interface as closely and as usefully as possible.

It ultimately subclasses L<Whostmgr::Remote::Base>. Except as noted
below, an instance of this class should be interchangeable with a
L<Whostmgr::Remote> instance.

=cut

=head1 HANDY ONE-LINER

    perl -MWhostmgr::Remote::CommandStream::Legacy -MData::Dumper -e'print Dumper( Whostmgr::Remote::CommandStream::Legacy->new( { host => "localhost", tls_verification => "off", user => "superduper", password => "XXXX" } )->remoteexec( cmd => "echo hello" ) )'

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::CommandStream::Client::WebSocket::Base::Password',
    'Whostmgr::Remote::Base',
);

use Cpanel::Imports;

use AnyEvent ();

use Cpanel::Exception                   ();
use Cpanel::PromiseUtils                ();
use Cpanel::IOCallbackWriteLine::Buffer ();
use Whostmgr::Remote::State             ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Required %OPTS are C<host>, C<user>, C<password>, and
C<tls_verification> (either C<on> or C<off>).

Optional %OPTS are C<scriptdir> and C<enable_custom_pkgacct>.

These have the same significance as in L<Whostmgr::Remote>’s
constructor, but note that C<password> is required here.
(C<tls_verification>, of course, is specific to this interface.)

B<NOTE:> The underlying connections are reaped when $obj is
garbage-collected.

=cut

my @REQUIRED;
BEGIN { @REQUIRED = qw( host user password tls_verification ) }

sub new ( $class, $opts_hr ) {
    my @missing = grep { !length $opts_hr->{$_} } @REQUIRED;
    die "missing: @missing" if @missing;

    my %opts = %$opts_hr;
    $opts{'hostname'} = delete $opts{'host'};
    $opts{'username'} = delete $opts{'user'};

    my $self = $class->SUPER::new(%opts);
    $self->{'host'} = $self->{'hostname'};
    $self->{'user'} = $self->{'username'};

    $self->{$_} = $opts_hr->{$_}
      for (
        'scriptdir',
        'enable_custom_pkgacct',
      );

    return $self;
}

=head2 I<OBJ>->connect_or_die()

Makes a connection using the parameters given to C<new()>, if one
has not already been made. If a connection has already been made,
then this does nothing.

Nothing is returned; an exception is thrown if there is any failure
to connect.

=cut

sub connect_or_die ($self) {
    my $result = Cpanel::PromiseUtils::wait_anyevent(
        $self->_Get_requestor_p(),
    );

    if ( my $err = $result->error() ) {
        die Cpanel::Exception->create_raw($err);
    }

    return;
}

=head2 @out = remoteexec(%opts)

Mimics the same-named method of L<Whostmgr::Remote>.

Differences:

=over

=item * This refuses to run C<pkgacct>. (See the code for why.)
As a result, @out[3, 4, 5, 6, 8] are all undef.

=item * This doesn’t do any root escalation. As a result, $out[9]
is undef.

=item * Since CommandStream provides direct I/O with the executed
subprocess there is no need for shell-oddity workarounds as
L<Whostmgr::Remote> has to do. Thus, $out[2] and $out[7] are identical.

=back

=cut

# See base class for public interface implementation.

sub _remoteexec_command ( $self, $remote_command_to_exec, %opts ) {    ## no critic qw(ProhibitManyArgs) - mis-parse

    # Refuse to allow pkgacct here because pkgacct needs to stream
    # so that clients see the updates in real-time,
    # whereas this function blocks until the command has finished.
    #
    # Transfers are supposed to live-tail a backgrounded pkgacct log
    # anyway, so neither this module should never actually need to
    # run pkgacct. Whostmgr::Remote might still need to do it in the
    # case of a transfer from a quite-old cP source server, but since
    # this module long postdates the switchover to background pkgacct
    # that’s not something we should ever have to do here.
    #
    my $program = ( $remote_command_to_exec =~ m<\A([^ ]+)> );
    if ( $program =~ m<pkgacct> ) {
        die 'pkgacct is wrong for this interface.';
    }

    my $cv = AnyEvent->condvar();

    my $output = q<>;

    my $print_output_yn = !$opts{'returnresult'};

    my $linebuf = $opts{'callback'} && do {
        Cpanel::IOCallbackWriteLine::Buffer->new( $opts{'callback'} );
    };

    my $err_linebuf = Cpanel::IOCallbackWriteLine::Buffer->new(
        \&_print_stderr_line_or_chunk,
    );

    my $exec_p = $self->_Exec(
        command => [ '/bin/sh', '-c', $remote_command_to_exec ],

        stdout => sub ($chunk) {
            print $chunk if $print_output_yn;

            $output .= $chunk;

            $linebuf->feed($chunk) if $linebuf;
        },

        stderr => sub ($chunk) {
            $err_linebuf->feed($chunk);
        },

        before_exec_cr => sub {
            print "$opts{'txt'} …\n" if $opts{'txt'};
        },
    )->then(
        sub ($errstatus) {
            $linebuf->clear() if $linebuf;
            $err_linebuf->clear();

            if ($errstatus) {
                require Cpanel::ChildErrorStringifier;
                my $ces = Cpanel::ChildErrorStringifier->new($errstatus);

                my $msg = "Remote “$remote_command_to_exec”: " . $ces->autopsy();

                warn "$msg\n";
            }
        },
    );

    my $result = Cpanel::PromiseUtils::wait_anyevent($exec_p);

    return ( 0, $result->error() ) if $result->error();

    return (
        1,
        locale()->maketext('Success'),

        # In Whostmgr::Remote this is the “raw” output, which includes
        # all of the extra output that compensates for shell normalization.
        $output,

        # In Whostmgr::Remote this is all pkgacct stuff.
        (undef) x 4,
        $output,
    );
}

sub _print_stderr_line_or_chunk ($line) {
    $line .= "\n" if $line !~ m<\n\z>;

    print $Whostmgr::Remote::State::ERROR_PREFIX . $line;

    return;
}

sub _multi_exec_shell_commands ( $self, $commands_hr ) {
    my @promises;

    my %key_result;

    my $requestor_p = $self->_Get_requestor_p();

    my $promise_tracker = $self->_Get_promise_tracker();

    # This is a hashref, not an array, so that each coderef can
    # remove itself. That way if the connection goes down partway
    # through a set of commands we won’t redo the cleanup for any
    # requests that already succeeded.
    my %cleanup_crs;

    for my $key ( keys %$commands_hr ) {
        my $cmd_hr = $commands_hr->{$key};

        $key_result{$key} = q<>;

        my $result_sr = \$key_result{$key};

        my $full_cmd = "LC_ALL=$cmd_hr->{'locale'} $cmd_hr->{'command'}";

        push @promises, $requestor_p->then(
            sub ($requestor) {

                my $exec = $requestor->request(
                    'exec',
                    command => [ '/bin/sh', '-c', $full_cmd ],
                );

                my $subscr = $exec->create_stdout_subscription(
                    sub ($chunk) {
                        $$result_sr .= $chunk;
                    }
                );

                my $stderr     = q<>;
                my $err_subscr = $exec->create_stderr_subscription(
                    sub ($txt) {
                        $stderr .= $txt;
                    }
                );

                my $rethrown = $exec->promise()->catch(
                    sub ($why) {
                        die "“$full_cmd” failed: $why\n";
                    }
                );

                my $cleanup_cr_str;

                my $cleanup_cr = sub {
                    delete $cleanup_crs{$cleanup_cr_str};

                    undef $err_subscr;
                    undef $subscr;

                    for my $line ( split m<\n>, $stderr ) {
                        _print_stderr_line_or_chunk($line);
                    }
                };

                $cleanup_cr_str = "$cleanup_cr";

                # We need the cleanup logic to run even if the promise
                # tracker’s reject_all() happens.
                $cleanup_crs{$cleanup_cr_str} = $cleanup_cr;

                return $rethrown->finally($cleanup_cr);
            }
        );
    }

    my $all_p = Promise::XS::all(@promises)->then( sub { [@_] } );

    my $big_p = $promise_tracker->add($all_p);

    my $result = Cpanel::PromiseUtils::wait_anyevent($big_p);

    if ( $result->error() ) {
        $_->() for values %cleanup_crs;
        return ( 0, $result->error() );
    }

    return ( 1, \%key_result );
}

sub _remotecopy_post_validation ( $self, %VALS ) {
    if ( $VALS{'direction'} ne 'upload' ) {
        die "Unimplemented remotecopy direction: $VALS{'direction'}";
    }

    my ( $ok, $dest_q ) = $self->_shell_quote( $VALS{'destfile'} );
    return ( 0, "Can’t quote “$VALS{'destfile'}”: $dest_q" ) if !$ok;

    require Cpanel::Autodie;
    Cpanel::Autodie::open( my $rfh, '<', $VALS{'srcfile'} );
    my $perms = ( Cpanel::Autodie::stat($rfh) )[2] & 07777;

    my $source = do { local $/; <$rfh> };

    my $perms_oct = sprintf( '%04o', $perms );

    my $promise = $self->_Get_requestor_p()->then(
        sub ($request) {
            my $exec = $request->request(
                'exec',
                command => [ '/bin/sh', '-c', "/bin/cat > $dest_q && /bin/chmod $perms_oct $dest_q" ],
                stdin   => $source,
            );

            return $exec->promise();
        }
    );

    $promise = $self->_Get_promise_tracker()->add($promise);

    my $result = Cpanel::PromiseUtils::wait_anyevent($promise);

    return ( 0, $result->error() ) if $result->error();

    return 1;
}

1;
