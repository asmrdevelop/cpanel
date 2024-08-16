package Cpanel::ForkSync;

# cpanel - Cpanel/ForkSync.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# XXX This module can’t use signatures because of updatenow.

=encoding utf-8

=head1 NAME

Cpanel::ForkSync

=head1 SYNOPSIS

    my $ran = Cpanel::ForkSync->new(
        sub (@args) {

            # to do in child
            # @args will be ('arg1', 'arg2')
        },
        'arg1',
        'arg2',
    );

=head1 DESCRIPTION

This module subclasses L<Cpanel::ChildErrorStringifier>. It
runs a code block in a child process and makes the return
value available to the parent.

This is useful for forking and reading back a return value from the fork
if you don't need to do a setuid.

B<IMPORTANT:> If you need a setuid in the child, use L<Cpanel::AccessIds>
instead of this module.

This module’s documentation is incomplete because the documentation
postdates the code.

=cut

#----------------------------------------------------------------------

use parent qw(Cpanel::ChildErrorStringifier);

use Try::Tiny;
use Cpanel::ForkAsync          ();
use Cpanel::Exception          ();
use Cpanel::Sereal::Decoder    ();
use Cpanel::FHUtils::Autoflush ();
use Cpanel::LoadFile::ReadFast ();

#----------------------------------------------------------------------

our $quiet;

=head1 METHODS

=head2 $obj = I<CLASS>->new( $CODE, @ARGS )

Executes $CODE with @ARGS in a child process (in list context) and
waits for the child process to end.

The return value is an instance of I<CLASS>.

=cut

sub new {
    my ( $class, $code, @args ) = @_;

    return $class->new_with_parent_callback( undef, $code, @args );
}

=head2 $obj = I<CLASS>->new_with_parent_callback( $PCODE, $CCODE, @ARGS )

Like C<new()>, but $PCODE runs in the parent process before the child
process’s return is collected. ($CCODE is what runs in the child.)

=cut

sub new_with_parent_callback {
    my ( $class, $parent_code, $code, @args ) = @_;

    #So we don't get -1 from waitpid().
    local $SIG{'CHLD'} = 'DEFAULT';

    # PR : parent read
    # CW : child write
    # RC : result content
    my ( $PR, $CW, $RC );
    pipe( $PR, $CW ) or do {
        my $err = $!;
        require Cpanel::Debug;
        Cpanel::Debug::log_die("Failed to pipe(): $err");
    };

    # autoflush() should not be necessary but go ahead and do it if we already have it
    Cpanel::FHUtils::Autoflush::enable($CW);

    my $decoder = Cpanel::Sereal::Decoder::create();

    my $run = sub {
        require Cpanel::Sereal::Encoder;
        my $encoder = Cpanel::Sereal::Encoder::create();

        close $PR or die "close() on parent reader in child failed: $!";
        my ( $err, $ret );
        try {
            $ret = { '_return' => [ $code->(@args) ] };    # if we die/exit here, json is going to be corrupted
        }
        catch {
            $err = $_;

            # The specific fields we have available (class, etc.) will vary depending on whether
            # it's a blessed exception or not.
            $ret = _build_serializable_exception_data($err);
        };

        my $encoded;

        eval { $encoded = $encoder->encode($ret); 1 } or do {
            local ( $@, $! );
            require Cpanel::JSON::Sanitize;

            $ret = Cpanel::JSON::Sanitize::filter_to_json($ret);

            $encoded = $encoder->encode($ret);
        };

        syswrite $CW, $encoded or die "Failed to write: $!";

        close $CW or die "close() on child writer in child failed: $!";
        die $err if $err;

        return;
    };

    my $pid =
      $quiet
      ? Cpanel::ForkAsync::do_in_child_quiet($run)
      : Cpanel::ForkAsync::do_in_child($run);

    close $CW or warn "Parent failed to close child-write: $!";

    if ($parent_code) {
        warn if !eval { $parent_code->(); 1 };
    }

    local $@;
    eval {
        local $SIG{__DIE__};
        local $SIG{__WARN__};

        Cpanel::LoadFile::ReadFast::read_all_fast( $PR, my $buf );

        $RC = $decoder->decode($buf);
    };
    my $retrieve_err = $@;
    close $PR or warn "Parent failed to close parent-read: $!";

    #This prevents overwriting global $?.
    local $?;

    # modern perls is signal safe so no need to
    # use sigsafe_blocking_waitpid
    waitpid( $pid, 0 );

    # If we received structured exception data from the child representing a Cpanel::Exception object,
    # re-bless the most important parts of the object as a Cpanel::UntrustedException. Some child
    # processes will be running as untrusted users, so it's important to use an exception class that's
    # designed to handle this type of data safely.
    if ( ref $RC->{'_structured_exception'} eq 'HASH' && $RC->{'_structured_exception'}{'class'} ) {

        # Special logic to recreate “error” as a dualvar:
        if ( my $errno = delete $RC->{'_structured_exception'}{'metadata_errno'} ) {
            $RC->{'_structured_exception'}{'metadata'}{'error'} = do {
                local $! = $errno;
            };
        }

        require Cpanel::UntrustedException;
        $RC->{'_structured_exception'} = Cpanel::UntrustedException->new(
            class    => $RC->{'_structured_exception'}->{'class'},
            string   => $RC->{'_structured_exception'}->{'string'},
            longmess => $RC->{'_structured_exception'}->{'longmess'},
            metadata => $RC->{'_structured_exception'}->{'metadata'},
        );
    }

    my $self = {
        _CHILD_ERROR          => $?,
        _pid                  => $pid,
        _retrieve_err         => $retrieve_err,
        _return               => $RC->{'_return'},
        _exception            => $RC->{'_exception'},
        _full_exception_text  => $RC->{'_full_exception_text'},
        _structured_exception => $RC->{'_structured_exception'},
    };

    return bless $self, $class;
}

