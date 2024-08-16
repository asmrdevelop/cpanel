package Cpanel::CGI::NoForm;

# cpanel - Cpanel/CGI/NoForm.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::CGI::NoForm

=head1 SYNOPSIS

    use parent qw( Cpanel::CGI::NoForm );

    __PACKAGE__->new()->run() if !caller;

    sub _do_initial {
        my ($self) = @_;

        #Uncaught exceptions will prompt a 500, but it’s better
        #to give explicit error codes, like so:

        $self->die( 400, 'HTTP status reason', 'A longer explanation …' );

        $self->die( 500, undef, 'Uses default status reason …' );

        #Print HTTP headers …
    }

    sub _do_interactive { ... }

=head1 DESCRIPTION

This thin framework for a CGI application doesn’t do much, but it does
simplify error reporting.

=head1 METHODS TO IMPLEMENT IN SUBCLASSES

See the SYNOPSIS for examples.

=head2 _do_initial()

REQUIRED. This is where you print the headers and parse
any form input.
Failures here will prompt a 5XX status code.

=head2 _do_interactive()

This can be omitted; if defined, it is executed after C<_do_initial()>.
Failures here are NOT trapped automatically; you need to provide your
own error handling. It’s useful for WebSocket or other interactive
protocols.

=head1 PROVIDED METHODS

=cut

use strict;
use warnings;

use Cpanel::Exception ();
use Cpanel::Autodie ('syswrite_sigguard');

use constant {
    DEFAULT_HTTP_ERROR => 500,
    DEFAULT_REASON     => 'Unknown Failure',
};

BEGIN {
    *_write = *Cpanel::Autodie::syswrite_sigguard;
}

=head2 I<CLASS>->new()

Instantiates this class and returns an instance.

=cut

sub new {
    my ($class) = @_;

    my %self;

    return bless \%self, $class;
}

=head2 I<OBJ>->run()

Runs the script/module. Note that C<$|> is enabled during the execution.

=cut

sub run {
    my ($self) = @_;

    #This originally justified the use of print() in this function;
    #however, since even with this on print() only sends 8,192 bytes
    #at a time, there’s really no good reason to use print() here.
    local $| = 1;

    local $@;
    eval { $self->_do_initial(); 1; } or do {
        my $err = $@;

        if ( !$self->{'_headers_sent'} ) {
            if ( !eval { $err->isa('Cpanel::Exception') } ) {
                $err = Cpanel::Exception->create_raw($err);
            }

            $self->_print_http( DEFAULT_HTTP_ERROR, undef, "XID: " . $err->id() . "\n" );
        }

        local $@ = $err;
        die;
    };

    if ( my $cr = $self->can('_do_interactive') ) {
        $self->{'_initial_done'} = 1;

        $cr->($self);
    }

    return;
}

=head2 I<OBJ>->die( EXPLANATION, CODE, STATUS_STR )

Sends an HTTP-level failure.

CODE is the HTTP error code (e.g., C<404>). If not given,
a default value of C<500> will be used.

STATUS_STR is the HTTP status message, e.g., C<Unauthorized> for C<401>.
If not given, the default string as given in the HTTP specification
will be used.

EXPLANATION is printed as the body of the message, after the
CODE and STATUS_STR.

=cut

sub die {
    my ( $self, $str, $code, $reason ) = @_;

    if ( $self->{'_initial_done'} ) {
        require Carp;
        die "die() is meaningless after do_initial()! " . Carp::longmess();
    }

    $code ||= DEFAULT_HTTP_ERROR;

    ( $reason, $str ) = $self->_print_http( $code, $reason, $str );

    die "$code ($reason): $str";
}

my $_loaded_status_codes;

sub _print_http {
    my ( $self, $code, $reason, $body ) = @_;

    CORE::die 'Already sent headers!' if $self->{'_headers_sent'};

    CORE::die 'Need HTTP code!' if !$code;

    $_loaded_status_codes ||= do {
        local $@;
        eval 'require Cpanel::HTTP::StatusCodes' or 1;    ##no critic qw(ProhibitStringyEval)
    };

    $reason ||= $Cpanel::HTTP::StatusCodes::STATUS_CODES{$code};
    $reason ||= DEFAULT_REASON;

    $body = q<> if !length $body;
    substr( $body, 0, 0, "$code $reason\n" );

    my $pre_body = join(
        "\x0d\x0a",
        "Status: $code $reason",
        "Content-Type: text/plain; charset=utf-8",
        q<>,
        q<>,
    );

    local $@;
    eval { _write( \*STDOUT, $pre_body . $body ); 1 } or do {
        $pre_body =~ tr<\x0d><>d;
        warn "Failed to output to client ($@): $pre_body$body";
    };

    $self->{'_headers_sent'} = 1;

    return ( $reason, $body );
}

1;
