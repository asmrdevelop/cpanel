package Cpanel::Streamer::ReportUtil;

# cpanel - Cpanel/Streamer/ReportUtil.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Streamer::ReportUtil

=head1 DESCRIPTION

This module is not itself a L<Cpanel::Streamer> subclass; rather, it
simplifies use cases where such a subclass wants to:

=over

=item * Report L<Cpanel::Exception> error IDs to its parent.

=item * Optionally identify specific error I<classes> in the subprocesses
to report via specific process exit codes.

=back

=cut

#----------------------------------------------------------------------

use Socket ();

use Cpanel::ForkAsync ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 start_reporter_child( %OPTS )

%OPTS are:

=over

=item * C<streamer> - A L<Cpanel::Streamer> instance.

=item * C<todo_cr> - A code reference to execute in the child process.
The code reference will receive a paired socket whose peer will be
assigned as C<streamer>’s C<from> and C<to> filehandles.

=item * C<get_exit_code_for_error> - Optional, a code reference that
translates an exception into a process exit code. If defined, and if
it returns something other than undef, that return will be the process’s
exit code. This is useful for, e.g., communicating specific failure types
to callers.

=back

In addition to C<from> and C<to>, C<streamer>’s C<pid> attribute is also
assigned. Further attributes may be created, but these are not meant for
use outside this module.

=cut

sub start_reporter_child (%opts) {
    my $streamer = $opts{'streamer'} || die 'need “streamer”';
    my $todo_cr  = $opts{'todo_cr'}  || die 'need “todo_cr”';

    socketpair my $parent_s, my $child_s, Socket::AF_UNIX(), Socket::SOCK_STREAM(), 0 or die "socketpair: $!";

    pipe my $err_r, my $err_w;

    my $class = ref $streamer;

    my $cpid = Cpanel::ForkAsync::do_in_child(
        sub {
            local $0 = $class;

            close $parent_s;
            close $err_r;

            my $ok = eval { $todo_cr->($child_s); 1 };

            close $child_s;

            if ($ok) {
                close $err_w;
            }
            else {
                my $err = $@;

                if ( !ref $err ) {
                    require Cpanel::Exception;
                    $err = Cpanel::Exception->create_raw($err);
                }

                if ( ( ref $err )->isa('Cpanel::Exception') ) {
                    my $id = $err->id();

                    syswrite $err_w, $id or do {
                        warn "Failed to write error ID “$id” to pipe: $!";
                    };
                }

                close $err_w;

                my $cr = $opts{'get_exit_code_for_error'};

                # This has to be published globally since $! is what
                # Cpanel::ForkAsync uses to determine the exit code.
                $! = $cr && $cr->($err);    ## no critic qw(RequireLocalizedPunctuationVars)

                local $@ = $err;
                die;
            }
        }
    );

    close $child_s;
    close $err_w;

    $parent_s->blocking(0);

    $streamer->import_attrs(
        {
            from => $parent_s,
            to   => $parent_s,
            pid  => $cpid,

            # External tests may depend on this attribute name,
            # so it’s best to leave it as it is.
            _error_fh => $err_r,
        }
    );

    return;
}

=head2 $xid = get_child_error_id( $STREAMER_OBJ )

Retrieves $STREAMER_OBJ’s internally-stored L<Cpanel::Exception> error ID,
or undef if none exists.

B<IMPORTANT:> This doesn’t actually check to see if we’re far enough along
in the process such that there would I<be> an error yet. Consider
C<get_child_error_id_p()> instead.

=cut

sub get_child_error_id ($streamer) {
    if ( !$streamer->attr_exists('_error_id') ) {

        sysread( $streamer->get_attr('_error_fh'), my $buf, 48 ) // do {
            warn "$streamer: Failed to read error ID from pipe: $!";
        };

        $streamer->set_attr( _error_id => $buf );
    }

    return $streamer->get_attr('_error_id');
}

=head2 promise($xid) = get_child_error_id_p( $STREAMER_OBJ )

A promise-returning variant of C<get_child_error_id()>. The returned
promise only resolves once we know whether there is an error or not.

=cut

sub get_child_error_id_p ($streamer) {
    if ( !$streamer->get_attr('_error_id_p') ) {
        my $p;

        if ( $streamer->attr_exists('_error_id') ) {
            $p = Promise::XS::resolved( $streamer->get_attr('_error_id') );
        }
        else {
            my $d = Promise::XS::deferred();

            my $fh = $streamer->get_attr('_error_fh');

            require Scalar::Util;
            my $weak_streamer = $streamer;
            Scalar::Util::weaken($weak_streamer);

            my $w;
            $w = AnyEvent->io(
                fh   => $fh,
                poll => 'r',
                cb   => sub {
                    my $got = sysread( $fh, my $buf, 48 );

                    if ( defined $got ) {
                        $weak_streamer->set_attr( '_error_id', $buf );
                        $d->resolve($buf);
                    }
                    else {
                        $d->reject("$streamer: Failed to read error ID from pipe: $!");
                    }

                    undef $w;
                },
            );

            $p = $d->promise();
        }

        $streamer->set_attr( '_error_id_p', $p );
    }

    return $streamer->get_attr('_error_id_p');
}

1;