sub new_quiet {
    my ( $package, $code, @args ) = @_;

    local $quiet = 1;
    return $package->new( $code, @args );
}

sub exception {
    my ($self) = @_;

    return $self->{'_exception'};
}

sub full_exception_text {
    my ($self) = @_;

    return $self->{'_full_exception_text'};
}

=head2 $obj = I<OBJ>->structured_exception()

A L<Cpanel::UntrustedException> instance that describes the exception
thrown in the child.

=cut

sub structured_exception {
    my ($self) = @_;

    return $self->{'_structured_exception'};
}

=head2 $err = I<OBJ>->retrieve_error()

The error in the parent that happened while trying to read the child’s
response.

=cut

sub retrieve_error {
    my ($self) = @_;

    return $self->{'_retrieve_err'};
}

=head2 $return_ar = I<OBJ>->return()

Returns an array reference that contains the value(s) (if any) that the child
process’s code block returned.

=cut

sub return {
    my ($self) = @_;

    return $self->{'_return'};
}

=head2 $yn = I<OBJ>->had_error()

Returns a boolean that indicates whether an error happened anywhere
along the way of running the child and collecting its response.

=cut

sub had_error {
    my ($self) = @_;

    return ( $self->CHILD_ERROR() || $self->exception() || $self->retrieve_error() ) ? 1 : 0;
}

=head2 $pid = I<OBJ>->pid()

Returns the (now-ended) child process’s (numeric) identifier.

=cut

sub pid {
    my ($self) = @_;

    return $self->{'_pid'};
}

#----------------------------------------------------------------------
#STATIC

#NOTE: For legacy compatibility, this function publishes to global $?.
#It is probably better to instantiate an instance of this module than to
#call this function. Globals are no fun.
sub do_in_child {
    my ( $code, @args ) = @_;

    if ( !wantarray ) {
        my $given_code = $code;
        $code = sub { return scalar $given_code->(@_) };
    }

    my $run = __PACKAGE__->new( $code, @args );

    $? = $run->CHILD_ERROR();    ## no critic(RequireLocalizedPunctuationVars) -- legacy compatibility

    #This usually means that we exit()ed within $code.
    return undef if $run->retrieve_error() || !defined $run->return() || $run->CHILD_ERROR();

    return wantarray ? @{ $run->return() } : $run->return()->[-1];
}

sub _build_serializable_exception_data {
    my ($err) = @_;

    my ( $_exception, $_full_exception_text, $_structured_exception, $_metadata );
    if ( try { $err->isa('Cpanel::Exception') } ) {
        $_exception            = Cpanel::Exception::get_string($err);    # short message
        $_full_exception_text  = $err . '';                              # force long-form stringification
        $_structured_exception = {
            class    => ref($err),
            string   => $err->get_string,
            longmess => $err->longmess,
            metadata => {},
        };

        for my $attr ( sort keys %{ $err->{'_metadata'} } ) {
            my $value = $err->get($attr);
            if ( !ref($value) ) {    # For now we'll just transport simple scalar values back to the parent to avoid having to deal with weeding blessed objects out from underneath hashes or arrays
                $_structured_exception->{'metadata'}{$attr} = $value;
            }
        }

        # A lot of Cpanel::Exception instances have an “error” metadata
        # item that’s a dualvar.
        if ( my $error = $_structured_exception->{'metadata'}{'error'} ) {
            local $! = $error;
            if ($!) {
                $_structured_exception->{'metadata_errno'} = 0 + $!;
            }
        }
    }
    elsif ( ref($_) eq 'HASH' || ref($_) eq 'ARRAY' ) {
        $_exception            = $err;
        $_full_exception_text  = undef;
        $_structured_exception = $err;
    }
    else {
        $_exception            = $err;
        $_full_exception_text  = $err;
        $_structured_exception = undef;
    }

    return {
        '_return'               => undef,
        '_exception'            => $_exception,
        '_full_exception_text'  => $_full_exception_text,
        '_structured_exception' => $_structured_exception,
        '_metadata'             => $_metadata,
    };
}

1;
